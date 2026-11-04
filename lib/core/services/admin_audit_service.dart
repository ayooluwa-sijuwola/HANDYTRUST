import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/admin_audit_log_model.dart';
import '../utils/safe_firestore.dart';

/// Single write layer for `admin_audit_logs/{logId}`.
///
/// Called by [VerificationService], the admin dashboard, and any service that
/// executes privileged mutations. Collection is admin-read / admin-write only
/// (Firestore rules block all other clients).
class AdminAuditService {
  final FirebaseFirestore _db;

  AdminAuditService(this._db);

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('admin_audit_logs');

  /// Writes a new immutable audit entry.
  Future<void> log({
    required AdminAction action,
    required String adminId,
    required String targetId,
    required String targetType,
    Map<String, dynamic> metadata = const {},
  }) async {
    final ref = _col.doc();
    await ref.set({
      'id': ref.id,
      'action': action.toJsonValue(),
      'adminId': adminId,
      'targetId': targetId,
      'targetType': targetType,
      'timestamp': FieldValue.serverTimestamp(),
      'metadata': metadata,
    });
  }

  /// Writes inside a caller's existing [Transaction] — used when the audit
  /// entry must be atomic with another write (e.g. artisan approval batch).
  void logInBatch(
    WriteBatch batch, {
    required AdminAction action,
    required String adminId,
    required String targetId,
    required String targetType,
    Map<String, dynamic> metadata = const {},
  }) {
    final ref = _col.doc();
    batch.set(ref, {
      'id': ref.id,
      'action': action.toJsonValue(),
      'adminId': adminId,
      'targetId': targetId,
      'targetType': targetType,
      'timestamp': FieldValue.serverTimestamp(),
      'metadata': metadata,
    });
  }

  /// All admin actions, newest-first — drives the admin Activity tab.
  Stream<List<AdminAuditLogModel>> watchAll({int limit = 200}) => safeStream(
        _col.orderBy('timestamp', descending: true).limit(limit),
        (d) => AdminAuditLogModel.fromJson({...d.data(), 'id': d.id}),
        debugLabel: 'adminAuditLogs',
      );
}
