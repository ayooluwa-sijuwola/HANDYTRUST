import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/job_model.dart';
import '../../models/job_mutation_context.dart';
import '../errors/job_exceptions.dart';

/// Callback type for [JobService.applyJobUpdateTransaction].
typedef JobUpdateFn = void Function(
  Transaction tx,
  DocumentReference<Map<String, dynamic>> jobRef,
  Map<String, dynamic> currentData,
);

/// ════════════════════════════════════════════════════════════════════════════
/// JobService — single authoritative write layer for /jobs
/// ════════════════════════════════════════════════════════════════════════════
///
/// Invariants enforced on every call:
///   1. All writes go through a Firestore transaction (no bare .update()).
///   2. State transitions are validated against [allowedTransitions] unless
///      the caller supplies an admin override context.
///   3. Every transaction writes an immutable audit log entry atomically:
///         if the job update fails → audit log is NOT written
///         if the audit log write fails → job update is rolled back
///      No partial state is possible.
///   4. Three consistency fields are stamped on every job mutation:
///      lastUpdatedAt, lastUpdatedBy, updateVersion.
///   5. Status-milestone timestamps use FieldValue.serverTimestamp() —
///      no client clock is ever trusted for milestone data.
class JobService {
  final FirebaseFirestore _db;

  JobService(this._db);

  // ─── State machine ────────────────────────────────────────────────────────

  static const allowedTransitions = <JobStatus, Set<JobStatus>>{
    JobStatus.requested: {JobStatus.matched, JobStatus.cancelled},
    JobStatus.matched: {JobStatus.inChat, JobStatus.cancelled},
    JobStatus.inChat: {JobStatus.paymentPending, JobStatus.cancelled},
    JobStatus.paymentPending: {JobStatus.escrowLocked, JobStatus.cancelled},
    // escrowLocked → cancelled removed (Stage 2, policy D2): a funded job is
    // never cancelled by a party — see requestPaidCancellation. Admin
    // settlement goes through adminForceStatus, which bypasses this table.
    JobStatus.escrowLocked: {
      JobStatus.inProgress,
      JobStatus.disputed,
    },
    JobStatus.inProgress: {JobStatus.submitted, JobStatus.disputed},
    // Stage 5 (D4): submitted -> inProgress is the single customer rework
    // request (requestRework); the artisan then resubmits normally.
    JobStatus.submitted: {JobStatus.completed, JobStatus.disputed, JobStatus.inProgress},
    JobStatus.completed: {},
    JobStatus.disputed: {JobStatus.resolved},
    JobStatus.resolved: {},
    JobStatus.cancelled: {},
  };

  static bool isValidTransition(JobStatus from, JobStatus to) {
    final allowed = allowedTransitions[from];
    return allowed != null && allowed.contains(to);
  }

  static void assertValidTransition(JobStatus from, JobStatus to) {
    if (!isValidTransition(from, to)) {
      throw InvalidJobTransitionException(from: from, to: to);
    }
  }

  // ─── Agreement-confirmation validation (pure — unit-testable) ─────────────
  //
  // These mirror isValidTransition's role for the core state machine: pure
  // functions of (job, actor) with no Firestore dependency, called by both
  // the real transactional methods below AND test/job_service_agreement_test.dart.
  // The transactional methods reconstruct a JobModel from the in-transaction
  // read and call these directly — there is exactly one place this logic
  // lives, not a copy for tests and a copy for production.

  /// Customer may confirm the agreement only while inChat, only once a
  /// quote has actually been accepted (artisanId set), only as the job's
  /// own customer, and only when not already pending/confirmed.
  static bool canConfirmAgreement(JobModel job, String actorId) {
    if (job.status != JobStatus.inChat) return false;
    if (job.artisanId.isEmpty) return false;
    if (actorId != job.customerId) return false;
    final current = job.agreementStatus ?? AgreementStatus.negotiating;
    return current == AgreementStatus.negotiating ||
        current == AgreementStatus.changesRequested;
  }

  /// Artisan may accept (or request changes on) the agreement only while
  /// inChat, only as the job's own matched artisan (not any other artisan —
  /// "not selected for" is exactly artisanId mismatch), and only once the
  /// customer has actually confirmed and it's awaiting artisan action.
  static bool canRespondToAgreement(JobModel job, String actorId) {
    if (job.status != JobStatus.inChat) return false;
    if (job.artisanId.isEmpty || actorId != job.artisanId) return false;
    return job.agreementStatus == AgreementStatus.pendingArtisanConfirmation;
  }

  /// Stage 5 (D7): only the matched artisan confirms a booking request,
  /// only while it is still awaiting them. The confirmation deadline itself
  /// (default 24 h) is server-enforced in firestore.rules.
  static bool canConfirmBooking(JobModel job, String actorId) =>
      job.awaitingArtisanConfirmation && job.artisanId.isNotEmpty && actorId == job.artisanId;

