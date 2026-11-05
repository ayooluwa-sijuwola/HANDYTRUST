import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/admin_audit_service.dart';
import '../core/utils/safe_firestore.dart';
import '../models/admin_audit_log_model.dart';
import '../models/artisan_model.dart';
import '../models/dispute_model.dart';
import '../models/finance_record.dart';
import '../models/job_model.dart';
import '../models/payment_model.dart';
import '../models/user_model.dart';
import '../models/verification_model.dart';

/// Stage 8.2: admin data sources, moved out of the old dashboard widget
/// file with the same queries (limits, ordering, client-side sorting that
/// avoids composite indexes). Admin read access is granted by the rules'
/// isAdmin(); the router's /admin guard is a UI convenience only.

FirebaseFirestore get _db => FirebaseFirestore.instance;

/// Latest 200 users.
final adminUsersProvider = StreamProvider<List<UserModel>>((ref) => safeStream(
      _db.collection('users').orderBy('createdAt', descending: true).limit(200),
      (d) => UserModel.fromJson({...d.data(), 'uid': d.id}),
      debugLabel: 'adminUsers',
    ));

/// Latest 200 jobs.
final adminJobsProvider = StreamProvider<List<JobModel>>((ref) => safeStream(
      _db.collection('jobs').orderBy('createdAt', descending: true).limit(200),
      (d) => JobModel.fromJson({...d.data(), 'id': d.id}),
      debugLabel: 'adminJobs',
    ));

/// Latest 200 artisans.
final adminArtisansProvider = StreamProvider<List<ArtisanModel>>((ref) => safeStream(
      _db.collection('artisans').orderBy('createdAt', descending: true).limit(200),
      (d) => ArtisanModel.fromJson({...d.data(), 'uid': d.id}),
      debugLabel: 'adminArtisans',
    ));

/// Artisan applications awaiting approval, oldest first (sorted client-side).
final adminPendingArtisansProvider = StreamProvider<List<ArtisanModel>>((ref) => safeStream(
      _db.collection('artisans').where('approvalStatus', isEqualTo: 'pending'),
      (d) => ArtisanModel.fromJson({...d.data(), 'uid': d.id}),
      debugLabel: 'adminPendingArtisans',
    ).map((l) => l..sort((a, b) => a.createdAt.compareTo(b.createdAt))));

/// Account-deletion requests, newest first.
final adminDeletionRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) => _db
    .collection('account_deletion_requests')
    .orderBy('requestedAt', descending: true)
    .limit(100)
    .snapshots()
    .map((s) => s.docs.map((d) => Map<String, dynamic>.from({...d.data(), 'uid': d.id})).toList()));

/// Unresolved operational alerts written by Cloud Functions, newest first.
final adminAlertsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) => safeStream(
      _db.collection('admin_alerts').where('resolved', isEqualTo: false).limit(100),
      (d) => Map<String, dynamic>.from({...d.data(), 'id': d.id}),
      debugLabel: 'adminAlerts',
    ).map((l) => l..sort((a, b) => (b['createdAt'] as Timestamp? ?? Timestamp(0, 0)).compareTo(a['createdAt'] as Timestamp? ?? Timestamp(0, 0)))));

/// Up to 500 payments (escrow figures).
final adminPaymentsProvider = StreamProvider<List<PaymentModel>>((ref) => safeStream(
      _db.collection('payments').limit(500),
      (d) => PaymentModel.fromJson({...d.data(), 'id': d.id}),
      debugLabel: 'adminPayments',
    ));

/// Latest 200 disputes (all statuses).
final adminDisputesProvider = StreamProvider<List<DisputeModel>>((ref) => safeStream(
      _db.collection('disputes').orderBy('createdAt', descending: true).limit(200),
      (d) => DisputeModel.fromJson({...d.data(), 'id': d.id}),
      debugLabel: 'adminDisputes',
    ));

/// Up to 500 verification submissions (all statuses).
final adminVerificationsProvider = StreamProvider<List<VerificationModel>>((ref) => safeStream(
      _db.collection('verifications').limit(500),
      (d) => VerificationModel.fromJson(d.data()),
      debugLabel: 'adminVerifications',
    ));

/// Admin audit log, newest first (latest 200).
final adminAuditLogsProvider = StreamProvider<List<AdminAuditLogModel>>((ref) => AdminAuditService(_db).watchAll());

/// Display names for a set of uids (users docs), keyed by a sorted,
/// comma-joined id string so repeat lookups are cached.
final adminPeopleNamesProvider = FutureProvider.family<Map<String, String>, String>((ref, idsKey) async {
  if (idsKey.isEmpty) return const {};
  final ids = idsKey.split(',');
  final out = <String, String>{};
  for (var i = 0; i < ids.length; i += 30) {
    final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
    final snap = await _db.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
    for (final d in snap.docs) {
      out[d.id] = (d.data()['name'] as String?) ?? '';
    }
  }
  return out;
});

String peopleKey(Iterable<String> ids) => (ids.where((s) => s.isNotEmpty).toSet().toList()..sort()).join(',');

/// Exact collection totals (Firestore count() aggregation; no documents
/// are downloaded). Stage 8.2: the old dashboard counted the 200-document
/// lists, so "Total users" could never exceed 200.
class AdminTotals {
  const AdminTotals({required this.users, required this.artisans, required this.jobs, required this.admins});
  final int users;
  final int artisans;
  final int jobs;
  final int admins;
}

final adminTotalsProvider = FutureProvider<AdminTotals>((ref) async {
  Future<int> count(Query<Map<String, dynamic>> q) async => (await q.count().get()).count ?? 0;
  final r = await Future.wait([
    count(_db.collection('users')),
    count(_db.collection('artisans')),
    count(_db.collection('jobs')),
    count(_db.collection('admins')),
  ]);
  return AdminTotals(users: r[0], artisans: r[1], jobs: r[2], admins: r[3]);
});

/// Finance records (read-only), newest first, latest 200 per collection.
final adminFinanceProvider = StreamProvider.family<List<FinanceRecord>, FinanceKind>((ref, kind) => safeStream(
      _db.collection(kind.collection).orderBy(kind.timeField, descending: true).limit(200),
      (d) => FinanceRecord(kind, d.id, d.data()),
      debugLabel: 'adminFinance:${kind.collection}',
    ));
