import '../../models/artisan_model.dart';
import '../../models/dispute_model.dart';
import '../../models/job_model.dart';
import '../../models/payment_model.dart';
import '../../models/user_model.dart';
import '../../models/verification_model.dart';

/// F-2 (approved spec §6): every `admin_alerts` type gets a readable label
/// and severity; the raw identifier is always shown next to it.
enum AlertSeverity { actionRequired, needsAttention, information }

/// The existing action an alert offers. No new actions are added; "View in
/// Finance" (U-2) was not approved, so chargeback alerts keep Resolve.
enum AlertAction { resolve, openDispute, settleCancellation, retryPayout, refundCharge, retryRefund, autoReleaseInfo }

class AlertKind {
  const AlertKind(this.label, this.severity, this.action);
  final String label;
  final AlertSeverity severity;
  final AlertAction action;
}

abstract final class AdminAlertCatalog {
  static const kinds = <String, AlertKind>{
    'stuck_escrow_release': AlertKind('Escrow release stuck', AlertSeverity.actionRequired, AlertAction.resolve),
    'dispute': AlertKind('Dispute raised', AlertSeverity.needsAttention, AlertAction.openDispute),
    'dispute_from_job': AlertKind('Dispute raised from job', AlertSeverity.needsAttention, AlertAction.openDispute),
    'paid_cancellation_request': AlertKind('Paid cancellation request', AlertSeverity.actionRequired, AlertAction.settleCancellation),
    'payout_authorization_failed': AlertKind('Payout authorisation failed', AlertSeverity.actionRequired, AlertAction.retryPayout),
    'payout_frozen': AlertKind('Payout frozen', AlertSeverity.needsAttention, AlertAction.retryPayout),
    'autorelease_blocked': AlertKind('Auto-release blocked', AlertSeverity.needsAttention, AlertAction.autoReleaseInfo),
    'transfer_failed': AlertKind('Transfer to artisan failed', AlertSeverity.actionRequired, AlertAction.retryPayout),
    'charge_requires_refund': AlertKind('Charge needs a refund', AlertSeverity.actionRequired, AlertAction.refundCharge),
    'refund_failed': AlertKind('Refund failed at Paystack', AlertSeverity.actionRequired, AlertAction.retryRefund),
    'refund_needs_attention': AlertKind('Refund needs customer bank details', AlertSeverity.needsAttention, AlertAction.resolve),
    'refund_submit_unknown': AlertKind('Refund outcome unknown (reconciling)', AlertSeverity.information, AlertAction.resolve),
    'non_domestic_card_payment': AlertKind('Non-Nigerian card used', AlertSeverity.information, AlertAction.resolve),
    'chargeback_opened': AlertKind('Chargeback opened: payout on hold', AlertSeverity.actionRequired, AlertAction.resolve),
    'chargeback_after_payout': AlertKind('Chargeback opened after payout', AlertSeverity.actionRequired, AlertAction.resolve),
    'chargeback_event_after_close': AlertKind('Chargeback update after case closed', AlertSeverity.needsAttention, AlertAction.resolve),
    'chargeback_paystack_resolved': AlertKind('Paystack resolved the chargeback', AlertSeverity.information, AlertAction.resolve),
    'chargeback_reference_mismatch': AlertKind('Chargeback reference doesn’t match payment', AlertSeverity.actionRequired, AlertAction.resolve),
    'chargeback_unmatched': AlertKind('Chargeback not matched to a payment', AlertSeverity.actionRequired, AlertAction.resolve),
    'chargeback_unverified': AlertKind('Chargeback couldn’t be verified with Paystack', AlertSeverity.needsAttention, AlertAction.resolve),
    'chargeback_event_unsupported': AlertKind('Unsupported chargeback event', AlertSeverity.information, AlertAction.resolve),
    'chargeback_webhook_invalid': AlertKind('Invalid chargeback webhook', AlertSeverity.needsAttention, AlertAction.resolve),
    'chargeback_payout_completed': AlertKind('Payout completed while chargeback open', AlertSeverity.needsAttention, AlertAction.resolve),
    'chargeback_closed': AlertKind('Chargeback closed', AlertSeverity.information, AlertAction.resolve),
    'chargeback_fraud_confirmed': AlertKind('Chargeback marked as confirmed fraud', AlertSeverity.actionRequired, AlertAction.resolve),
    'refund_held_chargeback': AlertKind('Refund held: chargeback open', AlertSeverity.needsAttention, AlertAction.resolve),
    'refund_webhook_unmatched': AlertKind('Refund update not matched to a refund', AlertSeverity.needsAttention, AlertAction.resolve),
    'refund_amount_mismatch': AlertKind('Refund amount differs from request', AlertSeverity.actionRequired, AlertAction.resolve),
  };

  static const unknown = AlertKind('Unrecognised alert', AlertSeverity.information, AlertAction.resolve);

  static AlertKind of(String? type) => kinds[type] ?? unknown;

  static String severityLabel(AlertSeverity s) => switch (s) {
        AlertSeverity.actionRequired => 'Action required',
        AlertSeverity.needsAttention => 'Needs attention',
        AlertSeverity.information => 'Information',
      };

