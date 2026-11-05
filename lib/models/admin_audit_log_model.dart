import 'package:cloud_firestore/cloud_firestore.dart';

/// Actions tracked in `admin_audit_logs/{logId}` — admin-only writes via
/// [AdminAuditService]. Distinct from [AuditLogModel] (which tracks job
/// mutations in `jobs/{jobId}/auditLogs`).
enum AdminAction {
  artisanApproved,
  artisanRejected,
  verificationApproved,
  verificationRejected,
  userSuspended,
  userReactivated,
  userDeleted,
  jobDeleted,
  jobCancelled,
  disputeResolved,
  adminLogin,
  adminOverride,
  betaTesterChanged,
}

/// Firestore's serialized `action` value for each [AdminAction]. Every
/// value defaults to the enum's own camelCase [AdminAction.name] (the
/// convention every action already used) — [betaTesterChanged] is the one
/// deliberate exception, stored as the snake_case `beta_tester_changed`
/// per design/BETA_TESTING_GUIDE.md's audit-entry spec. Same pattern this
/// codebase already uses for VerificationStatus.pendingLater ↔
/// 'pending_later' — a Dart-idiomatic enum name and a specific required
/// wire value are allowed to differ, deliberately, via one small mapping,
/// rather than picking a name that's awkward in one place to satisfy the
/// other.
extension AdminActionJson on AdminAction {
  String toJsonValue() => switch (this) {
        AdminAction.betaTesterChanged => 'beta_tester_changed',
        _ => name,
      };
}

AdminAction _adminActionFromJsonValue(String? v) => switch (v) {
      'beta_tester_changed' => AdminAction.betaTesterChanged,
      _ => AdminAction.values.firstWhere(
          (e) => e.name == v,
          orElse: () => AdminAction.adminOverride,
        ),
    };

/// Immutable admin action record written to `admin_audit_logs/{logId}`.
/// Written by [AdminAuditService] — no client outside that service may
/// write to this collection (enforced by Firestore rules).
class AdminAuditLogModel {
  final String id;
  final AdminAction action;
  final String adminId;
  final String targetId;
  final String targetType; // 'artisan' | 'user' | 'job' | 'verification'
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  /// Stage 8.2: the action string exactly as recorded. Cloud Functions write
  /// actions outside [AdminAction] (e.g. payoutFrozen, chargeRefunded);
  /// those parse to [AdminAction.adminOverride], so the audit log shows this.
  final String actionId;

  const AdminAuditLogModel({
    required this.id,
    required this.action,
    required this.adminId,
    required this.targetId,
    required this.targetType,
    required this.timestamp,
    this.metadata = const {},
    this.actionId = '',
  });

  factory AdminAuditLogModel.fromJson(Map<String, dynamic> json) =>
      AdminAuditLogModel(
        id: json['id'] as String? ?? '',
        action: _adminActionFromJsonValue(json['action'] as String?),
        adminId: json['adminId'] as String? ?? '',
        targetId: json['targetId'] as String? ?? '',
        targetType: json['targetType'] as String? ?? '',
        timestamp: _toDate(json['timestamp']),
        metadata: Map<String, dynamic>.from((json['metadata'] as Map?) ?? {}),
        actionId: json['action'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action.toJsonValue(),
        'adminId': adminId,
        'targetId': targetId,
        'targetType': targetType,
        'timestamp': Timestamp.fromDate(timestamp),
        'metadata': metadata,
      };

  String get actionLabel => switch (action) {
        AdminAction.artisanApproved => 'Artisan Approved',
        AdminAction.artisanRejected => 'Artisan Rejected',
        AdminAction.verificationApproved => 'Verification Approved',
        AdminAction.verificationRejected => 'Verification Rejected',
        AdminAction.userSuspended => 'User Suspended',
        AdminAction.userReactivated => 'User Reactivated',
        AdminAction.userDeleted => 'User Deleted',
        AdminAction.jobDeleted => 'Job Deleted',
        AdminAction.jobCancelled => 'Job Cancelled',
        AdminAction.disputeResolved => 'Dispute Resolved',
        AdminAction.adminLogin => 'Admin Login',
        AdminAction.adminOverride => 'Admin Override',
        AdminAction.betaTesterChanged => 'Beta Tester Changed',
      };

  static DateTime _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }
}
