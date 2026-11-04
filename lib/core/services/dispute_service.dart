import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/audit_log_model.dart';
import '../../models/dispute_model.dart';
import '../../models/job_mutation_context.dart';
import '../utils/safe_firestore.dart';
import 'job_service.dart';

/// Write layer for the dispute domain.
///
/// Raising and resolving a dispute both mutate /jobs (status transition)
/// AND /disputes (the record) — those two writes are delegated to
/// [JobService.raiseDisputeWithRecord] / [resolveDisputeWithRecord] so they
/// commit atomically in a single transaction, preserving JobService as the
/// single writer of job documents. The artisan's response to a dispute does
/// NOT touch /jobs, so it is a direct, narrow Firestore write here — exactly
/// the field whitelist permitted by the disputes security rule.
class DisputeService {
  final FirebaseFirestore _db;
  final JobService _jobService;

  DisputeService(this._db, this._jobService);

  CollectionReference<Map<String, dynamic>> get _disputesCol =>
      _db.collection('disputes');

  /// Pre-allocates a dispute document ID. Callers that need to upload
  /// evidence to Storage first (path includes the dispute ID) should call
  /// this, upload, then pass the same ID into [raiseDispute].
  String newDisputeId() => _disputesCol.doc().id;

  /// Either party raises a dispute against the other (Stage 5, policy D3 —
  /// previously customer-only). firestore.rules require [againstUserId] to
  /// be the other party on the job.
  Future<void> raiseDispute({
    required String disputeId,
    required String jobId,
    required String raisedBy,
    required String againstUserId,
    required bool raisedByCustomer,
    required String reason,
    List<String> evidenceImageUrls = const [],
  }) async {
    final disputeRef = _disputesCol.doc(disputeId);
    final ctx = raisedByCustomer
        ? JobMutationContext.customer(uid: raisedBy, actionType: JobActionType.disputeRaised, reason: reason)
        : JobMutationContext.artisan(uid: raisedBy, actionType: JobActionType.disputeRaised, reason: reason);

    await _jobService.raiseDisputeWithRecord(
      ctx,
      jobId,
      disputeId: disputeRef.id,
      reason: reason,
      againstUserId: againstUserId,
      evidenceImageUrls: evidenceImageUrls,
    );

    // Stage 6 (HT-015): this notification is generated server-side from the
    // underlying document change (functions/index.js); clients can no longer
    // create notifications.
  }

  /// Against-party (artisan) responds with their side and evidence.
  /// One-shot — the rule only allows these three fields, and only once
  /// while the dispute is open (a resolved/dismissed dispute is read-only
  /// to non-admins because [resolveDispute] changes its status).
  Future<void> respondToDispute({
    required String disputeId,
    required String responseText,
    List<String> evidenceImageUrls = const [],
  }) async {
    await _disputesCol.doc(disputeId).update({
      'artisanResponseText': responseText,
      'artisanEvidenceUrls': evidenceImageUrls,
      'artisanRespondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin resolves (or dismisses) a dispute.
  ///
  /// Superseded in Stage 4: this wrote a status-only resolution with no money
  /// outcome (HT-007), and firestore.rules now refuse an admin client moving a
  /// funded job to 'resolved'. Use AdminFinanceService.resolveDispute, which
  /// calls the audited adminResolveDispute Cloud Function.
  @Deprecated('Use AdminFinanceService.resolveDispute (adminResolveDispute callable).')
  Future<void> resolveDispute({
    required String jobId,
    required String disputeId,
    required String adminId,
    required String raisedBy,
    required String againstUserId,
    required String resolution,
    String? adminNote,
    bool dismiss = false,
  }) async {
    final ctx = JobMutationContext.admin(
      uid: adminId,
      actionType: JobActionType.disputeResolved,
      reason: resolution,
    );

    await _jobService.resolveDisputeWithRecord(
      ctx,
      jobId,
      disputeId: disputeId,
      resolution: resolution,
      adminNote: adminNote,
      dismiss: dismiss,
    );

    // Stage 6 (HT-015): this notification is generated server-side from the
    // underlying document change (functions/index.js); clients can no longer
    // create notifications.
  }

  /// The single dispute record for a job, if one exists.
  Stream<DisputeModel?> watchDisputeForJob(String jobId) => safeStream(
        _disputesCol.where('jobId', isEqualTo: jobId).limit(1),
        (d) => DisputeModel.fromJson({...d.data(), 'id': d.id}),
        debugLabel: 'disputeForJob:$jobId',
      ).map((list) => list.isEmpty ? null : list.first);

  /// All open/under-review disputes — drives the admin Disputes tab.
  Stream<List<DisputeModel>> watchOpenDisputes() => safeStream(
        _disputesCol.where('status', whereIn: ['open', 'underReview']),
        (d) => DisputeModel.fromJson({...d.data(), 'id': d.id}),
        debugLabel: 'openDisputes',
      ).map((disputes) => disputes..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
}
