import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/customer_booking_logic.dart';
import '../../models/job_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/quote_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../theme/ht_theme.dart';
import 'customer_shell.dart';
import 'discovery_screen.dart' show ArtisanDiscoveryCard;

/// My Bookings (references 4 dark, 19 light). Data: customerJobsProvider.
/// Every action is decided by [CustomerBookingLogic] (server state machine).
class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  BookingTab _tab = BookingTab.active;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final uid = ref.watch(authStateChangesProvider).asData?.value?.uid;
    final unread = ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
    final jobsAsync = uid == null ? const AsyncValue<List<JobModel>>.loading() : ref.watch(customerJobsProvider(uid));

    return HtBackground(
      glow: false,
      child: SafeArea(
        bottom: false,
        child: jobsAsync.when(
          loading: () => Column(children: [_header(unread), const Expanded(child: HtLoadingView())]),
          error: (e, _) => Column(children: [
            _header(unread),
            HtErrorView(message: 'Your bookings could not be loaded.', onRetry: () => ref.invalidate(customerJobsProvider(uid!))),
          ]),
          data: (jobs) {
            final groups = CustomerBookingLogic.group(jobs);
            final list = groups[_tab]!;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(unread)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 14, HtSpace.gutter, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Bookings', style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 27.5)),
                        const SizedBox(height: 4),
                        Text('Manage your service requests and appointments.', style: HtType.body(p.textSecondary)),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 6),
                    child: HtSegmentedTabs(
                      labels: const ['Active', 'Completed', 'Disputed'],
                      counts: [groups[BookingTab.active]!.length, groups[BookingTab.completed]!.length, groups[BookingTab.disputed]!.length],
                      selected: _tab.index,
                      onSelected: (i) => setState(() => _tab = BookingTab.values[i]),
                    ),
                  ),
                ),
                if (!p.isDark)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(HtSpace.gutter, 10, HtSpace.gutter, 0),
                      child: _ProtectionStrip(),
                    ),
                  ),
                if (list.isEmpty)
                  SliverToBoxAdapter(child: _emptyFor(_tab))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 16, HtSpace.gutter, 0),
                    sliver: SliverList.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 18),
                      itemBuilder: (_, i) => CustomerBookingLogic.isFunded(list[i])
                          ? FundedBookingCard(job: list[i])
                          : BookingSummaryCard(job: list[i]),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 18, HtSpace.gutter, 0),
                    child: p.isDark
                        ? const HtInfoBanner(
                            icon: Icons.lock_outline_rounded,
                            title: 'Funds safely locked',
                            text: 'Money is not transferred to the artisan until you confirm the job is complete.',
                            tone: HtTone.neutral,
                          )
                        : const _PostJobCard(),
                  ),
                ),
                if (p.isDark)
                  const SliverToBoxAdapter(
                    child: Padding(padding: EdgeInsets.fromLTRB(HtSpace.gutter, 14, HtSpace.gutter, 0), child: _PostJobCard()),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: CustomerShell.bottomInset)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(int unread) => HtAppHeader(
        subtitle: context.ht.isDark ? null : 'Bookings',
        actions: [
          HtIconCircle(icon: Icons.notifications_none_rounded, badge: unread > 0, tooltip: 'Notifications', onTap: () => context.push('/notifications')),
          HtIconCircle(
            icon: Icons.person_outline_rounded,
            fill: context.ht.headerAvatarFill,
            iconColor: context.ht.onHeaderAvatar,
            tooltip: 'Profile',
            onTap: () => ref.read(customerTabProvider.notifier).state = CustomerTab.profile,
          ),
        ],
      );

  Widget _emptyFor(BookingTab t) => switch (t) {
        BookingTab.active => HtEmptyView(
            icon: Icons.calendar_month_outlined,
            title: 'No active bookings',
            message: 'Post a job to receive quotes from verified artisans.',
            action: HtSmallPrimaryButton(label: 'Post Job', icon: Icons.add_rounded, onPressed: () => context.push('/request')),
          ),
        BookingTab.completed => const HtEmptyView(icon: Icons.task_alt_rounded, title: 'No completed bookings yet'),
        BookingTab.disputed => const HtEmptyView(icon: Icons.gavel_rounded, title: 'No disputes', message: 'Disputed bookings appear here until HandyTrust resolves them.'),
      };
}

class _ProtectionStrip extends StatelessWidget {
  const _ProtectionStrip();
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.tile)),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 20, color: p.textPrimary),
          const SizedBox(width: 12),
          Expanded(child: Text('Escrow protection: funds are safeguarded until you approve the completed job.', style: HtType.small(p.textPrimary))),
        ],
      ),
    );
  }
}

