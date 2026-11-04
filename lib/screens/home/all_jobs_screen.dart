import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/workflow_gate_service.dart';
import '../../models/job_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/job_booking_card.dart';
import '../../widgets/pill_tab_selector.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/web_content_wrapper.dart';

class AllJobsScreen extends ConsumerStatefulWidget {
  const AllJobsScreen({super.key});

  @override
  ConsumerState<AllJobsScreen> createState() => _AllJobsScreenState();
}

class _AllJobsScreenState extends ConsumerState<AllJobsScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (user) {
            if (user == null) return const SizedBox.shrink();
            final isArtisan = user.isArtisan && !user.isCustomer;
            final jobsAsync = isArtisan
                ? ref.watch(artisanJobsProvider(user.uid))
                : ref.watch(customerJobsProvider(user.uid));

            return jobsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('$e', style: TextStyle(color: context.colors.error))),
              data: (jobs) {
                final active = jobs
                    .where((j) => !j.status.isTerminal && j.status != JobStatus.disputed)
                    .toList();
                final completed =
                    jobs.where((j) => j.status == JobStatus.completed).toList();
                // 'draft' isn't a real JobStatus — every job posted through
                // service_request_screen.dart goes live immediately, there's
                // no partial-save flow. The tab stays honest about that
                // rather than pretending it works (see empty state below).
                const drafts = <JobModel>[];
                final disputed = jobs
                    .where((j) => j.status == JobStatus.disputed || j.status == JobStatus.resolved)
                    .toList();

                final tabs = [active, completed, drafts, disputed];
                final filtered = tabs[_tabIndex];

                return Stack(
                  children: [
                    Column(
                      children: [
                        _Header(userAsync: userAsync),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                          child: PillTabSelector(
                            tabs: [
                              PillTabItem('Active', count: active.length),
                              PillTabItem('Completed', count: completed.length),
                              PillTabItem('Drafts', count: drafts.length),
                              PillTabItem('Disputed', count: disputed.length),
                            ],
                            selectedIndex: _tabIndex,
                            onChanged: (i) => setState(() => _tabIndex = i),
                          ),
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? _EmptyState(tabIndex: _tabIndex, isArtisan: isArtisan)
                              : WebContentWrapper(
                                  child: _BookingsList(
                                    jobs: filtered,
                                    isArtisan: isArtisan,
                                    showPromo: _tabIndex == 0 && !isArtisan,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    if (!isArtisan)
                      Positioned(
                        right: 20,
                        bottom: 20,
                        child: FloatingActionButton(
                          backgroundColor: context.colors.ink,
                          foregroundColor: context.colors.onInk,
                          onPressed: () => context.push('/request'),
                          child: const Icon(Icons.add_rounded),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Card grid on desktop ("table/card hybrid" — a 2-column grid reads as a
/// data grid rather than a phone-width list stretched edge-to-edge),
/// unchanged single-column ListView below the tablet breakpoint. JobBookingCard
/// has no fixed height (content-dependent), so this uses Wrap with a
/// LayoutBuilder-computed column width rather than GridView's fixed
/// childAspectRatio, which would either clip taller cards or leave gaps.
class _BookingsList extends StatelessWidget {
  final List<JobModel> jobs;
  final bool isArtisan;
  final bool showPromo;

  const _BookingsList({required this.jobs, required this.isArtisan, required this.showPromo});

  @override
  Widget build(BuildContext context) {
    if (!context.isDesktop) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: [
          for (final j in jobs) ...[
            _BookingCardTile(job: j, isArtisan: isArtisan),
            const SizedBox(height: 12),
          ],
          if (showPromo) ...[
            const SizedBox(height: 8),
            const _NeedAHandCard(),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final columnWidth = (constraints.maxWidth - spacing) / 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final j in jobs)
                SizedBox(
                  width: columnWidth,
                  child: _BookingCardTile(job: j, isArtisan: isArtisan),
                ),
              if (showPromo) SizedBox(width: columnWidth, child: const _NeedAHandCard()),
            ],
          ),
        );
      },
    );
  }
}

/// Header: hamburger + "My Bookings"/"Manage your service requests and
/// appointments." + chat icon + avatar — pixel-matched to Stitch. This app
/// has no side-drawer navigation surface, so the hamburger icon (a real
/// element in the reference with no obvious existing destination) opens
/// Settings — the closest existing "more" hub — documented here rather
/// than silently invented as a fake drawer.
class _Header extends ConsumerWidget {
  final AsyncValue userAsync;
  const _Header({required this.userAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // AllJobsScreen is both a bottom-nav tab (My Bookings/My Jobs —
    // nothing to pop) and reachable as the standalone /jobs route (pushed
    // from Profile's "My Jobs" row — something to pop). The hamburger icon
    // is a real, pixel-matched shortcut to Settings, not a nav-stack
    // control, so a back button is added alongside it rather than
    // replacing it — same canPop-conditional approach as WalletScreen.
    final canPop = Navigator.canPop(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (canPop) ...[
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  icon: Icon(Icons.arrow_back_rounded,
                      color: context.colors.textPrimary, size: 24),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
              ],
              GestureDetector(
                onTap: () => context.push('/settings'),
                child: Icon(Icons.menu_rounded, color: context.colors.textPrimary, size: 26),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/my-chats'),
                child: Icon(Icons.chat_bubble_outline_rounded,
                    color: context.colors.textSecondary, size: 24),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () => context.push('/settings'),
                child: userAsync.maybeWhen(
                  data: (u) => UserAvatar(
                    photoUrl: u?.photoUrl,
                    displayName: u?.displayUsername ?? '',
                    size: 36,
                  ),
                  orElse: () => const SizedBox(width: 36, height: 36),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'My Bookings',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter',
              color: context.colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage your service requests and appointments.',
            style: TextStyle(
              fontSize: 13.5,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

/// "Need a Hand?" promo card — pixel-matched to Stitch, appears below the
/// Active bookings list only.
class _NeedAHandCard extends StatelessWidget {
  const _NeedAHandCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need a Hand?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Book a verified pro for your next home improvement project.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => context.push('/browse-artisans'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Explore Services',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.colors.primary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14, color: context.colors.primary),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Text('👷', style: TextStyle(fontSize: 48)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final int tabIndex;
  final bool isArtisan;

  const _EmptyState({required this.tabIndex, required this.isArtisan});

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = switch (tabIndex) {
      0 => (
          Icons.inbox_outlined,
          'No active jobs',
          isArtisan ? null : 'Post a job to get matched with artisans.',
        ),
      1 => (Icons.check_circle_outline_rounded, 'No completed jobs', null),
      2 => (
          Icons.drafts_outlined,
          'Drafts aren\'t supported yet',
          'Every job you post goes live immediately — there\'s no partial-save step to come back to.',
        ),
      // Deliberately reassuring — unlike every other empty state here,
      // "empty" is the good outcome for this one.
      _ => (Icons.check_circle_outline_rounded, "No disputes — that's a good thing", null),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: context.colors.textTertiary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
            if (tabIndex == 0 && !isArtisan) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.push('/request'),
                child: const Text('Post a Job'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Resolves counterparty info and the workflow phase for one job, then
/// renders it through JobBookingCard. All phase/action decisions come from
/// WorkflowGateService — this widget never inspects job.status,
/// agreementStatus, or payment fields itself, only step.phase/
/// step.primaryAction. Execution (navigation, provider calls) mirrors
/// job_detail_screen.dart's _executeAction for the same WorkflowAction
/// values — the decision lives in one place, but each screen still owns
/// how it carries the action out.
class _BookingCardTile extends ConsumerWidget {
  final JobModel job;
  final bool isArtisan;

  const _BookingCardTile({required this.job, required this.isArtisan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = WorkflowGateService.describeStep(job, viewerIsCustomer: !isArtisan);
    final needsAction = step.primaryAction != WorkflowAction.none;
    final tone = needsAction
        ? JobBookingTone.attention
        : (job.status.isActive ? JobBookingTone.positive : JobBookingTone.neutral);

    final isSearching = !isArtisan && job.status == JobStatus.requested && job.artisanId.isEmpty;

    String? counterpartyName;
    String? counterpartyAvatarUrl;
    var counterpartyVerified = false;

    if (!isSearching && !isArtisan && job.artisanId.isNotEmpty) {
      final artisan = ref.watch(artisanProfileProvider(job.artisanId)).asData?.value;
      counterpartyName = artisan?.displayName;
      counterpartyAvatarUrl = artisan?.profileImageUrl;
      counterpartyVerified = artisan?.isVerified ?? false;
    } else if (!isSearching && isArtisan) {
      // No customer-by-id provider exists in this app yet — showing a
      // generic role label rather than fabricating a name/avatar this
      // screen has no real data source for.
      counterpartyName = 'Customer';
    }

    final price = job.agreedAmount ?? job.budgetMin;

    // Matched job: "Message" (secondary) + "View Details" (primary, dark
    // navy). Unmatched/searching job: single full-width "Edit Booking" —
    // pixel-matched to Stitch's two card variants exactly.
    final hasCounterparty = !isSearching;

    return JobBookingCard(
      title: job.category,
      dateLabel: _formatDate(job.createdAt),
      phase: step.phase,
      tone: tone,
      phaseIcon: tone == JobBookingTone.attention
          ? Icons.hourglass_empty_rounded
          : Icons.schedule_rounded,
      isSearching: isSearching,
      counterpartyName: counterpartyName,
      counterpartyAvatarUrl: counterpartyAvatarUrl,
      counterpartyVerified: counterpartyVerified,
      priceLabel: job.agreedAmount != null ? 'Agreed Price' : 'Budget',
      priceValue: price != null ? '₦${price.toStringAsFixed(0)}' : '—',
      secondaryLabel: hasCounterparty ? 'Message' : null,
      onSecondary: hasCounterparty
          ? () async {
              await ref.read(escrowNotifierProvider.notifier).openChat(job.id);
              if (context.mounted) {
                context.push('/chat/${job.id}', extra: {'artisanId': job.artisanId});
              }
            }
          : null,
      // "View Details"/"Edit Booking" both just open Job Detail — Stitch's
      // card only ever shows a generic navigation label here, never a
      // specific verb like "Pay Now" — the actual next-action buttons
      // (via WorkflowGateService) live on Job Detail itself, one tap away,
      // not duplicated onto this card.
      primaryLabel: hasCounterparty ? 'View Details' : 'Edit Booking',
      primaryDark: hasCounterparty,
      onPrimary: () => context.push('/job/${job.id}'),
      onTap: () => context.push('/job/${job.id}'),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}
