import 'package:cloud_firestore/cloud_firestore.dart';

/// Fine-grained progress within the [JobStatus.inProgress] stage.
/// Artisan sets these; customer and admin can view them.
enum JobProgressStage {
  accepted,
  onTheWay,
  workStarted,
  quarterDone,
  halfDone,
  threeQuartersDone,
  almostFinished,
  completed;

  static JobProgressStage fromString(String s) =>
      JobProgressStage.values.firstWhere(
        (e) => e.name == s,
        orElse: () => JobProgressStage.accepted,
      );

  String get label => switch (this) {
        JobProgressStage.accepted => 'Accepted',
        JobProgressStage.onTheWay => 'On The Way',
        JobProgressStage.workStarted => 'Work Started',
        JobProgressStage.quarterDone => '25% Done',
        JobProgressStage.halfDone => '50% Done',
        JobProgressStage.threeQuartersDone => '75% Done',
        JobProgressStage.almostFinished => 'Almost Finished',
        JobProgressStage.completed => 'Completed',
      };

  /// 0–7 ordinal for timeline rendering.
  int get step => index;
}

/// Formal agreement-confirmation sub-state within [JobStatus.inChat],
/// mirroring how [JobProgressStage] is a fine-grained sub-state within
/// [JobStatus.inProgress] — this does NOT introduce a new top-level
/// JobStatus. Negotiation happens via chat/agreedAmount as before; this
/// enum turns "we're done negotiating" into an explicit, two-party,
/// state-controlled checkpoint instead of relying on conversation history.
enum AgreementStatus {
  negotiating,
  pendingArtisanConfirmation,
  confirmed,
  changesRequested;

  static AgreementStatus fromString(String s) =>
      AgreementStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => AgreementStatus.negotiating,
      );

  String get label => switch (this) {
        AgreementStatus.negotiating => 'Negotiating',
        AgreementStatus.pendingArtisanConfirmation => 'Awaiting Artisan Confirmation',
        AgreementStatus.confirmed => 'Agreement Confirmed',
        AgreementStatus.changesRequested => 'Changes Requested',
      };
}

/// Formal scheduling sub-state within [JobStatus.inChat], following the
/// exact same pattern as [AgreementStatus] and [JobProgressStage] — no new
/// top-level JobStatus. Only meaningful once [AgreementStatus.confirmed];
/// only *required* to reach [scheduled] for jobs where [JobModel.urgency]
/// == 'scheduled' — an 'asap' job has nothing to schedule, so it's treated
/// as satisfied automatically (see [JobModel.schedulingSatisfied]).
enum SchedulingStatus {
  awaitingSchedule,
  scheduled;

  static SchedulingStatus fromString(String s) =>
      SchedulingStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => SchedulingStatus.awaitingSchedule,
      );

  String get label => switch (this) {
        SchedulingStatus.awaitingSchedule => 'Awaiting Schedule',
        SchedulingStatus.scheduled => 'Scheduled',
      };
}

enum JobStatus {
  requested,
  matched,
  inChat,
  paymentPending,
  escrowLocked,
  inProgress,
  submitted,
  completed,
  disputed,
  resolved,
  cancelled,
  /// Stage 5 (policy D5): an open job that got no booking within the
  /// configured window (default 7 days). Server-set, terminal.
  expired;

  static JobStatus fromString(String s) {
    // "paid_escrow" is written by DemoEscrowService; map it to escrowLocked
    if (s == 'paid_escrow') return JobStatus.escrowLocked;
    return JobStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => JobStatus.requested,
    );
  }

  String get label => switch (this) {
        JobStatus.requested => 'Requested',
        JobStatus.matched => 'Matched',
        JobStatus.inChat => 'In Chat',
        JobStatus.paymentPending => 'Payment Pending',
        JobStatus.escrowLocked => 'Escrow Locked',
        JobStatus.inProgress => 'In Progress',
        JobStatus.submitted => 'Submitted',
        JobStatus.completed => 'Completed',
        JobStatus.disputed => 'Disputed',
        JobStatus.resolved => 'Resolved',
        JobStatus.cancelled => 'Cancelled',
        JobStatus.expired => 'Expired',
      };

  bool get isTerminal =>
      this == JobStatus.completed ||
      this == JobStatus.resolved ||
      this == JobStatus.cancelled ||
      this == JobStatus.expired;

  bool get isActive =>
      this == JobStatus.escrowLocked || this == JobStatus.inProgress || this == JobStatus.submitted;
}

