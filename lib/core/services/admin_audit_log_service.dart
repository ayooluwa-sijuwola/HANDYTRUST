import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/admin_audit_log_model.dart';

/// Writes immutable records to the top-level `admin_audit_logs` collection.
/// Distinct from [AuditLogModel] which tracks per-job mutations in
/// `jobs/{jobId}/auditLogs`. This collection records admin-level governance
/// actions (approval, suspension, deletion) for the Activity tab.
class AdminAuditLogService {
  final FirebaseFirestore _db;

  AdminAuditLogService(this._db);

  Future<void> log({
    required AdminAction action,
    required String adminId,
    required String targetId,
    required String targetType,
    Map<String, dynamic> metadata = const {},
  }) async {
    final ref = _db.collection('admin_audit_logs').doc();
    await ref.set({
      'id': ref.id,
      'action': action.name,
      'adminId': adminId,
      'targetId': targetId,
      'targetType': targetType,
      'timestamp': FieldValue.serverTimestamp(),
      'metadata': metadata,
    });
  }

  Stream<List<AdminAuditLogModel>> watchRecent({int limit = 150}) =>
      _db
          .collection('admin_audit_logs')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map((d) =>
                    AdminAuditLogModel.fromJson({...d.data(), 'id': d.id}))
                .toList(),
          );
}
