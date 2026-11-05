import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/admin_catalog.dart';
import '../../core/services/admin_finance_service.dart';
import '../../core/services/admin_service.dart';
import '../../models/job_model.dart';
import '../../models/review_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/review_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../theme/ht_theme.dart';
import 'admin_kit.dart';
import 'admin_shell.dart';

String _pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(v < 0.1 ? 1 : 0)}%';

String _compactNaira(double v) {
  if (v >= 1e6) return '₦${(v / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e3) return '₦${(v / 1e3).toStringAsFixed(v >= 1e5 ? 0 : 1)}k';
  return HtFormat.naira(v);
}

// ─── Dashboard (AD-1) ───────────────────────────────────────────────────────

class AdminDashboardSection extends ConsumerWidget {
  const AdminDashboardSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = clock.now();
    final totals = ref.watch(adminTotalsProvider).asData?.value;
    final users = ref.watch(adminUsersProvider).asData?.value ?? const [];
    final jobs = ref.watch(adminJobsProvider).asData?.value ?? const <JobModel>[];
    final artisans = ref.watch(adminArtisansProvider).asData?.value ?? const [];
    final payments = ref.watch(adminPaymentsProvider).asData?.value ?? const [];
    final disputes = ref.watch(adminDisputesProvider).asData?.value ?? const [];
    final verifications = ref.watch(adminVerificationsProvider).asData?.value ?? const [];
    final counts = ref.watch(adminPendingCountsProvider);
    final loading = ref.watch(adminJobsProvider).isLoading || ref.watch(adminUsersProvider).isLoading;
    final jobsSampled = totals != null && totals.jobs > jobs.length;
    final (joined, joinedBefore) = AdminMetrics.joinedThisAndLastWeek(users, now);
    final avg = AdminMetrics.averageRating(artisans);
    final responseMins = artisans.map((a) => a.responseTimeMinutes).where((m) => m > 0).toList();
    final avgResponse = responseMins.isEmpty ? null : responseMins.reduce((a, b) => a + b) / responseMins.length;

    return AdminPage(
      title: 'Dashboard',
      subtitle: 'Platform overview from live records',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (loading) const LinearProgressIndicator(minHeight: 2),
        AdminGrid(children: [
          AdminStatCard(icon: Icons.people_outline_rounded, label: 'Total users', value: totals == null ? '—' : '${totals.users}', note: '$joined joined in the last 7 days (previous 7: $joinedBefore)', onTap: () => context.go(AdminSection.users.path)),
          AdminStatCard(icon: Icons.handyman_outlined, label: 'Total artisans', value: totals == null ? '—' : '${totals.artisans}', note: '${counts[AdminSection.artisans] ?? 0} awaiting approval', onTap: () => context.go(AdminSection.artisans.path)),
          AdminStatCard(icon: Icons.work_outline_rounded, label: 'Active jobs', value: '${AdminMetrics.activeJobs(jobs)}', note: jobsSampled ? 'In the latest ${jobs.length} of ${totals.jobs} jobs' : 'Booked through to customer review', onTap: () => context.go(AdminSection.jobs.path)),
          AdminStatCard(icon: Icons.lock_outline_rounded, label: 'Held in escrow', value: _compactNaira(AdminMetrics.escrowHeld(payments)), note: 'Payments currently held (charged amount)', onTap: () => context.go(AdminSection.finance.path)),
          AdminStatCard(icon: Icons.task_alt_rounded, label: 'Completed jobs', value: '${AdminMetrics.completedJobs(jobs)}', note: jobsSampled ? 'In the latest ${jobs.length} jobs' : 'Completed or resolved'),
          AdminStatCard(icon: Icons.verified_user_outlined, label: 'Pending verifications', value: '${counts[AdminSection.verifications] ?? 0}', note: 'ID and selfie submissions to review', onTap: () => context.go(AdminSection.verifications.path)),
          AdminStatCard(icon: Icons.star_outline_rounded, label: 'Average rating', value: avg == null ? '—' : avg.toStringAsFixed(1), note: 'Mean of rated artisans'),
          AdminStatCard(icon: Icons.admin_panel_settings_outlined, label: 'Administrators', value: totals == null ? '—' : '${totals.admins}', note: 'Accounts with admin access'),
        ]),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, c) {
          final left = [const _AlertsPanel(), const SizedBox(height: 16), _JobsChartPanel(jobs: jobs, now: now)];
          final right = [
            _PendingPanel(counts: counts),
            const SizedBox(height: 16),
            _CategoriesPanel(jobs: jobs, now: now),
            const SizedBox(height: 16),
            AdminPanel(
              title: 'Platform health',
              trailing: AdminLink(label: 'Analytics', onTap: () => context.go(AdminSection.analytics.path)),
              child: Column(children: [
                adminFact(context, 'Completion rate', _pct(AdminMetrics.completionRate(jobs))),
                adminFact(context, 'Verification approval', _pct(AdminMetrics.verificationApprovalRate(verifications))),
                adminFact(context, 'Artisan response time', avgResponse == null ? '—' : (avgResponse >= 60 ? '${(avgResponse / 60).toStringAsFixed(1)} h' : '${avgResponse.round()} min')),
                adminFact(context, 'Disputes per funded job', _pct(AdminMetrics.disputeRate(disputes, jobs))),
              ]),
            ),
          ];
          if (c.maxWidth < 900) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...left, const SizedBox(height: 16), ...right]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
          ]);
        }),
      ]),
    );
  }
}

