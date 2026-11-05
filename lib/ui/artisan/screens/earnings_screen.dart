import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/artisan_earnings_summary.dart';
import '../../../models/job_model.dart';
import '../../../providers/artisan_provider.dart';
import '../../../providers/escrow_provider.dart';
import '../../../providers/payment_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_format.dart';
import '../../components/ht_kit.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';
import 'work_ui.dart';

String _short(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).round()}k';
  return v.round().toString();
}

/// AR-05 Earnings: released payouts by month, money in escrow and awaiting
/// release, payout account, payout ledger. No balance and no withdrawals —
/// payouts go to the artisan's bank account per job.
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final ctx = ref.watch(artisanContextProvider).asData?.value;
    if (ctx == null) return const Column(children: [ArtisanTabHeader(), Expanded(child: ArtisanState.loading())]);
    final paymentsAsync = ref.watch(artisanPaymentsProvider(ctx.uid));
    final jobs = ref.watch(artisanJobsProvider(ctx.uid)).asData?.value ?? const <JobModel>[];
    final jobsById = {for (final j in jobs) j.id: j};
    final payoutReady = ref.watch(artisanPayoutReadyProvider(ctx.uid)).asData?.value;

    return paymentsAsync.when(
      loading: () => ArtisanTabBody(children: [proTitle(context, 'Earnings'), const SizedBox(height: 40), const HtLoadingView(label: 'Loading your earnings…')]),
      error: (e, _) => ArtisanTabBody(children: [proTitle(context, 'Earnings'), const SizedBox(height: 20), ArtisanState.error(e, onRetry: () => ref.invalidate(artisanPaymentsProvider(ctx.uid)))]),
      data: (payments) {
        final now = clock.now();
        final s = ArtisanEarningsSummary.of(payments, jobsById, now);
        final ledger = ArtisanEarningsSummary.ledger(payments);
        const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return ArtisanTabBody(
          onRefresh: () async => ref.invalidate(artisanPaymentsProvider(ctx.uid)),
          children: [
            proTitle(context, 'Earnings'),
            const SizedBox(height: 12),
            HtCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('RELEASED TO YOU · LAST ${s.months.length} MONTHS', style: HtType.caps(p.textMuted).copyWith(fontSize: 10.5)),
                const SizedBox(height: 4),
                Text(HtFormat.naira(s.releasedLastMonths), style: HtType.amount(p.textPrimary, size: 30)),
                const SizedBox(height: 12),
                ProMonthBars(
                  months: [for (final m in s.months) monthNames[m.month - 1]],
                  values: [for (final m in s.months) m.total],
                  labels: [for (final m in s.months) m.total == 0 ? '—' : _short(m.total)],
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: ProStat(icon: Icons.lock_outline_rounded, label: 'In escrow', value: HtFormat.naira(s.inEscrow), sub: '${s.inEscrowJobs} funded ${s.inEscrowJobs == 1 ? 'job' : 'jobs'}')),
              const SizedBox(width: 10),
              Expanded(child: ProStat(icon: Icons.hourglass_bottom_rounded, label: 'Awaiting release', value: HtFormat.naira(s.awaitingRelease), sub: 'In customer review')),
            ]),
            const SizedBox(height: 10),
            HtCard(
              radius: HtRadius.inner,
              padding: const EdgeInsets.all(14),
              onTap: () => context.push('/bank-details'),
              child: Row(children: [
                htIconTile(context, Icons.account_balance_outlined, tone: payoutReady == true ? HtTone.success : HtTone.warning, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Payout account', style: HtType.bodyStrong(p.textPrimary)),
                    Text(payoutReady == true ? 'Bank account on file' : 'Add your bank account to receive payouts', style: HtType.small(p.textSecondary)),
                  ]),
                ),
                Text(payoutReady == true ? 'Manage' : 'Add', style: HtType.smallStrong(proAccent(p))),
              ]),
            ),
            const ProSection('Payout ledger'),
            if (ledger.isEmpty)
              HtCard(child: HtEmptyView(icon: Icons.payments_outlined, title: 'No payouts yet', message: 'Payments released for your completed jobs appear here.'))
            else
              for (final pay in ledger.take(30))
                Builder(builder: (context) {
                  final job = jobsById[pay.jobId] ?? ref.watch(jobStreamProvider(pay.jobId)).asData?.value;
                  final label = ArtisanEarningsSummary.payoutLabel(job?.payoutStatus);
                  final tone = switch (job?.payoutStatus) { 'paid' => HtTone.success, 'processing' => HtTone.warning, 'delayed' || 'on_hold' => HtTone.danger, _ => HtTone.accent };
                  final at = (pay.releasedAt ?? pay.createdAt).toLocal();
                  return ProLedgerRow(
                    date: '${at.day.toString().padLeft(2, '0')} ${monthNames[at.month - 1]}',
                    title: job == null ? 'Job #${HtFormat.bookingRef(pay.jobId)}' : workTitle(job),
                    status: label,
                    tone: tone,
                    amount: HtFormat.naira(pay.amount),
                    onTap: () => context.push('/job/${pay.jobId}'),
                  );
                }),
            const SizedBox(height: 14),
            const HtInfoBanner(icon: Icons.info_outline_rounded, tone: HtTone.neutral, text: 'You receive the full agreed price for each job. The platform fee is paid by the customer.'),
          ],
        );
      },
    );
  }
}