  /// Stage 5 (D4): one rework request per job, by the customer, on
  /// submitted work. Mirrors the firestore.rules clause.
  static bool canRequestRework(JobModel job, String actorId) =>
      job.canRequestRework && actorId == job.customerId;

  /// Stage 5 (D4): the artisan may answer the rework request once.
  static bool canRespondToRework(JobModel job, String actorId) =>
      job.status == JobStatus.inProgress &&
      job.reworkCount == 1 &&
      job.reworkResponse == null &&
      job.artisanId.isNotEmpty &&
      actorId == job.artisanId;

  /// Paid-job cancellation request (policy D2): once escrow is funded,
  /// neither party may cancel — either may ask, once at a time, while the
  /// job is escrowLocked or inProgress. Mirrors the firestore.rules clause.
  /// (submitted is excluded deliberately — a problem with submitted work
  /// goes through the dispute flow, which also pauses auto-release.)
  static bool canRequestPaidCancellation(JobModel job, String actorId) {
    if (job.status != JobStatus.escrowLocked && job.status != JobStatus.inProgress) {
      return false;
    }
    final isParty = actorId == job.customerId ||
        (job.artisanId.isNotEmpty && actorId == job.artisanId);
    return isParty && !job.hasPendingCancellationRequest;
  }

  /// Payment may only be initiated once both parties have confirmed the
  /// agreement AND (for jobs that need one) a schedule is confirmed — on
  /// top of (not instead of) the underlying inChat → paymentPending
  /// transition already being structurally valid. 'asap' jobs have nothing
  /// to schedule, so [JobModel.schedulingSatisfied] is true for them by
  /// definition — this does not add a new blocker for the common case.
  static bool canInitPayment(JobModel job, String actorId) {
    if (!isValidTransition(job.status, JobStatus.paymentPending)) return false;
    if (actorId != job.customerId) return false;
    if (job.agreementStatus != AgreementStatus.confirmed) return false;
    return job.schedulingSatisfied;
  }

  // ─── Core write primitive ─────────────────────────────────────────────────

  /// Atomic status transition with mandatory audit trail.
  ///
  /// [ctx] carries WHO is doing WHAT and WHY. Every transaction writes the
  /// audit log entry in the same commit — partial success is impossible.
  ///
  /// Pass [skipTransitionCheck] only via [adminForceStatus] — every other
  /// caller must go through the state machine.
  Future<void> updateJobStatus(
    JobMutationContext ctx,
    String jobId,
    JobStatus to, {
    Map<String, dynamic> extra = const {},
    bool skipTransitionCheck = false,
  }) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final from = JobStatus.fromString(data['status'] as String? ?? 'requested');

      if (!skipTransitionCheck) assertValidTransition(from, to);

      final version = (data['updateVersion'] as int?) ?? 0;
      final milestones = timestampsForStatus(to);
      final consistency = _consistencyFields(ctx: ctx, currentVersion: version);
      final userDelta = _sanitizeDelta({
        'status': to.name,
        ...extra,
      });