  /// One-line context from the fields the server writes on each alert.
  static String detail(Map<String, dynamic> a) {
    final parts = <String>[
      if (a['jobId'] is String) 'Job ${a['jobId']}',
      if (a['refundId'] is String) 'Refund ${a['refundId']}',
      if (a['reference'] is String) 'Charge ${a['reference']}',
      if (a['disputeId'] is String) 'Case ${a['disputeId']}',
      if (a['cardCountry'] is String) 'Card country ${a['cardCountry']}',
    ];
    final msg = a['message'] ?? a['reason'] ?? a['error'];
    if (msg is String && msg.isNotEmpty) parts.add(msg);
    return parts.isEmpty ? 'No further details recorded' : parts.join(' · ');
  }
}

/// Dashboard figures, computed only from records the admin can read.
/// Totals come from Firestore count() queries; distributions and trends
/// from the loaded lists (the latest N documents), labelled as such.
class AdminMetrics {
  const AdminMetrics._();

  static const activeStatuses = {
    JobStatus.matched, JobStatus.inChat, JobStatus.paymentPending, JobStatus.escrowLocked, JobStatus.inProgress, JobStatus.submitted, JobStatus.disputed,
  };

  static int activeJobs(Iterable<JobModel> jobs) => jobs.where((j) => activeStatuses.contains(j.status)).length;
  static int completedJobs(Iterable<JobModel> jobs) => jobs.where((j) => j.status == JobStatus.completed || j.status == JobStatus.resolved).length;

  /// Money currently held: payments in escrow (charged amount when known).
  static double escrowHeld(Iterable<PaymentModel> payments) => payments
      .where((p) => p.status == PaymentStatus.escrowHeld || p.status == PaymentStatus.releasing)
      .fold(0.0, (s, p) => s + (p.totalCharged ?? p.amount));

  /// Mean rating over artisans that have at least one rating; null if none.
  static double? averageRating(Iterable<ArtisanModel> artisans) {
    final rated = artisans.where((a) => a.totalRatings > 0).toList();
    if (rated.isEmpty) return null;
    return rated.fold(0.0, (s, a) => s + a.rating) / rated.length;
  }

  /// Jobs created per day over the last [days] days (oldest first).
  static List<int> jobsPerDay(Iterable<JobModel> jobs, DateTime now, {int days = 7}) {
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final out = List<int>.filled(days, 0);
    for (final j in jobs) {
      final d = DateTime(j.createdAt.year, j.createdAt.month, j.createdAt.day);
      final i = d.difference(start).inDays;
      if (i >= 0 && i < days) out[i]++;
    }
    return out;
  }

  /// Jobs per category created in the last [days] days, largest first.
  static List<(String, int)> topCategories(Iterable<JobModel> jobs, DateTime now, {int days = 30, int limit = 5}) {
    final from = now.subtract(Duration(days: days));
    final counts = <String, int>{};
    for (final j in jobs.where((j) => j.createdAt.isAfter(from))) {
      counts[j.category] = (counts[j.category] ?? 0) + 1;
    }
    final list = counts.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return list.take(limit).toList();
  }

  /// Share of finished jobs that completed (vs cancelled/expired); null if
  /// nothing has finished.
  static double? completionRate(Iterable<JobModel> jobs) {
    final done = completedJobs(jobs);
    final failed = jobs.where((j) => j.status == JobStatus.cancelled || j.status == JobStatus.expired).length;
    final total = done + failed;
    return total == 0 ? null : done / total;
  }

  /// Share of reviewed verification submissions that were approved.
  static double? verificationApprovalRate(Iterable<VerificationModel> v) {
    final approved = v.where((x) => x.status == VerificationStatus.approved).length;
    final rejected = v.where((x) => x.status == VerificationStatus.rejected).length;
    final total = approved + rejected;
    return total == 0 ? null : approved / total;
  }

  /// Disputes per funded job (jobs that ever reached escrow).
  static double? disputeRate(Iterable<DisputeModel> disputes, Iterable<JobModel> jobs) {
    final funded = jobs.where((j) => j.escrowLockedAt != null || const {JobStatus.escrowLocked, JobStatus.inProgress, JobStatus.submitted, JobStatus.disputed, JobStatus.completed, JobStatus.resolved}.contains(j.status)).length;
    return funded == 0 ? null : disputes.length / funded;
  }

  /// Users who joined in the last 7 days vs the 7 days before; null when
  /// there is nothing to compare with.
  static (int, int) joinedThisAndLastWeek(Iterable<UserModel> users, DateTime now) {
    final weekAgo = now.subtract(const Duration(days: 7));
    final twoWeeksAgo = now.subtract(const Duration(days: 14));
    final thisWeek = users.where((u) => u.createdAt.isAfter(weekAgo)).length;
    final lastWeek = users.where((u) => u.createdAt.isAfter(twoWeeksAgo) && !u.createdAt.isAfter(weekAgo)).length;
    return (thisWeek, lastWeek);
  }
}
