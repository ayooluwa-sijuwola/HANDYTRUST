import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/customer_booking_logic.dart';
import '../../core/services/payment_summary.dart';
import '../../models/job_model.dart';
import '../../models/payment_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/payment_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../theme/ht_theme.dart';
import 'customer_shell.dart';

/// Customer "Wallet" tab (references 5 dark, 21/25 light), adapted to the
/// real backend: HandyTrust has NO stored-value wallet, so there is no
/// balance, Add Money or Withdraw. The reference's structure shows what the
/// customer genuinely has — money held in escrow for their jobs, active
/// escrow contracts and their payment history (customerPaymentsProvider).
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final uid = ref.watch(authStateChangesProvider).asData?.value?.uid;
    final unread = ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
    if (uid == null) return const HtBackground(child: HtLoadingView());
    final paymentsAsync = ref.watch(customerPaymentsProvider(uid));
    final jobs = ref.watch(customerJobsProvider(uid)).asData?.value ?? const <JobModel>[];
    final jobsById = {for (final j in jobs) j.id: j};

    return HtBackground(
      glow: false,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: HtAppHeader(
                title: p.isDark ? 'HandyTrust' : 'Payments',
                actions: [
                  HtIconCircle(icon: Icons.notifications_none_rounded, badge: unread > 0, tooltip: 'Notifications', onTap: () => context.push('/notifications')),
                  HtIconCircle(
                    icon: Icons.person_outline_rounded,
                    fill: p.headerAvatarFill,
                    iconColor: p.onHeaderAvatar,
                    tooltip: 'Profile',
                    onTap: () => ref.read(customerTabProvider.notifier).state = CustomerTab.profile,
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 12, HtSpace.gutter, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!p.isDark) Text('HANDYTRUST ESCROW', style: HtType.caps(p.accentStrong)),
                    Text(p.isDark ? 'Escrow Payments' : 'Payments', style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 27.5)),
                    if (p.isDark) Text('Your job payments and escrow status', style: HtType.body(p.textSecondary)),
                  ],
                ),
              ),
            ),
            ...paymentsAsync.when(
              loading: () => [const SliverToBoxAdapter(child: HtLoadingView())],
              error: (e, _) => [
                SliverToBoxAdapter(
                  child: HtErrorView(message: 'Your payments could not be loaded.', onRetry: () => ref.invalidate(customerPaymentsProvider(uid))),
                ),
              ],
              data: (payments) {
                final summary = PaymentSummary.of(payments);
                final funded = jobs.where(CustomerBookingLogic.isFunded).toList();
                final shown = _showAll ? payments : payments.take(3).toList();
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 18, HtSpace.gutter, 0),
                      child: _EscrowSummaryCard(summary: summary),
                    ),
                  ),
                  if (funded.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 28, HtSpace.gutter, 14),
                        child: HtSectionHeader(
                          title: 'Active Escrow Contracts',
                          trailing: 'Bookings',
                          onTrailing: () => ref.read(customerTabProvider.notifier).state = CustomerTab.bookings,
                        ),
                      ),
                    ),
                    SliverList.separated(
                      itemCount: funded.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: HtSpace.gutter),
                        child: _EscrowContractCard(job: funded[i]),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 28, HtSpace.gutter, 14),
                      child: HtSectionHeader(
                        title: 'Recent Transactions',
                        badge: p.isDark ? null : '${payments.length}',
                        trailing: payments.length > 3 ? (_showAll ? 'Show less' : 'See All') : null,
                        onTrailing: payments.length > 3 ? () => setState(() => _showAll = !_showAll) : null,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: HtSpace.gutter),
                      child: payments.isEmpty
                          ? const HtCard(child: HtEmptyView(icon: Icons.receipt_long_outlined, title: 'No payments yet', message: 'Payments you make into escrow for your jobs appear here.'))
                          : HtCard(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                children: [
                                  for (var i = 0; i < shown.length; i++) ...[
                                    if (i > 0) Divider(height: 1, color: p.border, indent: 18, endIndent: 18),
                                    _TransactionRow(payment: shown[i], job: jobsById[shown[i].jobId]),
                                  ],
                                ],
                              ),
                            ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(HtSpace.gutter, 22, HtSpace.gutter, 0),
                      child: HtInfoBanner(
                        icon: Icons.verified_user_outlined,
                        title: 'Escrow protection',
                        text: 'Your payment stays in escrow and is released to the artisan when you approve the job — or automatically 14 days after the artisan submits it, unless you raise a dispute.',
                      ),
                    ),
                  ),
                ];
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: CustomerShell.bottomInset)),
          ],
        ),
      ),
    );
  }
}