      tx.update(jobRef, {
        'status': to.name,
        ...extra,
        ...milestones,
        ...consistency,
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: from.name,
        jobStatusAfter: to.name,
        versionBefore: version,
        delta: userDelta,
      ));
    });
  }

  /// Atomically updates [agreedAmount] without changing job status.
  /// Only valid when status == inChat.
  Future<void> updateAgreedAmount(
    JobMutationContext ctx,
    String jobId,
    double amount,
  ) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final status = JobStatus.fromString(data['status'] as String? ?? 'requested');
      if (status != JobStatus.inChat) {
        throw JobStateConflictException(
          'Cannot update agreedAmount in status "${status.name}" — must be inChat.',
        );
      }

      final version = (data['updateVersion'] as int?) ?? 0;

      tx.update(jobRef, {
        'agreedAmount': amount,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: status.name,
        jobStatusAfter: null, // no status change
        versionBefore: version,
        delta: {'agreedAmount': amount},
      ));
    });
  }

  /// Atomically updates the artisan's [progressStage] without changing job status.
  /// Only valid when status == inProgress. The artisan may only advance the stage
  /// (not rewind it), but this is enforced at the UI layer — here we just persist.
  Future<void> updateJobProgress(
    JobMutationContext ctx,
    String jobId,
    JobProgressStage stage,
  ) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final status = JobStatus.fromString(data['status'] as String? ?? 'requested');
      if (status != JobStatus.inProgress) {
        throw JobStateConflictException(
          'Progress stage can only be updated while job is inProgress (current: "${status.name}").',
        );
      }

      final version = (data['updateVersion'] as int?) ?? 0;

      tx.update(jobRef, {
        'progressStage': stage.name,
        'progressUpdatedAt': FieldValue.serverTimestamp(),
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: status.name,
        jobStatusAfter: null,
        versionBefore: version,
        delta: {'progressStage': stage.name},
      ));
    });
  }

  /// Atomically sends a negotiation message AND updates [proposedAmount] on
  /// the job — one transaction, one audit log entry. No split-write possible.
  Future<void> sendNegotiation(
    JobMutationContext ctx,
    String jobId,
    String receiverId,
    double proposedAmount,
  ) async {
    final jobRef = _jobRef(jobId);
    final msgRef = _db.collection('jobs').doc(jobId).collection('messages').doc();
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final status = JobStatus.fromString(data['status'] as String? ?? 'requested');
      if (status != JobStatus.inChat) {
        throw JobStateConflictException(
          'Negotiation only allowed while inChat (current: "${status.name}").',
        );
      }

      final version = (data['updateVersion'] as int?) ?? 0;
      final now = FieldValue.serverTimestamp();

      // ① Write the chat message — schema matches MessageModel.fromJson exactly
      tx.set(msgRef, {
        'id': msgRef.id,
        'jobId': jobId,
        'senderId': ctx.actorId,
        'receiverId': receiverId,
        'text': '💰 Price proposal: ₦${proposedAmount.toStringAsFixed(0)}',
        'type': 'negotiation',
        'proposedAmount': proposedAmount,
        'isRead': false,
        'createdAt': now,
      });

      // ② Update job's agreedAmount in the same transaction
      tx.update(jobRef, {
        'agreedAmount': proposedAmount,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      // ③ Audit log — same commit, atomic with ① and ②
      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: status.name,
        jobStatusAfter: null,
        versionBefore: version,
        delta: {
          'agreedAmount': proposedAmount,
          'messageId': msgRef.id,
        },
      ));
    });
  }

  /// [confirmComplete] is a special-case because it writes to TWO top-level
  /// collections (job + escrow_releases) AND the audit log — all in one
  /// transaction. If any write fails, all three roll back.
  ///
  /// Payout idempotency (design/PAYOUT_RACE_CONDITION_AUDIT.md): the release
  /// document ID is the [jobId] itself, not an auto-generated ID — one job
  /// can structurally have at most one `escrow_releases` document, ever.
  /// This transaction reads that fixed-ID doc and aborts with
  /// [JobStateConflictException] if it already exists, so a customer
  /// manually confirming a job the auto-release Cloud Function has already
  /// (or concurrently is about to) release cannot create a second payout —
  /// whichever writer's transaction reaches the release doc first wins;
  /// Firestore's transaction-conflict retry makes this safe under real
  /// concurrency, not just under sequential calls.
  Future<void> confirmComplete(JobMutationContext ctx, String jobId) async {
    final jobRef = _jobRef(jobId);
    final releaseRef = _db.collection('escrow_releases').doc(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final from = JobStatus.fromString(data['status'] as String? ?? 'requested');
      assertValidTransition(from, JobStatus.completed);

      final releaseSnap = await tx.get(releaseRef);
      if (releaseSnap.exists) {
        throw const JobStateConflictException(
          'This job has already been released for payout — cannot release it a second time.',
        );
      }

      final version = (data['updateVersion'] as int?) ?? 0;
      final now = FieldValue.serverTimestamp();

      tx.update(jobRef, {
        'status': JobStatus.completed.name,
        'completedAt': now,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      // Escrow release queued atomically — job cannot reach 'completed'
      // without a corresponding release entry. releaseRef's fixed jobId-
      // keyed ID (not an auto-ID) is what makes this a true create-once,
      // not just a same-transaction convenience.
      tx.set(releaseRef, {
        'jobId': jobId,
        'requestedAt': now,
        'status': 'pending',
        'requestedBy': ctx.actorId,
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: from.name,
        jobStatusAfter: JobStatus.completed.name,
        versionBefore: version,
        delta: {
          'status': JobStatus.completed.name,
          'escrowReleaseQueued': true,
          'releaseRef': releaseRef.id,
        },
      ));
    });
  }

  /// Admin-only: force a job to any status, bypassing the state machine.
  ///
  /// [ctx.isAdminOverride] MUST be true, [ctx.actorRole] MUST be admin,
  /// and [ctx.overrideReason] MUST be non-empty. All three are enforced
  /// by [ctx.assertAdminOverride()] — not runtime duck-typing.
  ///
  /// The override is still transactional and still writes an audit log.
  /// There is no way to perform an override without a trace.
  Future<void> adminForceStatus(
    JobMutationContext ctx,
    String jobId,
    JobStatus forcedStatus,
  ) async {
    ctx.assertAdminOverride(); // throws if context is not valid admin override
    await updateJobStatus(
      ctx,
      jobId,
      forcedStatus,
      extra: {
        if (ctx.overrideReason != null) 'adminOverrideReason': ctx.overrideReason,
      },
      skipTransitionCheck: true,
    );
  }

  /// Escape hatch for callers needing custom multi-doc atomic updates.
  /// The job is pre-read; [updateFn] must not await anything.
  Future<void> applyJobUpdateTransaction(
    String jobId,
    JobUpdateFn updateFn,
  ) async {
    final ref = _jobRef(jobId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw JobNotFoundException(jobId);
      updateFn(tx, ref, snap.data()!);
    });
  }

  // ─── Lifecycle convenience methods ────────────────────────────────────────

  Future<void> acceptArtisan(
    JobMutationContext ctx,
    String jobId,
    String artisanId,
  ) =>
      updateJobStatus(ctx, jobId, JobStatus.matched,
          extra: {'artisanId': artisanId, 'bookingStatus': 'awaitingArtisan'});

  Future<void> openChat(JobMutationContext ctx, String jobId) =>
      updateJobStatus(ctx, jobId, JobStatus.inChat);

  /// Own transaction rather than a thin [updateJobStatus] delegate — like
  /// [updateAgreedAmount], this transition carries a business-rule
  /// precondition ([canInitPayment]'s agreementStatus check) beyond pure
  /// status-transition validity, so it needs the job data loaded first.
  ///
  /// Stage 2 (HT-004): no longer writes agreedAmount. The price is frozen
  /// when the artisan accepts the agreement, and firestore.rules reject any
  /// change to it on this transition; initializePaystackTransaction charges
  /// the stored value. There is deliberately no amount parameter.
  Future<void> initPayment(
    JobMutationContext ctx,
    String jobId,
  ) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final job = JobModel.fromJson({...snap.data()!, 'id': jobId});
      assertValidTransition(job.status, JobStatus.paymentPending);
      if (!canInitPayment(job, ctx.actorId)) {
        final reason = job.agreementStatus != AgreementStatus.confirmed
            ? 'a confirmed agreement (current: '
                '"${(job.agreementStatus ?? AgreementStatus.negotiating).name}")'
            : 'a confirmed schedule (current: '
                '"${(job.schedulingStatus ?? SchedulingStatus.awaitingSchedule).name}")';
        throw JobStateConflictException('Payment requires $reason.');
      }

      final version = job.updateVersion;

      tx.update(jobRef, {
        'status': JobStatus.paymentPending.name,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: job.status.name,
        jobStatusAfter: JobStatus.paymentPending.name,
        versionBefore: version,
        delta: {'agreedAmount': job.agreedAmount},
      ));
    });
  }

  Future<void> lockEscrow(
    JobMutationContext ctx,
    String jobId,
    String paystackRef,
  ) =>
      updateJobStatus(ctx, jobId, JobStatus.escrowLocked,
          extra: {'paymentReference': paystackRef});

  Future<void> startWork(JobMutationContext ctx, String jobId) =>
      updateJobStatus(ctx, jobId, JobStatus.inProgress);

  Future<void> submitCompletion(
    JobMutationContext ctx,
    String jobId, {
    required List<String> completionImageUrls,
    List<String> beforePhotoUrls = const [],
    String? artisanNotes,
  }) {
    final extra = <String, dynamic>{
      'completionImageUrls': completionImageUrls,
      if (beforePhotoUrls.isNotEmpty) 'beforePhotoUrls': beforePhotoUrls,
    };
    if (artisanNotes != null) extra['artisanNotes'] = artisanNotes;
    return updateJobStatus(ctx, jobId, JobStatus.submitted, extra: extra);
  }

  /// Artisan proposes appointment slots (up to 3) while job is inChat.
  /// No status transition — writes [appointmentSlots] + consistency fields.
  Future<void> proposeAppointmentSlots(
    JobMutationContext ctx,
    String jobId,
    List<DateTime> slots,
  ) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final status = JobStatus.fromString(data['status'] as String? ?? 'requested');
      if (status != JobStatus.inChat) {
        throw JobStateConflictException(
          'Appointment slots can only be proposed while job is inChat (current: "${status.name}").',
        );
      }

      final version = (data['updateVersion'] as int?) ?? 0;

      tx.update(jobRef, {
        'appointmentSlots': slots.map((d) => Timestamp.fromDate(d)).toList(),
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: status.name,
        jobStatusAfter: null,
        versionBefore: version,
        delta: {'appointmentSlotsCount': slots.length},
      ));
    });
  }

  /// Customer confirms one of the artisan's proposed appointment slots.
  /// No status transition — writes [confirmedAppointment] + consistency fields.
  Future<void> confirmAppointmentSlot(
    JobMutationContext ctx,
    String jobId,
    DateTime slot,
  ) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final status = JobStatus.fromString(data['status'] as String? ?? 'requested');
      if (status != JobStatus.inChat) {
        throw JobStateConflictException(
          'Appointment slot can only be confirmed while job is inChat (current: "${status.name}").',
        );
      }

      final version = (data['updateVersion'] as int?) ?? 0;

      // Confirming a slot IS the "Scheduled" workflow stage completing —
      // written in the same transaction as confirmedAppointment itself,
      // not a separate write, so the two can never disagree. Doesn't
      // require agreementStatus == confirmed first: negotiating timing
      // alongside price during inChat is normal and stays allowed: the
      // payment gate (canInitPayment) is what actually enforces the
      // Agreement Confirmed -> Scheduled -> Payment ordering, not this.
      tx.update(jobRef, {
        'confirmedAppointment': Timestamp.fromDate(slot),
        'schedulingStatus': SchedulingStatus.scheduled.name,
        'schedulingUpdatedAt': FieldValue.serverTimestamp(),
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: status.name,
        jobStatusAfter: null,
        versionBefore: version,
        delta: {
          'confirmedAppointment': slot.toIso8601String(),
          'schedulingStatus': SchedulingStatus.scheduled.name,
        },
      ));
    });
  }

  /// Customer confirms negotiation is finished and locks the terms in —
  /// the "Negotiation Completed / Agreement Confirmation" checkpoint. No
  /// JobStatus change (still inChat); [agreementStatus] moves to
  /// pendingArtisanConfirmation, mirroring how [updateJobProgress] advances
  /// [progressStage] without touching JobStatus. [scope] and, if provided,
  /// [price] are locked at this point — see [canConfirmAgreement] for the
  /// full precondition and [_isValidJobTransition] in firestore.rules for
  /// the server-enforced mirror of this same check.
  Future<void> confirmAgreementAsCustomer(
    JobMutationContext ctx,
    String jobId, {
    required String scope,
    double? price,
  }) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final job = JobModel.fromJson({...snap.data()!, 'id': jobId});
      if (!canConfirmAgreement(job, ctx.actorId)) {
        throw JobStateConflictException(
          'Cannot confirm agreement: job must be inChat with an accepted '
          'quote, caller must be the customer, and the agreement must not '
          'already be pending or confirmed (current: '
          '"${(job.agreementStatus ?? AgreementStatus.negotiating).name}").',
        );
      }

      final version = job.updateVersion;
      final now = FieldValue.serverTimestamp();

      tx.update(jobRef, {
        'agreementStatus': AgreementStatus.pendingArtisanConfirmation.name,
        'agreementScope': scope,
        'agreementConfirmedByCustomer': true,
        'agreementCustomerConfirmedAt': now,
        'agreementUpdatedAt': now,
        'agreedAmount': ?price,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: job.status.name,
        jobStatusAfter: null,
        versionBefore: version,
        delta: {
          'agreementStatus': AgreementStatus.pendingArtisanConfirmation.name,
          'agreementScope': scope,
          'agreedAmount': ?price,
        },
      ));
    });
  }

  /// Artisan accepts the customer-confirmed agreement — the job may now
  /// proceed to scheduling/payment. See [canRespondToAgreement].
  Future<void> acceptAgreementAsArtisan(
    JobMutationContext ctx,
    String jobId,
  ) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final job = JobModel.fromJson({...snap.data()!, 'id': jobId});
      if (!canRespondToAgreement(job, ctx.actorId)) {
        throw JobStateConflictException(
          'Cannot accept agreement: job must be inChat, caller must be the '
          'job\'s matched artisan, and agreement must be pending artisan '
          'confirmation (current: '
          '"${(job.agreementStatus ?? AgreementStatus.negotiating).name}").',
        );
      }

      final version = job.updateVersion;
      final now = FieldValue.serverTimestamp();

      tx.update(jobRef, {
        'agreementStatus': AgreementStatus.confirmed.name,
        'agreementConfirmedByArtisan': true,
        'agreementArtisanConfirmedAt': now,
        'agreementUpdatedAt': now,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: job.status.name,
        jobStatusAfter: null,
        versionBefore: version,
        delta: {'agreementStatus': AgreementStatus.confirmed.name},
      ));
    });
  }

  /// Artisan sends the agreement back for further negotiation instead of
  /// accepting it. Only the artisan's own confirmation flag is touched —
  /// the customer's [agreementConfirmedByCustomer]/timestamp are left as
  /// historical record and are naturally overwritten on their next confirm.
  Future<void> requestAgreementChanges(
    JobMutationContext ctx,
    String jobId, {
    required String reason,
  }) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final job = JobModel.fromJson({...snap.data()!, 'id': jobId});
      if (!canRespondToAgreement(job, ctx.actorId)) {
        throw JobStateConflictException(
          'Cannot request changes: job must be inChat, caller must be the '
          'job\'s matched artisan, and agreement must be pending artisan '
          'confirmation (current: '
          '"${(job.agreementStatus ?? AgreementStatus.negotiating).name}").',
        );
      }

      final version = job.updateVersion;
      final now = FieldValue.serverTimestamp();

      tx.update(jobRef, {
        'agreementStatus': AgreementStatus.changesRequested.name,
        'agreementConfirmedByArtisan': false,
        'agreementChangesRequestedReason': reason,
        'agreementUpdatedAt': now,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: job.status.name,
        jobStatusAfter: null,
        versionBefore: version,
        delta: {
          'agreementStatus': AgreementStatus.changesRequested.name,
          'reason': reason,
        },
      ));
    });
  }

  /// Stage 5 (D7): the artisan accepts a booking request — matched -> inChat
  /// with the booking confirmed, stamped with server time.
  Future<void> confirmBooking(JobMutationContext ctx, String jobId) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);
      final job = JobModel.fromJson({...snap.data()!, 'id': jobId});
      if (!canConfirmBooking(job, ctx.actorId)) {
        throw JobStateConflictException(
          'This booking can no longer be confirmed (status: "${job.status.name}").',
        );
      }
      final version = job.updateVersion;
      tx.update(jobRef, {
        'status': JobStatus.inChat.name,
        'bookingStatus': 'confirmed',
        'bookingConfirmedAt': FieldValue.serverTimestamp(),
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });
      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: job.status.name,
        jobStatusAfter: JobStatus.inChat.name,
        versionBefore: version,
        delta: {'bookingStatus': 'confirmed'},
      ));
    });
  }

  /// Stage 5 (D4): the customer's single rework request — submitted ->
  /// inProgress with a reason. The review-window timers are cleared
  /// server-side, and the artisan's resubmission starts a new 14-day window.
  Future<void> requestRework(
    JobMutationContext ctx,
    String jobId, {
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.length < 10) {
      throw const JobStateConflictException('Please describe what needs to change (at least 10 characters).');
    }
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);
      final job = JobModel.fromJson({...snap.data()!, 'id': jobId});
      if (!canRequestRework(job, ctx.actorId)) {
        throw const JobStateConflictException('Rework can only be requested once, on submitted work.');
      }
      final version = job.updateVersion;
      tx.update(jobRef, {
        'status': JobStatus.inProgress.name,
        'reworkCount': 1,
        'reworkReason': trimmed,
        'reworkRequestedAt': FieldValue.serverTimestamp(),
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });
      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: job.status.name,
        jobStatusAfter: JobStatus.inProgress.name,
        versionBefore: version,
        delta: {'reworkCount': 1, 'reworkReason': trimmed},
      ));
    });
  }

  /// Stage 5 (D4): the artisan's single response to a rework request.
  Future<void> respondToRework(
    JobMutationContext ctx,
    String jobId, {
    required String response,
  }) async {
    final trimmed = response.trim();
    if (trimmed.isEmpty) throw const JobStateConflictException('Please write a response.');
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);
      final job = JobModel.fromJson({...snap.data()!, 'id': jobId});
      if (!canRespondToRework(job, ctx.actorId)) {
        throw const JobStateConflictException('There is no open rework request to respond to.');
      }
      final version = job.updateVersion;
      tx.update(jobRef, {
        'reworkResponse': trimmed,
        'reworkRespondedAt': FieldValue.serverTimestamp(),
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });
      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: job.status.name,
        jobStatusAfter: null,
        versionBefore: version,
        delta: {'reworkResponse': trimmed},
      ));
    });
  }

  /// Files a paid-job cancellation request for admin review (policy D2).
  /// No status change, no escrow/payment field touched — the
  /// onJobCompleted Cloud Function raises an admin alert and tells the
  /// other party. See [canRequestPaidCancellation].
  Future<void> requestPaidCancellation(
    JobMutationContext ctx,
    String jobId, {
    required String reason,
  }) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final job = JobModel.fromJson({...snap.data()!, 'id': jobId});
      if (!canRequestPaidCancellation(job, ctx.actorId)) {
        throw JobStateConflictException(
          'A cancellation request can only be filed by a party to a funded '
          'job (escrowLocked/inProgress) with no request already pending '
          '(current status: "${job.status.name}").',
        );
      }

      final version = job.updateVersion;

      tx.update(jobRef, {
        'cancellationRequestStatus': 'pending',
        'cancellationRequestedBy': ctx.actorId,
        'cancellationRequestReason': reason,
        'cancellationRequestedAt': FieldValue.serverTimestamp(),
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: job.status.name,
        jobStatusAfter: null,
        versionBefore: version,
        delta: {'cancellationRequestStatus': 'pending', 'reason': reason},
      ));
    });
  }

  Future<void> cancelJob(
    JobMutationContext ctx,
    String jobId, {
    String? cancelledBy,
    String? cancellationReason,
  }) =>
      updateJobStatus(ctx, jobId, JobStatus.cancelled, extra: {
        'cancelledBy': ?cancelledBy,
        'cancellationReason': ?cancellationReason,
        'cancelledAt': FieldValue.serverTimestamp(),
      });

  /// Raises a dispute: transitions the job to 'disputed' AND creates the
  /// dispute record — all in one transaction. Modeled on [confirmComplete],
  /// which writes to escrow_releases alongside the job doc; here the second
  /// collection is /disputes. A dispute can never exist without the job
  /// reflecting 'disputed' status, and vice versa — no partial state.
  Future<void> raiseDisputeWithRecord(
    JobMutationContext ctx,
    String jobId, {
    required String disputeId,
    required String reason,
    required String againstUserId,
    List<String> evidenceImageUrls = const [],
  }) async {
    final jobRef = _jobRef(jobId);
    final disputeRef = _db.collection('disputes').doc(disputeId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final from = JobStatus.fromString(data['status'] as String? ?? 'requested');
      assertValidTransition(from, JobStatus.disputed);

      final version = (data['updateVersion'] as int?) ?? 0;

      tx.update(jobRef, {
        'status': JobStatus.disputed.name,
        'disputeReason': reason,
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.set(disputeRef, {
        'id': disputeId,
        'jobId': jobId,
        'raisedBy': ctx.actorId,
        'againstUserId': againstUserId,
        'reason': reason,
        'evidenceImageUrls': evidenceImageUrls,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: from.name,
        jobStatusAfter: JobStatus.disputed.name,
        versionBefore: version,
        delta: {'disputeId': disputeId, 'reason': reason},
      ));
    });
  }

  /// Admin resolves a dispute: transitions the job to 'resolved' AND
  /// updates the dispute record — all in one transaction. [dismiss] marks
  /// the dispute record 'dismissed' instead of 'resolved'; the job still
  /// transitions to 'resolved' either way (it is no longer blocked).
  Future<void> resolveDisputeWithRecord(
    JobMutationContext ctx,
    String jobId, {
    required String disputeId,
    required String resolution,
    String? adminNote,
    bool dismiss = false,
  }) async {
    final jobRef = _jobRef(jobId);
    final disputeRef = _db.collection('disputes').doc(disputeId);
    final auditRef = _auditRef(jobId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final from = JobStatus.fromString(data['status'] as String? ?? 'requested');
      assertValidTransition(from, JobStatus.resolved);

      final disputeSnap = await tx.get(disputeRef);
      if (!disputeSnap.exists) {
        throw JobStateConflictException('Dispute $disputeId not found for job $jobId');
      }
      final disputeStatus = disputeSnap.data()!['status'] as String?;
      if (disputeStatus == 'resolved' || disputeStatus == 'dismissed') {
        throw JobStateConflictException('Dispute is already resolved.');
      }

      final version = (data['updateVersion'] as int?) ?? 0;

      tx.update(jobRef, {
        'status': JobStatus.resolved.name,
        'disputeResolution': resolution,
        ...timestampsForStatus(JobStatus.resolved),
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.update(disputeRef, {
        'status': dismiss ? 'dismissed' : 'resolved',
        'resolution': resolution,
        'adminNote': ?adminNote,
        'resolvedAt': FieldValue.serverTimestamp(),
      });

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: from.name,
        jobStatusAfter: JobStatus.resolved.name,
        versionBefore: version,
        delta: {'disputeId': disputeId, 'resolution': resolution, 'dismissed': dismiss},
      ));
    });
  }

  /// Accepts an artisan's quote: transitions the job requested → matched
  /// AND resolves every quote for the job — all in one transaction.
  ///
  /// The quotes subcollection is written here, inside JobService, rather
  /// than by a separate write in QuoteService, because the quote outcome
  /// is inseparable from the job's transition: if these were two writes,
  /// a failure between them could leave the job matched with competing
  /// quotes still "pending" (one artisan could then withdraw and silently
  /// reappear as if still in the running). [competingQuoteIds] is the
  /// caller's pre-transaction snapshot of other pending quotes; each is
  /// re-validated implicitly by being blind-written to 'closed' only if
  /// still present — a late-arriving quote outside that snapshot is a
  /// known, accepted gap (the UI only ever shows quotes for jobs still in
  /// 'requested' status, so it self-resolves on the next read).
  Future<void> acceptQuote(
    JobMutationContext ctx,
    String jobId, {
    required String quoteId,
    required String artisanId,
    required List<String> competingQuoteIds,
  }) async {
    final jobRef = _jobRef(jobId);
    final auditRef = _auditRef(jobId);
    final quotesCol = _db.collection('jobs').doc(jobId).collection('quotes');
    final acceptedRef = quotesCol.doc(quoteId);
    final competingRefs = competingQuoteIds
        .where((id) => id != quoteId)
        .map(quotesCol.doc)
        .toList();

    await _db.runTransaction((tx) async {
      final snap = await tx.get(jobRef);
      if (!snap.exists) throw JobNotFoundException(jobId);

      final data = snap.data()!;
      final from = JobStatus.fromString(data['status'] as String? ?? 'requested');
      assertValidTransition(from, JobStatus.matched);

      final acceptedSnap = await tx.get(acceptedRef);
      if (!acceptedSnap.exists) {
        throw JobStateConflictException('Quote $quoteId not found for job $jobId');
      }
      if (acceptedSnap.data()!['status'] != 'pending') {
        throw JobStateConflictException('Quote is no longer pending.');
      }

      final version = (data['updateVersion'] as int?) ?? 0;

      tx.update(jobRef, {
        'status': JobStatus.matched.name,
        'artisanId': artisanId,
        // Stage 5 (D7): the artisan must still confirm the booking.
        'bookingStatus': 'awaitingArtisan',
        ...timestampsForStatus(JobStatus.matched),
        ..._consistencyFields(ctx: ctx, currentVersion: version),
      });

      tx.update(acceptedRef, {'status': 'accepted'});
      for (final ref in competingRefs) {
        tx.update(ref, {'status': 'closed'});
      }

      tx.set(auditRef, _buildAuditEntry(
        id: auditRef.id,
        ctx: ctx,
        jobId: jobId,
        jobStatusBefore: from.name,
        jobStatusAfter: JobStatus.matched.name,
        versionBefore: version,
        delta: {
          'artisanId': artisanId,
          'acceptedQuoteId': quoteId,
          'closedQuoteCount': competingRefs.length,
        },
      ));
    });
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _jobRef(String jobId) =>
      _db.collection('jobs').doc(jobId);

  /// Each audit log is a new document in the job's auditLogs subcollection.
  /// The document ID serves as the transactionId.
  DocumentReference<Map<String, dynamic>> _auditRef(String jobId) =>
      _db.collection('jobs').doc(jobId).collection('auditLogs').doc();

  /// Builds the Firestore map for an audit log entry.
  /// Uses [FieldValue.serverTimestamp()] for [timestamp] — authoritative.
  Map<String, dynamic> _buildAuditEntry({
    required String id,
    required JobMutationContext ctx,
    required String jobId,
    required String jobStatusBefore,
    required String? jobStatusAfter,
    required int versionBefore,
    required Map<String, dynamic> delta,
  }) =>
      {
        'id': id,
        'jobId': jobId,
        'transactionId': id,
        'actionType': ctx.actionType.name,
        'actorId': ctx.actorId,
        'actorRole': ctx.actorRole.name,
        'timestamp': FieldValue.serverTimestamp(),
        'jobVersionBefore': versionBefore,
        'jobVersionAfter': versionBefore + 1,
        'jobStatusBefore': jobStatusBefore,
        'jobStatusAfter': ?jobStatusAfter,
        'delta': delta,
        'isAdminOverride': ctx.isAdminOverride,
        if (ctx.reason != null) 'reason': ctx.reason,
        if (ctx.overrideReason != null) 'overrideReason': ctx.overrideReason,
      };

  /// Stamps three fields on every job mutation.
  /// [updateVersion] is read inside the transaction and incremented by 1 —
  /// concurrent transactions retry and always see the committed version.
  static Map<String, dynamic> _consistencyFields({
    required JobMutationContext ctx,
    required int currentVersion,
  }) =>
      {
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'lastUpdatedBy': '${ctx.actorRole.name}:${ctx.actorId}',
        'updateVersion': currentVersion + 1,
      };

  /// Excludes [FieldValue] sentinels from the delta so it remains
  /// JSON-serializable when stored in the audit log.
  static Map<String, dynamic> _sanitizeDelta(Map<String, dynamic> data) =>
      Map.fromEntries(
        data.entries.where((e) => e.value is! FieldValue),
      );

  /// The single duration both the customer-facing dispute countdown and
  /// the Cloud Functions auto-release cron are computed from — see
  /// design/ESCROW_TIMING_AUDIT.md. Kept as one named constant so the two
  /// can never independently drift again the way autoReleaseAt (previously
  /// anchored to escrow-lock time, 48h) and disputeWindowEndsAt (anchored
  /// to submission time, 14 days) drifted before: a job that took longer
  /// than 48h to reach 'submitted' had already-expired autoReleaseAt the
  /// moment it got there, so the auto-release cron (which only matches
  /// status == 'submitted') would fire on the very next hourly run —
  /// often within the hour — while the UI still showed up to 14 days left.
  static const releaseWindow = Duration(days: 14);

  /// Timestamps for status milestones. Public (not `_timestampsForStatus`)
  /// for the same reason canConfirmAgreement/canInitPayment above are
  /// public: so test/job_service_agreement_test.dart can assert the exact
  /// map this produces — one copy of this logic, not a copy for tests and
  /// a copy for production.
  static Map<String, dynamic> timestampsForStatus(JobStatus status) =>
      switch (status) {
        JobStatus.matched => {'matchedAt': FieldValue.serverTimestamp()},
        JobStatus.escrowLocked => {
          'escrowLockedAt': FieldValue.serverTimestamp(),
          // autoReleaseAt is deliberately NOT set here anymore — see
          // design/ESCROW_TIMING_AUDIT.md. Setting it at lock time (as
          // 48h out) was the root cause of the auto-release timing bug:
          // it could expire before the job even reached 'submitted',
          // since the auto-release cron only ever matches status ==
          // 'submitted'. Its absence before submission is inert — the
          // cron can't match a job that isn't submitted yet regardless.
          // It's set once, correctly, at submission time below instead.
        },
        JobStatus.inProgress => {'startedAt': FieldValue.serverTimestamp()},
        // Stage 2 (HT-005): only the server timestamp. disputeWindowEndsAt
        // and autoReleaseAt are server-owned — onJobCompleted (Cloud
        // Functions) sets both to submittedAt + releaseWindow, and the
        // auto-release itself re-checks submittedAt. Computing them here
        // used the artisan's device clock, which the artisan controls.
        JobStatus.submitted => {'submittedAt': FieldValue.serverTimestamp()},
        JobStatus.completed || JobStatus.resolved => {
          'completedAt': FieldValue.serverTimestamp(),
        },
        _ => {},
      };
}
