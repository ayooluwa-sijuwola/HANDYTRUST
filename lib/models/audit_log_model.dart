import 'package:cloud_firestore/cloud_firestore.dart';

/// Every action that mutates a job document.
enum JobActionType {
  negotiationProposal,  // price proposal sent in chat
  agreedAmountUpdated,  // direct agreedAmount update (no chat message)
  statusTransition,     // catch-all for generic transitions
  workStarted,          // escrowLocked → inProgress
  workSubmitted,        // inProgress → submitted
  jobCompleted,         // submitted → completed (+ escrow release queued)
  disputeRaised,        // → disputed
  disputeResolved,      // → resolved (admin only)
  escrowLocked,         // payment confirmed, → escrowLocked
  jobCancelled,         // → cancelled
  adminOverride,        // admin forced a state change bypassing state machine
  adminEscrowRefund,    // admin forced refund (→ cancelled + refundReason field)
  quoteAccepted,        // requested → matched via QuoteService.acceptQuote
  progressUpdated,      // inProgress: artisan advances the progress stage
  agreementConfirmedByCustomer,  // inChat: customer locks terms, → pendingArtisanConfirmation
  agreementAcceptedByArtisan,    // inChat: artisan accepts → agreementStatus confirmed
  agreementChangesRequested,     // inChat: artisan sends terms back → changesRequested
  paidCancellationRequested,     // escrowLocked/inProgress: party asks admin to cancel (no status change)
}

/// The identity role of the actor who triggered a job mutation.
enum ActorRole { customer, artisan, admin, system }

/// Immutable audit record written atomically with every job mutation.
///
/// Written to: /jobs/{jobId}/auditLogs/{logId}
/// Also queryable via collectionGroup('auditLogs') for admin cross-job searches.
///
/// IMMUTABLE — no update or delete is permitted by Firestore rules.
class AuditLogModel {
  final String id;
  final String jobId;
  /// Same as [id] — the Firestore document ID uniquely identifies the
  /// transaction that produced this log entry.
  final String transactionId;
  final JobActionType actionType;
  final String actorId;
  final ActorRole actorRole;
  final DateTime timestamp;
  final int jobVersionBefore;
  final int jobVersionAfter;
  final String jobStatusBefore;
  /// Null when the mutation did not change job status (e.g. negotiation).
  final String? jobStatusAfter;
  /// The non-server-timestamp fields written in this transaction.
  /// Omits consistency fields (lastUpdatedAt, lastUpdatedBy, updateVersion).
  final Map<String, dynamic> delta;
  final bool isAdminOverride;
  final String? reason;
  final String? overrideReason;

  const AuditLogModel({
    required this.id,
    required this.jobId,
    required this.transactionId,
    required this.actionType,
    required this.actorId,
    required this.actorRole,
    required this.timestamp,
    required this.jobVersionBefore,
    required this.jobVersionAfter,
    required this.jobStatusBefore,
    this.jobStatusAfter,
    required this.delta,
    required this.isAdminOverride,
    this.reason,
    this.overrideReason,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) => AuditLogModel(
        id: json['id'] as String? ?? '',
        jobId: json['jobId'] as String? ?? '',
        transactionId: json['transactionId'] as String? ?? '',
        actionType: JobActionType.values.firstWhere(
          (e) => e.name == json['actionType'],
          orElse: () => JobActionType.statusTransition,
        ),
        actorId: json['actorId'] as String? ?? 'system',
        actorRole: ActorRole.values.firstWhere(
          (e) => e.name == json['actorRole'],
          orElse: () => ActorRole.system,
        ),
        timestamp: _toDate(json['timestamp']),
        jobVersionBefore: (json['jobVersionBefore'] as int?) ?? 0,
        jobVersionAfter: (json['jobVersionAfter'] as int?) ?? 0,
        jobStatusBefore: json['jobStatusBefore'] as String? ?? 'unknown',
        jobStatusAfter: json['jobStatusAfter'] as String?,
        delta: Map<String, dynamic>.from((json['delta'] as Map?) ?? {}),
        isAdminOverride: json['isAdminOverride'] as bool? ?? false,
        reason: json['reason'] as String?,
        overrideReason: json['overrideReason'] as String?,
      );

  /// Produces the data map written to Firestore inside the transaction.
  /// [timestamp] is intentionally a [FieldValue.serverTimestamp()] sentinel
  /// at write time — this method is NOT used for writing; call
  /// [JobService._buildAuditEntry] for that.
  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'transactionId': transactionId,
        'actionType': actionType.name,
        'actorId': actorId,
        'actorRole': actorRole.name,
        'timestamp': Timestamp.fromDate(timestamp),
        'jobVersionBefore': jobVersionBefore,
        'jobVersionAfter': jobVersionAfter,
        'jobStatusBefore': jobStatusBefore,
        if (jobStatusAfter != null) 'jobStatusAfter': jobStatusAfter,
        'delta': delta,
        'isAdminOverride': isAdminOverride,
        if (reason != null) 'reason': reason,
        if (overrideReason != null) 'overrideReason': overrideReason,
      };

  static DateTime _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }
}