class JobModel {
  final String id;
  final String customerId;
  final String artisanId;
  final String category;
  final String description;
  final List<String> imageUrls;
  final List<String> completionImageUrls;
  // Photos taken by the artisan on arrival, before work starts.
  final List<String> beforePhotoUrls;
  final JobStatus status;
  final double? agreedAmount;
  final String? paymentReference;
  final String? disputeReason;
  final String? disputeResolution;
  final DateTime? disputeWindowEndsAt;
  final String? artisanNotes;
  final double? customerLat;
  final double? customerLng;
  final String? customerAddress;
  final double? budgetMin;
  final double? budgetMax;
  /// 'asap' | 'scheduled'
  final String urgency;
  final DateTime? scheduledDate;
  final DateTime createdAt;
  final DateTime? matchedAt;
  final DateTime? escrowLockedAt;
  final DateTime? startedAt;
  final DateTime? submittedAt;
  final DateTime? completedAt;
  final DateTime? autoReleaseAt;

  /// Artisan-proposed appointment slots (set during inChat).
  final List<DateTime> appointmentSlots;
  /// Customer-confirmed appointment (chosen from [appointmentSlots]).
  final DateTime? confirmedAppointment;

  /// Artisan-updated fine-grained progress within [JobStatus.inProgress].
  /// Null until the artisan sets it after accepting the job.
  final JobProgressStage? progressStage;
  /// Server timestamp of the last progress stage update.
  final DateTime? progressUpdatedAt;

  // ─── Agreement confirmation (Negotiation Completed checkpoint) ───────────
  /// Null until the customer's first confirmation attempt — treated the
  /// same as [AgreementStatus.negotiating] by [AgreementStatus.fromString].
  final AgreementStatus? agreementStatus;
  /// Locked scope-of-work text, set when the customer confirms — may differ
  /// from the original [description] if negotiation changed the scope.
  final String? agreementScope;
  final bool agreementConfirmedByCustomer;
  final bool agreementConfirmedByArtisan;
  final DateTime? agreementCustomerConfirmedAt;
  final DateTime? agreementArtisanConfirmedAt;
  /// Set only when the artisan requests changes instead of accepting.
  final String? agreementChangesRequestedReason;
  /// Server timestamp of the last agreement-related update.
  final DateTime? agreementUpdatedAt;

  // ─── Scheduling (real workflow stage, not just data fields) ──────────────
  /// Null until the agreement is confirmed — treated the same as
  /// [SchedulingStatus.awaitingSchedule] by [SchedulingStatus.fromString].
  final SchedulingStatus? schedulingStatus;
  final DateTime? schedulingUpdatedAt;

  /// Whether scheduling is done or doesn't apply to this job. 'asap' jobs
  /// have nothing to schedule and are always satisfied; 'scheduled' jobs
  /// require [schedulingStatus] == [SchedulingStatus.scheduled]. Single
  /// source of truth for this check — [JobService.canInitPayment] and every
  /// scheduling-aware screen both read this instead of re-deriving it.
  bool get schedulingSatisfied =>
      urgency != 'scheduled' || schedulingStatus == SchedulingStatus.scheduled;

  // ─── Cancellation fields (Feature 2) ─────────────────────────────────────
  /// UID of whoever cancelled — 'customer' | 'artisan' | 'admin'.
  final String? cancelledBy;
  /// Human-readable reason selected by the cancelling party.
  final String? cancellationReason;
  /// Server timestamp set when the job transitions to [JobStatus.cancelled].
  final DateTime? cancelledAt;

  // ─── Paid-job cancellation request (policy D2) ───────────────────────────
  /// Once escrow is funded neither party may cancel directly — they file a
  /// request an admin reviews. 'pending' while awaiting review; admin-set
  /// afterwards. Null when no request was ever filed.
  final String? cancellationRequestStatus;
  final String? cancellationRequestedBy;
  final String? cancellationRequestReason;
  final DateTime? cancellationRequestedAt;

  bool get hasPendingCancellationRequest => cancellationRequestStatus == 'pending';

  // ─── Stage 4 settlement / refund mirror (server-written) ─────────────────
  /// Mirrors the refund's Paystack-reported lifecycle: requested, submitted,
  /// processing, processed, failed, needs_attention. Only 'processed' means
  /// the customer's money is on its way back.
  final String? refundStatus;
  /// 'release' | 'full_refund' | 'split' — an admin dispute/cancellation outcome.
  final String? settlementOutcome;
  final String? settlementStatus;