class _PendingPanel extends StatelessWidget {
  const _PendingPanel({required this.counts});
  final Map<AdminSection, int> counts;
  @override
  Widget build(BuildContext context) {
    final rows = [
      (Icons.handyman_outlined, 'Artisan approvals', AdminSection.artisans),
      (Icons.verified_user_outlined, 'Verifications', AdminSection.verifications),
      (Icons.support_agent_rounded, 'Support tickets', AdminSection.support),
      (Icons.gavel_rounded, 'Open disputes', AdminSection.disputes),
      (Icons.person_remove_outlined, 'Deletion requests', AdminSection.deletions),
    ];
    return AdminPanel(
      title: 'Pending actions',
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(children: [
        for (final (icon, label, s) in rows)
          HtMenuRow(icon: icon, title: label, trailing: AdminCountBadge(counts[s] ?? 0), onTap: () => context.go(s.path)),
      ]),
    );
  }
}

class _AlertsPanel extends ConsumerWidget {
  const _AlertsPanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(adminAlertsProvider);
    return AdminPanel(
      title: 'Operational alerts',
      badge: alerts.asData?.value.length,
      child: alerts.when(
        loading: () => const HtLoadingView(),
        error: (e, _) => HtErrorView(message: 'Alerts could not be loaded.', onRetry: () => ref.invalidate(adminAlertsProvider)),
        data: (list) => list.isEmpty
            ? const HtEmptyView(icon: Icons.task_alt_rounded, title: 'No open alerts', message: 'Alerts written by the server appear here.')
            : Column(children: [for (final a in list.take(8)) AdminAlertRow(alert: a)]),
      ),
    );
  }
}

/// One operational alert: approved label + severity, the unchanged type
/// identifier, server-recorded context, and its existing action(s).
class AdminAlertRow extends ConsumerStatefulWidget {
  const AdminAlertRow({super.key, required this.alert});
  final Map<String, dynamic> alert;
  @override
  ConsumerState<AdminAlertRow> createState() => _AdminAlertRowState();
}

class _AdminAlertRowState extends ConsumerState<AdminAlertRow> {
  bool _busy = false;

  String? get _adminId => ref.read(currentUserProvider).asData?.value?.uid;

