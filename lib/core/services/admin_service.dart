import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/admin_audit_log_model.dart';
import '../../models/job_model.dart';
import 'admin_audit_service.dart';

/// Stage 8.2 (D-5): every admin write that used to live inside the admin
/// dashboard widgets, moved here unchanged — same collections, documents,
/// fields, merge semantics, batches, callables and audit-log entries.
/// The only behavioural change is F-1 (job deletion order and gating).
class AdminService {
  AdminService(this._db, this._functions);
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  AdminAuditService get _audit => AdminAuditService(_db);

  /// Audit entry for an action performed through another service (e.g.
  /// verification approve/reject), exactly as the dashboard wrote it.
  Future<void> audit({required AdminAction action, required String adminId, required String targetId, required String targetType, Map<String, dynamic> metadata = const {}}) =>
      _audit.log(action: action, adminId: adminId, targetId: targetId, targetType: targetType, metadata: metadata);

  /// What is held in escrow for a job (display only, for the settlement
  /// dialog; the server re-derives every amount). Same read as before.
  Future<HeldFunds?> heldFunds(String jobId) async {
    final pays = await _db.collection('payments').where('jobId', isEqualTo: jobId).get();
    final held = pays.docs.map((d) => d.data()).where((p) => p['status'] == 'escrowHeld').toList();
    if (held.isEmpty) return null;
    final pay = held.first;
    final service = (pay['serviceAmount'] as num?) ?? (pay['amount'] as num?);
    final total = (pay['totalCharged'] as num?) ?? service;
    if (service == null || total == null) return null;
    return HeldFunds(total, service);
  }

  /// Dismiss an operational alert (`admin_alerts`).
  Future<void> resolveAlert(String alertId, {required String adminId}) => _db.collection('admin_alerts').doc(alertId).update({
        'resolved': true,
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': adminId,
      });

  /// Approve or reject an artisan application.
  Future<void> setArtisanApproval(String artisanUid, {required bool approve, required String adminId}) async {
    final status = approve ? 'approved' : 'rejected';
    final batch = _db.batch();
    // set(merge:true): update() would abort the whole batch if either doc
    // were missing.
    batch.set(_db.collection('artisans').doc(artisanUid), {
      'approvalStatus': status,
      'isAvailable': approve,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_db.collection('users').doc(artisanUid), {'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await batch.commit();
    await _audit.log(
      action: approve ? AdminAction.artisanApproved : AdminAction.artisanRejected,
      adminId: adminId,
      targetId: artisanUid,
      targetType: 'artisan',
    );
  }

  /// Beta-tester flag on an artisan (quote without ID verification).
  Future<void> setBetaTester(String artisanUid, {required bool value, required bool previous, required String name, required String adminId}) async {
    await _db.collection('artisans').doc(artisanUid).set({'betaTester': value}, SetOptions(merge: true));
    await _audit.log(
      action: AdminAction.betaTesterChanged,
      adminId: adminId,
      targetId: artisanUid,
      targetType: 'artisan',
      metadata: {'previousValue': previous, 'newValue': value, 'name': name},
    );
  }

  /// Suspend (with a policy-D9 type) or reactivate an account.
  Future<void> setAccountStatus({required String uid, required bool suspend, String? suspensionType, required bool isArtisan, required String name, required String adminId}) async {
    final newStatus = suspend ? 'suspended' : 'active';
    final fields = <String, dynamic>{
      'accountStatus': newStatus,
      'suspensionType': suspensionType ?? FieldValue.delete(),
    };
    final batch = _db.batch();
    batch.set(_db.collection('users').doc(uid), fields, SetOptions(merge: true));
    if (isArtisan) batch.set(_db.collection('artisans').doc(uid), fields, SetOptions(merge: true));
    await batch.commit();
    await _audit.log(
      action: suspend ? AdminAction.userSuspended : AdminAction.userReactivated,
      adminId: adminId,
      targetId: uid,
      targetType: 'user',
      metadata: {'name': name, 'newStatus': newStatus},
    );
  }

  /// Server-side account deletion (`adminDeleteUser` callable).
  Future<void> deleteUser(String uid) => _functions.httpsCallable('adminDeleteUser').call({'uid': uid});

  /// Delete a review and recompute the artisan's rating from the rest.
  Future<void> deleteReview({required String reviewId, required String artisanId}) async {
    final others = await _db.collection('reviews').where('artisanId', isEqualTo: artisanId).get();
    final remaining = others.docs.where((d) => d.id != reviewId).map((d) => (d.data()['rating'] as num).toDouble()).toList();
    final count = remaining.length;
    final rating = count == 0 ? 0.0 : double.parse((remaining.reduce((a, b) => a + b) / count).toStringAsFixed(2));
    final batch = _db.batch();
    batch.delete(_db.collection('reviews').doc(reviewId));
    batch.set(_db.collection('artisans').doc(artisanId), {'rating': rating, 'totalRatings': count}, SetOptions(merge: true));
    await batch.commit();
  }

  /// F-1: mirrors the firestore.rules delete clause for /jobs. Only jobs
  /// that never held funds may be removed.
  static bool canDeleteJob(JobModel j) =>
      const {JobStatus.requested, JobStatus.matched, JobStatus.inChat}.contains(j.status) ||
      (j.status == JobStatus.cancelled && (j.paymentReference == null || j.paymentReference!.isEmpty));

  /// Hard-delete a spam/fake job request. F-1: eligibility is checked
  /// BEFORE any write, and the job document is deleted BEFORE its messages,
  /// so a refused delete can never remove chat history. The messages are
  /// listed first because the messages read rule requires the job to exist.
  Future<void> deleteJob(JobModel job, {required String adminId}) async {
    if (!canDeleteJob(job)) {
      throw StateError('This job held funds or is in progress, so its record is kept.');
    }
    final jobRef = _db.collection('jobs').doc(job.id);
    final messages = await jobRef.collection('messages').get();
    await jobRef.delete();
    if (messages.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final d in messages.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await _audit.log(
      action: AdminAction.jobDeleted,
      adminId: adminId,
      targetId: job.id,
      targetType: 'job',
      metadata: {'category': job.category, 'status': job.status.name},
    );
  }

  /// Mark an account-deletion request handled.
  Future<void> resolveDeletionRequest(String uid) async {
    final batch = _db.batch();
    batch.update(_db.collection('account_deletion_requests').doc(uid), {
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.collection('users').doc(uid), {'accountDeletionRequested': false}, SetOptions(merge: true));
    await batch.commit();
  }
}

final adminServiceProvider = Provider<AdminService>((ref) => AdminService(FirebaseFirestore.instance, FirebaseFunctions.instance));

/// Funds held in escrow for a job: what the customer paid and the artisan's
/// agreed price (naira).
class HeldFunds {
  const HeldFunds(this.total, this.service);
  final num total;
  final num service;
}