  // ─── Stage 5: booking confirmation (policy D7) ───────────────────────────
  /// 'awaitingArtisan' while the artisan has not yet confirmed a booking
  /// request (quote acceptance or direct booking); 'confirmed' afterwards.
  final String? bookingStatus;
  /// Server-stamped start of the artisan's confirmation window.
  final DateTime? bookingRequestedAt;
  final DateTime? bookingConfirmedAt;

  bool get awaitingArtisanConfirmation =>
      status == JobStatus.matched && bookingStatus != 'confirmed';

  // ─── Stage 5: rework (policy D4 — one request per job) ───────────────────
  final int reworkCount;
  final String? reworkReason;
  final DateTime? reworkRequestedAt;
  final String? reworkResponse;

  bool get canRequestRework => status == JobStatus.submitted && reworkCount == 0;

  // ─── Stage 5: reopen / expiry (server-written) ───────────────────────────
  final int reopenCount;
  final String? reopenReason;
  final DateTime? expiredAt;

  // ─── Stage 6: coarse public area (P-K, D9) + payout mirror (HT-024) ──────
  /// ~1 km rounded coordinates + geohashes; the exact location is in
  /// jobs/{id}/private/location (see jobPrivateLocationProvider).
  final double? areaLat;
  final double? areaLng;
  final String? areaGeohash4;
  final String? areaLabel;
  /// Server-mirrored payout progress: processing | paid | on_hold | delayed.
  final String? payoutStatus;

  /// Set only when the customer accepted the AI job-improvement suggestion
  /// at creation time: {category, confidence, enhancedDescription}.
  final Map<String, dynamic>? aiSuggestion;

  // ─── Consistency / audit fields (server-written by JobService) ───────────
  /// Firestore server timestamp of the last mutation — set by JobService only.
  final DateTime? lastUpdatedAt;
  /// Role or UID of the last writer: 'customer' | 'artisan' | 'system' | 'admin'
  final String? lastUpdatedBy;
  /// Monotonically incrementing counter. Incremented inside every transaction.
  /// Useful for debugging concurrent write issues.
  final int updateVersion;

  const JobModel({
    required this.id,
    required this.customerId,
    this.artisanId = '',
    required this.category,
    required this.description,
    this.imageUrls = const [],
    this.completionImageUrls = const [],
    this.beforePhotoUrls = const [],
    this.status = JobStatus.requested,
    this.agreedAmount,
    this.paymentReference,
    this.disputeReason,
    this.disputeResolution,
    this.disputeWindowEndsAt,
    this.artisanNotes,
    this.customerLat,
    this.customerLng,
    this.customerAddress,
    this.budgetMin,
    this.budgetMax,
    this.urgency = 'asap',
    this.scheduledDate,
    required this.createdAt,
    this.matchedAt,
    this.escrowLockedAt,
    this.startedAt,
    this.submittedAt,
    this.completedAt,
    this.autoReleaseAt,
    this.appointmentSlots = const [],
    this.confirmedAppointment,
    this.progressStage,
    this.progressUpdatedAt,
    this.agreementStatus,
    this.agreementScope,
    this.agreementConfirmedByCustomer = false,
    this.agreementConfirmedByArtisan = false,
    this.agreementCustomerConfirmedAt,
    this.agreementArtisanConfirmedAt,
    this.agreementChangesRequestedReason,
    this.agreementUpdatedAt,
    this.schedulingStatus,
    this.schedulingUpdatedAt,
    this.cancelledBy,
    this.cancellationReason,
    this.cancelledAt,
    this.cancellationRequestStatus,
    this.cancellationRequestedBy,
    this.cancellationRequestReason,
    this.cancellationRequestedAt,
    this.refundStatus,
    this.settlementOutcome,
    this.settlementStatus,
    this.bookingStatus,
    this.bookingRequestedAt,
    this.bookingConfirmedAt,
    this.reworkCount = 0,
    this.reworkReason,
    this.reworkRequestedAt,
    this.reworkResponse,
    this.reopenCount = 0,
    this.reopenReason,
    this.expiredAt,
    this.areaLat,
    this.areaLng,
    this.areaGeohash4,
    this.areaLabel,
    this.payoutStatus,
    this.aiSuggestion,
    this.lastUpdatedAt,
    this.lastUpdatedBy,
    this.updateVersion = 0,
  });