class _EscrowSummaryCard extends StatelessWidget {
  const _EscrowSummaryCard({required this.summary});
  final PaymentSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final (whole, kobo) = HtFormat.nairaSplit(summary.heldInEscrow);
    return HtCard(
      radius: 30,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(p.isDark ? 'HELD IN ESCROW' : 'Held in escrow', style: p.isDark ? HtType.caps(p.textSecondary).copyWith(fontSize: 11) : HtType.body(p.textSecondary)),
              const Spacer(),
              HtStatusPill(label: '${summary.heldCount} active', tone: HtTone.success, dot: true),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: whole),
              TextSpan(text: kobo, style: HtType.cardTitle(p.textSecondary)),
            ]),
            style: HtType.amount(p.textPrimary, size: 36),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              HtStatusPill(label: '${HtFormat.naira(summary.released)} released', tone: HtTone.accent, icon: Icons.lock_open_rounded),
              if (summary.refunded > 0) HtStatusPill(label: '${HtFormat.naira(summary.refunded)} refunded', tone: HtTone.warning, icon: Icons.undo_rounded),
            ],
          ),
          const SizedBox(height: 12),
          Text('Escrow funds belong to your jobs and are not withdrawable.', style: HtType.small(p.textMuted)),
        ],
      ),
    );
  }
}

class _EscrowContractCard extends ConsumerWidget {
  const _EscrowContractCard({required this.job});
  final JobModel job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final artisan = job.artisanId.isEmpty ? null : ref.watch(artisanProfileProvider(job.artisanId)).asData?.value;
    final stage = CustomerBookingLogic.lifecycleIndex(job.status);
    final title = job.description.trim().split('\n').first;
    return HtCard(
      radius: 24,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: p.warningSoft, borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.lock_outline_rounded, color: p.warning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.isEmpty ? job.category : title, style: HtType.cardTitle(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${artisan == null ? job.category : '${job.category}: ${artisan.displayName}'} • #${HtFormat.bookingRef(job.id)}',
                        style: HtType.small(p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              HtStatusPill(label: CustomerBookingLogic.statusLabel(job), tone: HtTone.warning, dot: true),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.tile)),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('Stage ${stage + 1} of 4', style: HtType.smallStrong(p.textPrimary)),
                    const Spacer(),
                    Text('${HtFormat.naira(job.agreedAmount)} in escrow', style: HtType.smallStrong(p.warning)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: i < stage ? p.accentStrong : (i == stage ? p.warning : p.border),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  job.status == JobStatus.submitted && job.autoReleaseAt != null
                      ? 'Auto-release on ${HtFormat.date(job.autoReleaseAt!)} unless you dispute'
                      : 'Released when you approve the completed job',
                  style: HtType.small(p.textSecondary),
                ),
              ),
              const SizedBox(width: 10),
              HtSecondaryButton(label: 'Inspect Job', dense: true, icon: Icons.chevron_right_rounded, onPressed: () => context.push('/job/${job.id}')),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.payment, required this.job});
  final PaymentModel payment;
  final JobModel? job;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final s = payment.status;
    final (icon, tone) = switch (s) {
      PaymentStatus.escrowHeld || PaymentStatus.releasing || PaymentStatus.settling => (Icons.lock_outline_rounded, p.warning),
      PaymentStatus.released || PaymentStatus.settled => (Icons.check_circle_outline_rounded, p.accentStrong),
      PaymentStatus.refunded || PaymentStatus.refundPending || PaymentStatus.requiresRefund => (Icons.undo_rounded, p.success),
      PaymentStatus.failed || PaymentStatus.abandoned || PaymentStatus.chargedBack => (Icons.close_rounded, p.danger),
      _ => (Icons.schedule_rounded, p.textSecondary),
    };
    final verb = switch (s) {
      PaymentStatus.released || PaymentStatus.settled => 'Payment released',
      PaymentStatus.refunded || PaymentStatus.refundPending || PaymentStatus.requiresRefund => 'Refund',
      PaymentStatus.failed || PaymentStatus.abandoned => 'Payment not completed',
      PaymentStatus.chargedBack => 'Charged back',
      _ => 'Escrow funded',
    };
    final what = job == null ? '' : ': ${job!.description.trim().split('\n').first}';
    return InkWell(
      onTap: job == null ? null : () => context.push('/job/${payment.jobId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: tone.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(icon, color: tone, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$verb$what', style: HtType.bodyStrong(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${HtFormat.dateTime(payment.paidAt ?? payment.createdAt)} · #${HtFormat.bookingRef(payment.jobId)}',
                      style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(HtFormat.naira(PaymentSummary.charged(payment)), style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 14.5)),
                Text(PaymentSummary.statusLabel(s), style: HtType.caps(tone).copyWith(fontSize: 9)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
