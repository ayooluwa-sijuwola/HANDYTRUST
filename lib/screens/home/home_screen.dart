import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/workflow_gate_service.dart';
import '../../models/job_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/artisan_card.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/premium_scaffold.dart';
import '../../widgets/shimmer_loaders.dart';
import '../../widgets/user_avatar.dart';
import '../artisan/artisan_dashboard_screen.dart';
import '../profile/profile_screen.dart';
import '../home/all_jobs_screen.dart';
import '../wallet/wallet_screen.dart';
import '../chat/my_chats_screen.dart';

const _categories = [
  ('Plumbing', Icons.water_drop_outlined, '120+ Jobs'),
  ('Electrical', Icons.bolt_outlined, '95+ Jobs'),
  ('Cleaning', Icons.cleaning_services_outlined, '80+ Jobs'),
  ('Carpentry', Icons.handyman_outlined, '65+ Jobs'),
  ('Painting', Icons.format_paint_outlined, '50+ Jobs'),
  ('Welding', Icons.construction_outlined, '40+ Jobs'),
  ('Tiling', Icons.grid_on_outlined, '35+ Jobs'),
  ('Generator', Icons.electrical_services_outlined, '28+ Jobs'),
];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.asData?.value;

    // Tab sets pixel-matched to Stitch (design/STITCH_IMPLEMENTATION_AUDIT.md)
    // — customer and artisan modes now have DIFFERENT bottom-nav label
    // sets, not the same 4 tabs with different content. Artisan mode drops
    // Wallet from the bar entirely in favor of Inbox (chat list) — Stitch's
    // own "Find Jobs" nav has no Wallet tab; it's still reachable via
    // Profile/a pushed route, just not a bottom-nav item for artisans.
    if (user != null && user.isArtisan && user.activeRole == 'artisan') {
      return MainShellScreen(
        initialTab: _currentTab,
        onTabChange: (i) => setState(() => _currentTab = i),
        items: const [
          NavBarItem(icon: Icons.search_rounded, label: 'Find Jobs'),
          NavBarItem(icon: Icons.checklist_rounded, label: 'My Jobs'),
          NavBarItem(icon: Icons.chat_bubble_outline_rounded, label: 'Inbox'),
          NavBarItem(icon: Icons.person_rounded, label: 'Profile'),
        ],
        tabs: const [
          ArtisanHomeTabContent(),
          AllJobsScreen(),
          MyChatsScreen(),
          ProfileTabContent(),
        ],
      );
    }

    return MainShellScreen(
      initialTab: _currentTab,
      onTabChange: (i) => setState(() => _currentTab = i),
      items: const [
        NavBarItem(icon: Icons.search_rounded, label: 'Discovery'),
        NavBarItem(icon: Icons.event_available_rounded, label: 'Bookings'),
        NavBarItem(icon: Icons.account_balance_wallet_rounded, label: 'Wallet'),
        NavBarItem(icon: Icons.person_rounded, label: 'Profile'),
      ],
      tabs: const [
        _CustomerHomeTab(),
        AllJobsScreen(),
        WalletScreen(),
        ProfileTabContent(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Customer Home Tab
// ---------------------------------------------------------------------------

class _CustomerHomeTab extends ConsumerStatefulWidget {
  const _CustomerHomeTab();

  @override
  ConsumerState<_CustomerHomeTab> createState() => _CustomerHomeTabState();
}

class _CustomerHomeTabState extends ConsumerState<_CustomerHomeTab> {
  String _selectedCategory = 'Electrician';

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    final mainColumn = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(userAsync)),
        SliverToBoxAdapter(child: _buildHeadline()),
        SliverToBoxAdapter(child: _buildSearchBar()),
        SliverToBoxAdapter(child: _buildCategoryChips()),
        SliverToBoxAdapter(child: _buildFeaturedExperts()),
        SliverToBoxAdapter(
            child: SizedBox(
                height: MediaQuery.of(context).padding.bottom + 24)),
      ],
    );

    if (!context.isDesktop) return mainColumn;

    // Desktop-only third column: active-booking summary + quick actions.
    // No Stitch reference covers this (mobile Stitch is the visual
    // foundation only, no web reference exists) — real Firestore data via
    // customerJobsProvider, not fabricated content, matching this screen's
    // existing tokens/card language rather than inventing new ones.
    final user = userAsync.asData?.value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: mainColumn),
        SizedBox(
          width: 300,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 20, 20),
            child: user == null
                ? const SizedBox()
                : _DesktopRightRail(customerId: user.uid),
          ),
        ),
      ],
    );
  }

  // Header: avatar + "HandyTrust" wordmark + bell — pixel-matched to
  // Stitch's "Find your expert helper" variant (design/
  // STITCH_IMPLEMENTATION_AUDIT.md variant A, the confirmed canonical
  // choice — superseding the earlier "Find trusted experts" variant B this
  // screen was built against). The previous personalized greeting/
  // location-chip header is gone — Stitch's reference shows none of that
  // on this screen.
  Widget _buildHeader(AsyncValue userAsync) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        children: [
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
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'HandyTrust',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'Inter',
                color: context.colors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const NotificationBell(),
          // Dual-role switching has no Stitch equivalent — kept as a
          // small, secondary affordance rather than dropped outright,
          // since it's real functionality this screen was the only
          // reachable place for.
          userAsync.maybeWhen(
            data: (u) => (u != null && u.isArtisan)
                ? Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: GestureDetector(
                      onTap: () => ref
                          .read(authServiceProvider)
                          .updateUserProfile(u.uid, {'activeRole': 'artisan'}),
                      child: Icon(Icons.swap_horiz_rounded,
                          size: 20, color: context.colors.textTertiary),
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadline() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Text(
        'Find your expert helper.',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          fontFamily: 'Inter',
          height: 1.15,
          color: context.colors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  // Dark, high-contrast search field — variant A's treatment (vs. the
  // previous light-gray bar). Uses context.colors.ink so it stays a
  // deliberate "dark surface" in both light and dark app themes, matching
  // the fixed-tone Stitch "commitment" surfaces used elsewhere (CommitButton,
  // TrustScoreCard) rather than following the ambient light/dark palette.
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: _SearchBar(
        hintText: 'What do you need help with?',
        dark: true,
        onSearch: (query) {
          if (query.isNotEmpty) context.push('/request?category=$query');
        },
      ),
    );
  }

  // Category chips — horizontal scroll, black active pill with icon+label,
  // white/outlined inactive pills. Matches Stitch's Electrician/Plumber/
  // Carpenter row exactly; reuses the app's existing category list beyond
  // the three shown in the reference image (scrolls further).
  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final (name, icon, _) = _categories[i];
          final selected = _selectedCategory == name;
          // Dark mode can't reuse the light-mode literal black/white pair:
          // Colors.black on the dark page background is a near-zero-
          // contrast fill (both read as "near black"), and a pure white
          // unselected pill breaks the dark surface hierarchy entirely.
          // Light mode keeps its exact original literals untouched below.
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final selectedFill = isDark ? context.colors.ink : Colors.black;
          final unselectedFill = isDark ? context.colors.surface : Colors.white;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = name),
            child: AnimatedContainer(
              duration: AppAnimations.fast,
              curve: AppAnimations.defaultCurve,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? selectedFill : unselectedFill,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: selected ? selectedFill : context.colors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: selected ? Colors.white : context.colors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                      color: selected ? Colors.white : context.colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeaturedExperts() {
    final featuredAsync = ref.watch(featuredArtisansProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Featured Pros',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                  color: context.colors.textPrimary,
                ),
              ),
              GestureDetector(
                onTap: () => context.push('/browse-artisans'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See all',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Inter',
                        color: context.colors.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: context.colors.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          featuredAsync.when(
            loading: () => const JobListSkeleton(count: 2),
            error: (e, st) => const SizedBox(),
            data: (artisans) {
              if (artisans.isEmpty) {
                return _EmptyFeaturedCard(onBrowse: () => context.push('/browse-artisans'));
              }
              return Column(
                children: artisans.take(6).map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ArtisanCard(
                    artisan: a,
                    onTap: () => context.push('/artisan/${a.uid}'),
                  ),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Desktop-only right rail: real active-booking summary + quick actions.
/// WorkflowGateService.describeStep is the same decision source every
/// other screen in this app uses for job phase/status — this rail reads
/// it, not job.status directly, so it can't drift from job_detail_screen.
/// dart's own account of "what phase is this job in."
class _DesktopRightRail extends ConsumerWidget {
  final String customerId;

  const _DesktopRightRail({required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(customerJobsProvider(customerId));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active Bookings',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          jobsAsync.when(
            loading: () => const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, st) => const SizedBox(),
            data: (jobs) {
              final active = jobs.where((j) => !j.status.isTerminal).toList();
              if (active.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Text(
                    'No active bookings',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                );
              }
              return Column(
                children: active.take(3).map((j) => _ActiveBookingMiniCard(job: j)).toList(),
              );
            },
          ),
          const SizedBox(height: 28),
          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _QuickActionRow(
            icon: Icons.add_circle_outline_rounded,
            label: 'Post a Job',
            onTap: () => context.push('/request'),
          ),
          _QuickActionRow(
            icon: Icons.people_outline_rounded,
            label: 'Browse Artisans',
            onTap: () => context.push('/browse-artisans'),
          ),
          _QuickActionRow(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'My Chats',
            onTap: () => context.push('/my-chats'),
          ),
          _QuickActionRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Wallet',
            onTap: () => context.push('/wallet'),
          ),
        ],
      ),
    );
  }
}

class _ActiveBookingMiniCard extends StatelessWidget {
  final JobModel job;

  const _ActiveBookingMiniCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final step = WorkflowGateService.describeStep(job, viewerIsCustomer: true);
    return GestureDetector(
      onTap: () => context.push('/job/${job.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              job.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              step.phase,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
                color: context.colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 12, color: context.colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFeaturedCard extends StatelessWidget {
  final VoidCallback onBrowse;

  const _EmptyFeaturedCard({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline_rounded, size: 40, color: context.colors.textTertiary),
          const SizedBox(height: 10),
          Text(
            'No verified experts yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onBrowse, child: const Text('Browse Artisans')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search Bar
// ---------------------------------------------------------------------------

class _SearchBar extends StatefulWidget {
  final ValueChanged<String> onSearch;
  final String hintText;
  // Forces the Stitch variant-A "always dark" commitment-surface search bar
  // (context.colors.ink, fixed regardless of app theme) instead of the
  // default behavior of merely following the ambient light/dark theme.
  final bool dark;

  const _SearchBar({
    required this.onSearch,
    this.hintText = 'Search services, jobs...',
    this.dark = false,
  });

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = widget.dark
        ? context.colors.ink
        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9));
    final border = widget.dark
        ? context.colors.ink
        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));
    final iconColor = widget.dark ? context.colors.onInk.withValues(alpha: 0.6) : context.colors.textTertiary;
    final textColor = widget.dark ? context.colors.onInk : context.colors.textPrimary;
    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: border),
      ),
      child: TextField(
        controller: _ctrl,
        onSubmitted: widget.onSearch,
        textInputAction: TextInputAction.search,
        style: TextStyle(color: textColor, fontFamily: 'Inter'),
        cursorColor: textColor,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: widget.dark ? TextStyle(color: iconColor) : null,
          prefixIcon: Icon(Icons.search_rounded, color: iconColor, size: 20),
          suffixIcon: _ctrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded, color: iconColor, size: 18),
                  onPressed: () {
                    _ctrl.clear();
                    setState(() {});
                  },
                )
              : null,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              vertical: 14, horizontal: 0),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