class _PostJobCard extends StatelessWidget {
  const _PostJobCard();
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return HtCard(
      color: p.accentSoft,
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: p.isDark ? p.accent : p.accentStrong, shape: BoxShape.circle),
            child: Icon(Icons.add_rounded, color: p.isDark ? p.onPrimary : Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Need another repair done?', style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('Book verified carpenters, plumbers and more', style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          HtSmallPrimaryButton(label: 'Post Job', onPressed: () => context.push('/request')),
        ],
      ),
    );
  }
}

String _bookingTitle(JobModel j) {
  final first = j.description.trim().split('\n').first.trim();
  if (first.isEmpty) return j.category;
  return first.length > 48 ? '${first.substring(0, 47)}…' : first;
}

/// Funded booking card (escrow banner + lifecycle + primary action).
class FundedBookingCard extends ConsumerWidget {
  const FundedBookingCard({super.key, required this.job});
  final JobModel job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final uid = ref.watch(authStateChangesProvider).asData?.value?.uid ?? '';
    final artisan = job.artisanId.isEmpty ? null : ref.watch(artisanProfileProvider(job.artisanId)).asData?.value;
    final action = CustomerBookingLogic.actionFor(job, uid);
    final stage = CustomerBookingLogic.lifecycleIndex(job.status);
    final amount = job.agreedAmount;