  Future<void> _resolve() async {
    final adminId = _adminId;
    if (adminId == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminServiceProvider).resolveAlert(widget.alert['id'] as String, adminId: adminId);
    } catch (e) {
      if (mounted) htSnack(context, 'Could not resolve the alert: ${adminError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(AlertKind kind) async {
    final a = widget.alert;
    final finance = ref.read(adminFinanceServiceProvider);
    final jobId = a['jobId'] as String?;
    Future<void> Function()? run;
    switch (kind.action) {
      case AlertAction.openDispute:
        context.go(AdminSection.disputes.path);
        return;
      case AlertAction.autoReleaseInfo:
        htSnack(context, 'Lift the freeze or suspension first; auto-release then runs within the hour.');
        return;
      case AlertAction.settleCancellation:
        if (jobId == null) return;
        final d = await showSettlementDialog(context, loadHeld: ref.read(adminServiceProvider).heldFunds, title: 'Paid cancellation request', jobId: jobId, allowDecline: true, allowRelease: false, initialOutcome: 'decline');
        if (d == null) return;
        run = () => finance.resolveCancellation(jobId: jobId, decision: d.outcome, reason: d.reason, artisanAmount: d.artisanAmount, refundAmount: d.refundAmount);
      case AlertAction.refundCharge:
        final reference = a['reference'] as String?;
        if (reference == null) return;
        final reason = await showAdminReasonDialog(context, title: 'Refund charge', message: 'Refund the full captured amount of charge $reference to the customer.', confirmLabel: 'Refund');
        if (reason == null) return;
        run = () => finance.refundCharge(reference: reference, reason: reason);
      case AlertAction.retryRefund:
        final refundId = a['refundId'] as String?;
        if (refundId == null) return;
        final reason = await showAdminReasonDialog(context, title: 'Retry refund', message: 'Submit this refund to Paystack again.', confirmLabel: 'Retry');
        if (reason == null) return;
        run = () => finance.retryRefund(refundId: refundId, reason: reason);
      case AlertAction.retryPayout:
        if (jobId == null) return;
        final reason = await showAdminReasonDialog(context, title: 'Retry payout', message: 'Retry the payout for this job. If a freeze or suspension is still active, it stays frozen.', confirmLabel: 'Retry payout');
        if (reason == null) return;
        run = () => finance.retryPayout(jobId: jobId, reason: reason);
      case AlertAction.resolve:
        return _resolve();
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await run();
      await _resolve(); // only after the server accepted the action
    } catch (e) {
      if (mounted) htSnack(context, 'Action failed: ${financeError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final a = widget.alert;
    final type = a['type'] as String?;
    final kind = AdminAlertCatalog.of(type);
    final created = (a['createdAt'] as Timestamp?)?.toDate();
    final tone = alertTone(kind.severity);
    final actionLabel = switch (kind.action) {
      AlertAction.openDispute => 'Open disputes',
      AlertAction.settleCancellation => 'Decide',
      AlertAction.retryPayout => 'Retry payout',
      AlertAction.refundCharge => 'Refund charge',
      AlertAction.retryRefund => 'Retry refund',
      AlertAction.autoReleaseInfo => 'What to do',
      AlertAction.resolve => null,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(kind.severity == AlertSeverity.information ? Icons.info_outline_rounded : Icons.error_outline_rounded,
            color: tone == HtTone.danger ? p.danger : (tone == HtTone.warning ? p.warning : p.textSecondary)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(kind.label, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14))),
              if (created != null) Text(HtFormat.timeAgo(created, now: clock.now()), style: HtType.small(p.textMuted).copyWith(fontSize: 11)),
            ]),
            const SizedBox(height: 2),
            Text(AdminAlertCatalog.detail(a), style: HtType.small(p.textSecondary), maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              HtStatusPill(label: AdminAlertCatalog.severityLabel(kind.severity), tone: tone),
              Text(type ?? 'unknown', style: HtType.small(p.textMuted).copyWith(fontSize: 11, letterSpacing: 0.2)),
            ]),
            const SizedBox(height: 8),
            if (_busy)
              const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (actionLabel != null) HtSmallPrimaryButton(label: actionLabel, onPressed: () => _act(kind)),
                HtSecondaryButton(label: 'Resolve', dense: true, onPressed: _resolve),
              ]),
          ]),
        ),
      ]),
    );
  }
}

/// Simple accessible bar chart (values + labels; no invented scale).
class AdminBars extends StatelessWidget {
  const AdminBars({super.key, required this.values, required this.labels, this.height = 150, this.semanticsLabel});
  final List<num> values;
  final List<String> labels;
  final double height;
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final max = values.fold<num>(0, (m, v) => v > m ? v : m);
    return Semantics(
      label: semanticsLabel ?? [for (var i = 0; i < values.length; i++) '${labels[i]} ${values[i]}'].join(', '),
      child: SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${values[i]}', style: HtType.small(p.textSecondary).copyWith(fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    height: max == 0 ? 2 : ((height - 44) * values[i] / max).clamp(2, height - 44).toDouble(),
                    decoration: BoxDecoration(color: i == values.length - 1 ? p.accentStrong : p.accent.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
                  ),
                  const SizedBox(height: 6),
                  Text(labels[i], style: HtType.small(p.textMuted).copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.clip),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _JobsChartPanel extends StatelessWidget {
  const _JobsChartPanel({required this.jobs, required this.now});
  final List<JobModel> jobs;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final counts = AdminMetrics.jobsPerDay(jobs, now);
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final labels = [for (var i = 6; i >= 0; i--) days[now.subtract(Duration(days: i)).weekday - 1]];
    return AdminPanel(
      title: 'Jobs created',
      subtitle: 'Last 7 days · from the latest ${jobs.length} jobs',
      child: AdminBars(values: counts, labels: labels),
    );
  }
}

class _CategoriesPanel extends StatelessWidget {
  const _CategoriesPanel({required this.jobs, required this.now});
  final List<JobModel> jobs;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final top = AdminMetrics.topCategories(jobs, now);
    final max = top.isEmpty ? 1 : top.first.$2;
    return AdminPanel(
      title: 'Top categories',
      subtitle: 'Jobs created, last 30 days',
      child: top.isEmpty
          ? Text('No jobs in the last 30 days.', style: HtType.small(p.textMuted))
          : Column(children: [
              for (final (cat, n) in top)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(width: 96, child: Text(cat, style: HtType.small(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: n / max, minHeight: 10, backgroundColor: p.surfaceRaised, color: p.accentStrong),
                      ),
                    ),
                    SizedBox(width: 36, child: Text('$n', textAlign: TextAlign.right, style: HtType.smallStrong(p.textPrimary))),
                  ]),
                ),
            ]),
    );
  }
}