  factory JobModel.fromJson(Map<String, dynamic> json) => JobModel(
        id: json['id'] as String,
        customerId: json['customerId'] as String? ?? '',
        artisanId: json['artisanId'] as String? ?? '',
        category: json['category'] as String? ?? 'Other',
        description: json['description'] as String? ?? '',
        imageUrls: List<String>.from(json['imageUrls'] ?? []),
        completionImageUrls: List<String>.from(json['completionImageUrls'] ?? []),
        beforePhotoUrls: List<String>.from(json['beforePhotoUrls'] ?? []),
        status: JobStatus.fromString(json['status'] as String? ?? 'requested'),
        agreedAmount: (json['agreedAmount'] as num?)?.toDouble(),
        paymentReference: json['paymentReference'] as String?,
        disputeReason: json['disputeReason'] as String?,
        disputeResolution: json['disputeResolution'] as String?,
        disputeWindowEndsAt: _toDateNullable(json['disputeWindowEndsAt']),
        artisanNotes: json['artisanNotes'] as String?,
        customerLat: (json['customerLat'] as num?)?.toDouble(),
        customerLng: (json['customerLng'] as num?)?.toDouble(),
        customerAddress: json['customerAddress'] as String?,
        budgetMin: (json['budgetMin'] as num?)?.toDouble(),
        budgetMax: (json['budgetMax'] as num?)?.toDouble(),
        urgency: json['urgency'] as String? ?? 'asap',
        scheduledDate: _toDateNullable(json['scheduledDate']),
        createdAt: _toDate(json['createdAt']),
        matchedAt: _toDateNullable(json['matchedAt']),
        escrowLockedAt: _toDateNullable(json['escrowLockedAt']),
        startedAt: _toDateNullable(json['startedAt']),
        submittedAt: _toDateNullable(json['submittedAt']),
        completedAt: _toDateNullable(json['completedAt']),
        autoReleaseAt: _toDateNullable(json['autoReleaseAt']),
        appointmentSlots: (json['appointmentSlots'] as List<dynamic>? ?? [])
            .map<DateTime>((e) => _toDate(e))
            .toList(),
        confirmedAppointment: _toDateNullable(json['confirmedAppointment']),
        progressStage: json['progressStage'] != null
            ? JobProgressStage.fromString(json['progressStage'] as String)
            : null,
        progressUpdatedAt: _toDateNullable(json['progressUpdatedAt']),
        agreementStatus: json['agreementStatus'] != null
            ? AgreementStatus.fromString(json['agreementStatus'] as String)
            : null,
        agreementScope: json['agreementScope'] as String?,
        agreementConfirmedByCustomer: json['agreementConfirmedByCustomer'] as bool? ?? false,
        agreementConfirmedByArtisan: json['agreementConfirmedByArtisan'] as bool? ?? false,
        agreementCustomerConfirmedAt: _toDateNullable(json['agreementCustomerConfirmedAt']),
        agreementArtisanConfirmedAt: _toDateNullable(json['agreementArtisanConfirmedAt']),
        agreementChangesRequestedReason: json['agreementChangesRequestedReason'] as String?,
        agreementUpdatedAt: _toDateNullable(json['agreementUpdatedAt']),
        schedulingStatus: json['schedulingStatus'] != null
            ? SchedulingStatus.fromString(json['schedulingStatus'] as String)
            : null,
        schedulingUpdatedAt: _toDateNullable(json['schedulingUpdatedAt']),
        cancelledBy: json['cancelledBy'] as String?,
        cancellationReason: json['cancellationReason'] as String?,
        cancelledAt: _toDateNullable(json['cancelledAt']),
        cancellationRequestStatus: json['cancellationRequestStatus'] as String?,
        cancellationRequestedBy: json['cancellationRequestedBy'] as String?,
        cancellationRequestReason: json['cancellationRequestReason'] as String?,
        cancellationRequestedAt: _toDateNullable(json['cancellationRequestedAt']),
        refundStatus: json['refundStatus'] as String?,
        settlementOutcome: json['settlementOutcome'] as String?,
        settlementStatus: json['settlementStatus'] as String?,
        bookingStatus: json['bookingStatus'] as String?,
        bookingRequestedAt: _toDateNullable(json['bookingRequestedAt']),
        bookingConfirmedAt: _toDateNullable(json['bookingConfirmedAt']),
        reworkCount: (json['reworkCount'] as num?)?.toInt() ?? 0,
        reworkReason: json['reworkReason'] as String?,
        reworkRequestedAt: _toDateNullable(json['reworkRequestedAt']),
        reworkResponse: json['reworkResponse'] as String?,
        reopenCount: (json['reopenCount'] as num?)?.toInt() ?? 0,
        reopenReason: json['reopenReason'] as String?,
        expiredAt: _toDateNullable(json['expiredAt']),
        areaLat: (json['areaLat'] as num?)?.toDouble(),
        areaLng: (json['areaLng'] as num?)?.toDouble(),
        areaGeohash4: json['areaGeohash4'] as String?,
        areaLabel: json['areaLabel'] as String?,
        payoutStatus: json['payoutStatus'] as String?,
        aiSuggestion: json['aiSuggestion'] as Map<String, dynamic>?,
        lastUpdatedAt: _toDateNullable(json['lastUpdatedAt']),
        lastUpdatedBy: json['lastUpdatedBy'] as String?,
        updateVersion: (json['updateVersion'] as int?) ?? 0,
      );