    return HtCard(
      radius: HtRadius.card,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BOOKING #${HtFormat.bookingRef(job.id)}', style: HtType.caps(p.isDark ? p.accentStrong : p.accentStrong)),
                    const SizedBox(height: 6),
                    Text(_bookingTitle(job), style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 18), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(HtFormat.naira(amount), style: HtType.amount(p.isDark ? p.accent : p.textPrimary, size: 20.5)),
                  Text('Agreed price', style: HtType.smallStrong(p.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (artisan != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.inner)),
              child: Row(
                children: [
                  HtAvatar(name: artisan.name, imageUrl: artisan.profileImageUrl, size: 50, online: !p.isDark && artisan.isAvailable),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(artisan.displayName, style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text([artisan.category ?? 'Artisan', ?HtFormat.area(artisan.serviceAddress)].join(' · '),
                            style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (ArtisanDiscoveryCard.isIdVerified(artisan)) const HtVerifiedBadge(),
                ],
              ),
            ),
          const SizedBox(height: 14),
          HtInfoBanner(
            icon: Icons.lock_outline_rounded,
            title: '${HtFormat.naira(amount)} held in escrow',
            text: 'Released to the artisan only when you approve',
            tone: HtTone.accent,
            trailing: Icon(Icons.shield_outlined, color: p.accentSoftText),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('ESCROW LIFECYCLE', style: HtType.caps(p.textSecondary)),
              const Spacer(),
              Text('Stage ${stage + 1} of 4', style: HtType.smallStrong(p.accent)),
            ],
          ),
          const SizedBox(height: 14),
          HtLifecycle(
            current: stage,
            steps: const [
              HtLifecycleStep('Funded', Icons.lock_outline_rounded),
              HtLifecycleStep('In Progress', Icons.handyman_outlined),
              HtLifecycleStep('Verified', Icons.fact_check_outlined),
              HtLifecycleStep('Released', Icons.lock_open_rounded),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              HtIconCircle(icon: Icons.chat_bubble_outline_rounded, size: 50, tooltip: 'Open chat', onTap: () => context.push('/chat/${job.id}')),
              const SizedBox(width: 12),
              Expanded(child: _primaryFor(context, ref, action)),
              if (!p.isDark) ...[
                const SizedBox(width: 10),
                HtIconCircle(icon: Icons.more_vert_rounded, size: 50, tooltip: 'Job details', onTap: () => context.push('/job/${job.id}')),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _primaryFor(BuildContext context, WidgetRef ref, CustomerBookingAction action) {
    switch (action) {
      case CustomerBookingAction.approveAndRelease:
        return _ApproveReleaseButton(job: job);
      case CustomerBookingAction.payIntoEscrow:
        return HtPrimaryButton(label: 'Pay into Escrow', icon: Icons.arrow_forward_rounded, height: 56, onPressed: () => context.push('/payment/${job.id}'));
      default:
        return HtSecondaryButton(label: 'View Details', height: 56, onPressed: () => context.push('/job/${job.id}'));
    }
  }
}

class _ApproveReleaseButton extends ConsumerStatefulWidget {
  const _ApproveReleaseButton({required this.job});
  final JobModel job;
  @override
  ConsumerState<_ApproveReleaseButton> createState() => _ApproveReleaseButtonState();
}

class _ApproveReleaseButtonState extends ConsumerState<_ApproveReleaseButton> {
  bool _busy = false;

  Future<void> _approve() async {
    final ok = await htConfirm(
      context,
      title: 'Approve and release payment?',
      message: 'Confirm the work is complete. HandyTrust will release ${HtFormat.naira(widget.job.agreedAmount)} to the artisan. This cannot be undone.',
      confirmLabel: 'Approve & Release',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await ref.read(escrowNotifierProvider.notifier).confirmComplete(widget.job.id);
    if (!mounted) return;
    setState(() => _busy = false);
    final result = ref.read(escrowNotifierProvider);
    if (result.hasError) {
      htSnack(context, 'Could not release payment: ${result.error}', error: true);
    } else {
      htSnack(context, 'Payment approved. The payout is being processed.');
    }
  }

  @override
  Widget build(BuildContext context) => HtPrimaryButton(
        label: 'Approve & Release Payment',
        icon: Icons.verified_outlined,
        height: 56,
        loading: _busy,
        onPressed: _approve,
      );
}

/// Unfunded or closed booking card (reference 4 second card / 19 bids card).
class BookingSummaryCard extends ConsumerWidget {
  const BookingSummaryCard({super.key, required this.job});
  final JobModel job;

  static const _categoryIcons = <String, IconData>{
    'Plumbing': Icons.plumbing_rounded,
    'Electrical': Icons.bolt_rounded,
    'Painting': Icons.format_paint_outlined,
    'Cleaning': Icons.cleaning_services_outlined,
    'Carpentry': Icons.carpenter_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final uid = ref.watch(authStateChangesProvider).asData?.value?.uid ?? '';
    final action = CustomerBookingLogic.actionFor(job, uid);
    final quotes = job.status == JobStatus.requested ? (ref.watch(jobQuotesProvider(job.id)).asData?.value ?? const []) : const [];
    final pending = quotes.where((q) => q.status.name == 'pending').length;
    final budget = job.agreedAmount ?? job.budgetMax ?? job.budgetMin;
    final area = job.areaLabel;

    final statusTone = switch (job.status) {
      JobStatus.completed || JobStatus.resolved => HtTone.success,
      JobStatus.cancelled || JobStatus.expired => HtTone.neutral,
      JobStatus.disputed => HtTone.danger,
      _ => HtTone.warning,
    };

    return HtCard(
      radius: 26,
      onTap: () => context.push('/job/${job.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(p.isDark ? 16 : 26)),
                child: Icon(_categoryIcons[job.category] ?? Icons.handyman_outlined, color: p.accentSoftText),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_bookingTitle(job), style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 16.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text([job.category, ?area].join(' · '), style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (budget != null) ...[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(HtFormat.naira(budget), style: HtType.cardTitle(p.textPrimary)),
                    Text(job.agreedAmount != null ? 'Agreed price' : 'Budget', style: HtType.small(p.textSecondary)),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Flexible(
                child: HtStatusPill(
                  label: job.status == JobStatus.requested && pending > 0
                      ? '$pending ${pending == 1 ? 'offer' : 'offers'} in'
                      : CustomerBookingLogic.statusLabel(job),
                  tone: statusTone,
                  icon: job.status == JobStatus.matched ? Icons.hourglass_bottom_rounded : null,
                ),
              ),
              const SizedBox(width: 10),
              const Spacer(),
              switch (action) {
                CustomerBookingAction.payIntoEscrow =>
                  HtSmallPrimaryButton(label: 'Pay', icon: Icons.arrow_forward_rounded, onPressed: () => context.push('/payment/${job.id}')),
                CustomerBookingAction.openChat =>
                  HtSecondaryButton(label: 'Open Chat', dense: true, onPressed: () => context.push('/chat/${job.id}')),
                CustomerBookingAction.reviewQuotes => HtSecondaryButton(
                    label: pending > 0 ? 'View Bids' : 'View Details', dense: true, icon: Icons.arrow_forward_rounded, onPressed: () => context.push('/job/${job.id}')),
                _ => HtSecondaryButton(label: 'View Details', dense: true, onPressed: () => context.push('/job/${job.id}')),
              },
            ],
          ),
        ],
      ),
    );
  }
}
