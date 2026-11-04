import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/job_service.dart';
import '../core/utils/safe_firestore.dart';
import '../models/audit_log_model.dart';
import '../models/job_model.dart';
import '../models/job_mutation_context.dart';
import '../models/payment_model.dart';
import 'auth_provider.dart';
import 'job_service_provider.dart';

// ─── Job streams (read-only — not part of the write layer) ──────────────────

/// Real-time stream of a single job document. Drives all status-aware UI.
final jobStreamProvider = StreamProvider.family<JobModel?, String>((ref, jobId) {
  return safeDocStream(
    FirebaseFirestore.instance.collection('jobs').doc(jobId),
    JobModel.fromJson,
    debugLabel: 'job:$jobId',
  );
});

/// All jobs for a customer — sorted newest-first on the client to avoid a
/// composite Firestore index on (customerId, createdAt).
final customerJobsProvider =
    StreamProvider.family<List<JobModel>, String>((ref, customerId) {
  return safeStream(
    FirebaseFirestore.instance.collection('jobs').where('customerId', isEqualTo: customerId),
    (d) => JobModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'customerJobs:$customerId',
  ).map((jobs) => jobs..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

/// All jobs for an artisan — sorted newest-first on the client.
final artisanJobsProvider =
    StreamProvider.family<List<JobModel>, String>((ref, artisanId) {
  return safeStream(
    FirebaseFirestore.instance.collection('jobs').where('artisanId', isEqualTo: artisanId),
    (d) => JobModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'artisanJobs:$artisanId',
  ).map((jobs) => jobs..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
});

/// Payment record for a job — used by the payment screen.
final jobPaymentProvider =
    FutureProvider.family<PaymentModel?, String>((ref, jobId) async {
  final snap = await FirebaseFirestore.instance
      .collection('payments')
      .where('jobId', isEqualTo: jobId)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return null;
  final d = snap.docs.first;
  return PaymentModel.fromJson({...d.data(), 'id': d.id});
});

// ─── Write notifier ──────────────────────────────────────────────────────────

/// All job lifecycle mutations go through [JobService] — no direct Firestore
/// writes are made here. Every method is atomic via runTransaction and writes
/// an audit log entry in the same commit.
class EscrowNotifier extends StateNotifier<AsyncValue<void>> {
  final JobService _job;
  final String _uid;
  // Stage 6: no notification writer here any more — agreement and every
  // other job event is notified server-side (functions/index.js).
  EscrowNotifier(this._job, this._uid) : super(const AsyncData(null));

  // ─── Role assignments per action ─────────────────────────────────────────
  // Role is determined by the action: customers book/accept/pay/confirm;
  // artisans start/submit. Ambiguous actions (cancel/dispute) require the
  // caller to pass the role explicitly.

  JobMutationContext _customerCtx(JobActionType action, {String? reason}) =>
      JobMutationContext.customer(uid: _uid, actionType: action, reason: reason);

  JobMutationContext _artisanCtx(JobActionType action, {String? reason}) =>
      JobMutationContext.artisan(uid: _uid, actionType: action, reason: reason);

  JobMutationContext _ctxFor(ActorRole role, JobActionType action, {String? reason}) =>
      JobMutationContext(
        actorId: _uid,
        actorRole: role,
        actionType: action,
        reason: reason,
      );

  // ─── Customer actions ─────────────────────────────────────────────────────

  Future<void> acceptArtisan(String jobId, String artisanId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.acceptArtisan(
          _customerCtx(JobActionType.statusTransition),
          jobId,
          artisanId,
        ));
  }

  Future<void> openChat(String jobId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _job.openChat(_customerCtx(JobActionType.statusTransition), jobId));
  }

  /// No amount parameter (Stage 2, HT-004): the charged amount is the
  /// agreedAmount frozen at the artisan's acceptance, read server-side.
  Future<void> initPayment(String jobId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _job.initPayment(_customerCtx(JobActionType.statusTransition), jobId));
  }

  Future<void> lockEscrow(String jobId, String ref) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _job.lockEscrow(_customerCtx(JobActionType.escrowLocked), jobId, ref));
  }

  Future<void> confirmComplete(String jobId) async {
    state = const AsyncLoading();
    // Both the job→completed update and the escrow_releases entry are written
    // in a single Firestore transaction. Partial completion is impossible.
    state = await AsyncValue.guard(
        () => _job.confirmComplete(_customerCtx(JobActionType.jobCompleted), jobId));
  }

  // ─── Artisan actions ──────────────────────────────────────────────────────

  Future<void> startWork(String jobId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _job.startWork(_artisanCtx(JobActionType.workStarted), jobId));
  }

  Future<void> submitCompletion(
    String jobId, {
    required List<String> imageUrls,
    List<String> beforePhotoUrls = const [],
    String? notes,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.submitCompletion(
          _artisanCtx(JobActionType.workSubmitted),
          jobId,
          completionImageUrls: imageUrls,
          beforePhotoUrls: beforePhotoUrls,
          artisanNotes: notes,
        ));
  }

  // ─── Either-party actions (role passed by caller) ─────────────────────────
  // Note: raising/resolving a dispute is NOT exposed here — those mutate
  // both /jobs and /disputes atomically and live in DisputeService, which
  // delegates the job half of the write to JobService.raiseDisputeWithRecord
  // / resolveDisputeWithRecord (see dispute_service.dart).

  Future<void> proposeAppointmentSlots(
    String jobId,
    List<DateTime> slots,
  ) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.proposeAppointmentSlots(
          _artisanCtx(JobActionType.statusTransition),
          jobId,
          slots,
        ));
  }

  Future<void> confirmAppointmentSlot(String jobId, DateTime slot) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.confirmAppointmentSlot(
          _customerCtx(JobActionType.statusTransition),
          jobId,
          slot,
        ));
  }

  // ─── Agreement confirmation (Negotiation Completed checkpoint) ───────────

  /// Customer locks in the negotiated terms and hands off to the artisan
  /// for confirmation. Fetches the job's artisanId post-write (same pattern
  /// QuoteService.submitQuote uses to find its notification recipient) —
  /// EscrowNotifier's other methods don't need this since they're all
  /// already covered by the server-side push in onJobCompleted.
  Future<void> confirmAgreement(
    String jobId, {
    required String scope,
    double? price,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _job.confirmAgreementAsCustomer(
        _customerCtx(JobActionType.agreementConfirmedByCustomer),
        jobId,
        scope: scope,
        price: price,
      );
      // Stage 6 (HT-015): this notification is generated server-side from the
      // underlying document change (functions/index.js); clients can no longer
      // create notifications.
    });
  }

  /// Artisan accepts the confirmed agreement — job may now proceed to
  /// scheduling/payment.
  Future<void> acceptAgreement(String jobId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _job.acceptAgreementAsArtisan(
        _artisanCtx(JobActionType.agreementAcceptedByArtisan),
        jobId,
      );
      // Stage 6 (HT-015): this notification is generated server-side from the
      // underlying document change (functions/index.js); clients can no longer
      // create notifications.
    });
  }

  /// Artisan sends the agreement back for further negotiation.
  Future<void> requestAgreementChanges(String jobId, {required String reason}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _job.requestAgreementChanges(
        _artisanCtx(JobActionType.agreementChangesRequested),
        jobId,
        reason: reason,
      );
      // Stage 6 (HT-015): this notification is generated server-side from the
      // underlying document change (functions/index.js); clients can no longer
      // create notifications.
    });
  }

  Future<void> cancelJob(
    String jobId, {
    required ActorRole callerRole,
    String? cancellationReason,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.cancelJob(
          _ctxFor(callerRole, JobActionType.jobCancelled,
              reason: cancellationReason),
          jobId,
          cancelledBy: _uid,
          cancellationReason: cancellationReason,
        ));
  }

  /// Either party asks HandyTrust to cancel a funded job (policy D2). The
  /// job keeps its status and escrow stays locked until an admin decides.
  Future<void> requestPaidCancellation(
    String jobId, {
    required ActorRole callerRole,
    required String reason,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.requestPaidCancellation(
          _ctxFor(callerRole, JobActionType.paidCancellationRequested, reason: reason),
          jobId,
          reason: reason,
        ));
  }

  // ─── Stage 5: booking confirmation, rework, withdrawal ────────────────────

  /// Artisan accepts a booking request (policy D7).
  Future<void> confirmBooking(String jobId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => _job.confirmBooking(_artisanCtx(JobActionType.statusTransition), jobId));
  }

  /// Customer's single rework request on submitted work (policy D4).
  Future<void> requestRework(String jobId, {required String reason}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.requestRework(
          _customerCtx(JobActionType.statusTransition, reason: reason),
          jobId,
          reason: reason,
        ));
  }

  /// Artisan's single response to a rework request (policy D4).
  Future<void> respondToRework(String jobId, {required String response}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.respondToRework(
          _artisanCtx(JobActionType.statusTransition),
          jobId,
          response: response,
        ));
  }

  /// Artisan declines a booking request or withdraws before payment
  /// (policies D6/D7). Server-side: the job REOPENS for other artisans.
  Future<void> withdrawFromJob(String jobId, {required String reason}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await FirebaseFunctions.instance
          .httpsCallable('artisanWithdrawFromJob')
          .call({'jobId': jobId, 'reason': reason});
    });
  }

  /// Artisan advances the fine-grained progress stage within [JobStatus.inProgress].
  Future<void> updateProgress(String jobId, JobProgressStage stage) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _job.updateJobProgress(
          _artisanCtx(JobActionType.progressUpdated),
          jobId,
          stage,
        ));
  }
}

final escrowNotifierProvider =
    StateNotifierProvider<EscrowNotifier, AsyncValue<void>>((ref) {
  final uid = ref.watch(authStateChangesProvider).asData?.value?.uid ?? 'unknown';
  return EscrowNotifier(
    ref.watch(jobServiceProvider),
    uid,
  );
});

/// Stage 6 (P-K, policy D9): the exact job location from
/// `jobs/{id}/private/location`. Firestore rules only let the customer,
/// admins and the artisan who CONFIRMED the booking read it; for anyone else
/// this stream errors (permission denied) and callers show the coarse area.
final jobPrivateLocationProvider =
    StreamProvider.family<Map<String, dynamic>?, String>((ref, jobId) {
  return FirebaseFirestore.instance
      .collection('jobs')
      .doc(jobId)
      .collection('private')
      .doc('location')
      .snapshots()
      .map((s) => s.data());
});