  static DateTime _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  static DateTime? _toDateNullable(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'artisanId': artisanId,
        'category': category,
        'description': description,
        'imageUrls': imageUrls,
        'completionImageUrls': completionImageUrls,
        if (beforePhotoUrls.isNotEmpty) 'beforePhotoUrls': beforePhotoUrls,
        'status': status.name,
        if (agreedAmount != null) 'agreedAmount': agreedAmount,
        if (paymentReference != null) 'paymentReference': paymentReference,
        if (disputeReason != null) 'disputeReason': disputeReason,
        if (disputeResolution != null) 'disputeResolution': disputeResolution,
        if (disputeWindowEndsAt != null)
          'disputeWindowEndsAt': Timestamp.fromDate(disputeWindowEndsAt!),
        if (artisanNotes != null) 'artisanNotes': artisanNotes,
        if (customerLat != null) 'customerLat': customerLat,
        if (customerLng != null) 'customerLng': customerLng,
        if (customerAddress != null) 'customerAddress': customerAddress,
        if (budgetMin != null) 'budgetMin': budgetMin,
        if (budgetMax != null) 'budgetMax': budgetMax,
        'urgency': urgency,
        if (scheduledDate != null) 'scheduledDate': Timestamp.fromDate(scheduledDate!),
        'createdAt': Timestamp.fromDate(createdAt),
        if (matchedAt != null) 'matchedAt': Timestamp.fromDate(matchedAt!),
        if (escrowLockedAt != null) 'escrowLockedAt': Timestamp.fromDate(escrowLockedAt!),
        if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt!),
        if (submittedAt != null) 'submittedAt': Timestamp.fromDate(submittedAt!),
        if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
        if (autoReleaseAt != null) 'autoReleaseAt': Timestamp.fromDate(autoReleaseAt!),
        if (appointmentSlots.isNotEmpty)
          'appointmentSlots': appointmentSlots.map((d) => Timestamp.fromDate(d)).toList(),
        if (confirmedAppointment != null)
          'confirmedAppointment': Timestamp.fromDate(confirmedAppointment!),
        if (progressStage != null) 'progressStage': progressStage!.name,
        if (progressUpdatedAt != null) 'progressUpdatedAt': Timestamp.fromDate(progressUpdatedAt!),
        if (agreementStatus != null) 'agreementStatus': agreementStatus!.name,
        if (agreementScope != null) 'agreementScope': agreementScope,
        'agreementConfirmedByCustomer': agreementConfirmedByCustomer,
        'agreementConfirmedByArtisan': agreementConfirmedByArtisan,
        if (agreementCustomerConfirmedAt != null)
          'agreementCustomerConfirmedAt': Timestamp.fromDate(agreementCustomerConfirmedAt!),
        if (agreementArtisanConfirmedAt != null)
          'agreementArtisanConfirmedAt': Timestamp.fromDate(agreementArtisanConfirmedAt!),
        if (agreementChangesRequestedReason != null)
          'agreementChangesRequestedReason': agreementChangesRequestedReason,
        if (agreementUpdatedAt != null)
          'agreementUpdatedAt': Timestamp.fromDate(agreementUpdatedAt!),
        if (schedulingStatus != null) 'schedulingStatus': schedulingStatus!.name,
        if (schedulingUpdatedAt != null)
          'schedulingUpdatedAt': Timestamp.fromDate(schedulingUpdatedAt!),
        if (cancelledBy != null) 'cancelledBy': cancelledBy,
        if (cancellationReason != null) 'cancellationReason': cancellationReason,
        if (cancelledAt != null) 'cancelledAt': Timestamp.fromDate(cancelledAt!),
        if (aiSuggestion != null) 'aiSuggestion': aiSuggestion,
        if (lastUpdatedAt != null) 'lastUpdatedAt': Timestamp.fromDate(lastUpdatedAt!),
        if (lastUpdatedBy != null) 'lastUpdatedBy': lastUpdatedBy,
        'updateVersion': updateVersion,
      };

  JobModel copyWith({
    String? artisanId,
    JobStatus? status,
    List<String>? completionImageUrls,
    List<String>? beforePhotoUrls,
    double? agreedAmount,
    String? paymentReference,
    String? disputeReason,
    String? artisanNotes,
    DateTime? matchedAt,
    DateTime? escrowLockedAt,
    DateTime? startedAt,
    DateTime? submittedAt,
    DateTime? completedAt,
    DateTime? autoReleaseAt,
    List<DateTime>? appointmentSlots,
    DateTime? confirmedAppointment,
    JobProgressStage? progressStage,
    DateTime? progressUpdatedAt,
    AgreementStatus? agreementStatus,
    String? agreementScope,
    bool? agreementConfirmedByCustomer,
    bool? agreementConfirmedByArtisan,
    DateTime? agreementCustomerConfirmedAt,
    DateTime? agreementArtisanConfirmedAt,
    String? agreementChangesRequestedReason,
    DateTime? agreementUpdatedAt,
    SchedulingStatus? schedulingStatus,
    DateTime? schedulingUpdatedAt,
    String? cancelledBy,
    String? cancellationReason,
    DateTime? cancelledAt,
  }) =>
      JobModel(
        id: id,
        customerId: customerId,
        artisanId: artisanId ?? this.artisanId,
        category: category,
        description: description,
        imageUrls: imageUrls,
        completionImageUrls: completionImageUrls ?? this.completionImageUrls,
        beforePhotoUrls: beforePhotoUrls ?? this.beforePhotoUrls,
        status: status ?? this.status,
        agreedAmount: agreedAmount ?? this.agreedAmount,
        paymentReference: paymentReference ?? this.paymentReference,
        disputeReason: disputeReason ?? this.disputeReason,
        artisanNotes: artisanNotes ?? this.artisanNotes,
        customerLat: customerLat,
        customerLng: customerLng,
        customerAddress: customerAddress,
        budgetMin: budgetMin,
        budgetMax: budgetMax,
        urgency: urgency,
        scheduledDate: scheduledDate,
        createdAt: createdAt,
        matchedAt: matchedAt ?? this.matchedAt,
        escrowLockedAt: escrowLockedAt ?? this.escrowLockedAt,
        startedAt: startedAt ?? this.startedAt,
        submittedAt: submittedAt ?? this.submittedAt,
        completedAt: completedAt ?? this.completedAt,
        autoReleaseAt: autoReleaseAt ?? this.autoReleaseAt,
        appointmentSlots: appointmentSlots ?? this.appointmentSlots,
        confirmedAppointment: confirmedAppointment ?? this.confirmedAppointment,
        progressStage: progressStage ?? this.progressStage,
        progressUpdatedAt: progressUpdatedAt ?? this.progressUpdatedAt,
        agreementStatus: agreementStatus ?? this.agreementStatus,
        agreementScope: agreementScope ?? this.agreementScope,
        agreementConfirmedByCustomer:
            agreementConfirmedByCustomer ?? this.agreementConfirmedByCustomer,
        agreementConfirmedByArtisan:
            agreementConfirmedByArtisan ?? this.agreementConfirmedByArtisan,
        agreementCustomerConfirmedAt:
            agreementCustomerConfirmedAt ?? this.agreementCustomerConfirmedAt,
        agreementArtisanConfirmedAt:
            agreementArtisanConfirmedAt ?? this.agreementArtisanConfirmedAt,
        agreementChangesRequestedReason:
            agreementChangesRequestedReason ?? this.agreementChangesRequestedReason,
        agreementUpdatedAt: agreementUpdatedAt ?? this.agreementUpdatedAt,
        schedulingStatus: schedulingStatus ?? this.schedulingStatus,
        schedulingUpdatedAt: schedulingUpdatedAt ?? this.schedulingUpdatedAt,
        cancelledBy: cancelledBy ?? this.cancelledBy,
        cancellationReason: cancellationReason ?? this.cancellationReason,
        cancelledAt: cancelledAt ?? this.cancelledAt,
      );
}