// ─── Analytics (AD-11) ──────────────────────────────────────────────────────

class AdminAnalyticsSection extends ConsumerWidget {
  const AdminAnalyticsSection({super.key});

  static List<int> _perWeek(Iterable<DateTime> dates, DateTime now, int weeks) {
    final out = List<int>.filled(weeks, 0);
    for (final d in dates) {
      final w = now.difference(d).inDays ~/ 7;
      if (w >= 0 && w < weeks) out[weeks - 1 - w]++;
    }
    return out;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final now = clock.now();
    final users = ref.watch(adminUsersProvider).asData?.value ?? const [];
    final jobs = ref.watch(adminJobsProvider).asData?.value ?? const <JobModel>[];
    final reviews = ref.watch(allReviewsProvider).asData?.value ?? const <ReviewModel>[];
    final artisans = ref.watch(adminArtisansProvider).asData?.value ?? const [];
    const weeks = 8;
    final weekLabels = [for (var i = weeks - 1; i >= 0; i--) i == 0 ? 'This wk' : '-${i}w'];
    final byStatus = <JobStatus, int>{};
    for (final j in jobs) {
      byStatus[j.status] = (byStatus[j.status] ?? 0) + 1;
    }
    final ratings = List<int>.filled(5, 0);
    for (final r in reviews) {
      final i = r.rating.round().clamp(1, 5) - 1;
      ratings[i]++;
    }
    final trust = artisans.where((a) => a.trustScore > 0).map((a) => a.trustScore).toList();
    return AdminPage(
      title: 'Analytics',
      subtitle: 'Trends from the latest ${users.length} users and ${jobs.length} jobs loaded',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AdminGrid(minTileWidth: 380, children: [
          AdminPanel(title: 'New users per week', subtitle: 'Last $weeks weeks', child: AdminBars(values: _perWeek(users.map((u) => u.createdAt), now, weeks), labels: weekLabels)),
          AdminPanel(title: 'New jobs per week', subtitle: 'Last $weeks weeks', child: AdminBars(values: _perWeek(jobs.map((j) => j.createdAt), now, weeks), labels: weekLabels)),
          AdminPanel(
            title: 'Rating distribution',
            subtitle: '${reviews.length} reviews',
            child: reviews.isEmpty ? Text('No reviews yet.', style: HtType.small(p.textMuted)) : AdminBars(values: ratings, labels: const ['1★', '2★', '3★', '4★', '5★']),
          ),
          AdminPanel(
            title: 'Jobs by status',
            subtitle: 'Latest ${jobs.length} jobs',
            child: jobs.isEmpty
                ? Text('No jobs yet.', style: HtType.small(p.textMuted))
                : Column(children: [
                    for (final e in (byStatus.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                      adminFact(context, e.key.name, '${e.value}'),
                  ]),
          ),
          AdminPanel(
            title: 'Trust scores',
            subtitle: '${trust.length} scored artisans',
            child: Column(children: [
              adminFact(context, 'Average', trust.isEmpty ? '—' : (trust.reduce((a, b) => a + b) / trust.length).toStringAsFixed(0)),
              adminFact(context, '70 and above', '${trust.where((t) => t >= 70).length}'),
              adminFact(context, 'Below 40', '${trust.where((t) => t < 40).length}'),
            ]),
          ),
        ]),
      ]),
    );
  }
}
