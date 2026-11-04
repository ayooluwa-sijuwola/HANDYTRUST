import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/artisan_eligibility.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shimmer_loaders.dart';

/// Profile tab content — no Scaffold, rendered inside MainShellScreen.
class ProfileTabContent extends ConsumerWidget {
  const ProfileTabContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.asData?.value;
    final isArtisanMode = user?.isArtisan == true && user?.activeRole == 'artisan';
    final isAdmin = ref.watch(isAdminProvider).asData?.value ?? false;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 56, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ProfileTabContent is both a bottom-nav tab (nothing to
                // pop) and reachable as the standalone /profile route
                // (something to pop). No AppBar here to get the back arrow
                // automatically the way most other screens do, so it's
                // added explicitly, matching AppBar's own canPop-based
                // default. Reference shows no title text in this header —
                // just the back arrow — so the "Profile" label is gone;
                // the centered name below the avatar already identifies
                // the screen.
                if (Navigator.canPop(context))
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded,
                        color: context.colors.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                else
                  const SizedBox(width: 48),
                // Reference shows a share/export glyph here — no share
                // feature exists anywhere in this app (checked: no
                // share_plus dependency, no Share.share call). Kept as
                // the real, working Settings entry point instead of a
                // visually-matching but non-functional icon — a
                // deliberate, disclosed exception to literal pixel
                // matching, not a silent substitution.
                IconButton(
                  icon: Icon(Icons.settings_outlined,
                      color: context.colors.textSecondary),
                  onPressed: () => context.push('/settings'),
                ),
              ],
            ),
          ),
        ),

        // Profile header card
        SliverToBoxAdapter(
          child: userAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: HomeHeaderSkeleton(),
            ),
            error: (e, st) => const SizedBox(),
            data: (profile) {
              if (profile == null) return const SizedBox();
              final isArtisan = profile.isArtisan &&
                  profile.activeRole == 'artisan';
              return isArtisan
                  ? _ArtisanProfileHeader(userId: profile.uid)
                  : _CustomerProfileHeader(
                      name: profile.name,
                      photoUrl: profile.photoUrl,
                      location: profile.location,
                    );
            },
          ),
        ),

        // Menu items — pixel-matched to the reference's structure: one
        // primary card holding every settings-style row, a separate red
        // card for Sign Out below it. Every existing functional
        // destination is kept (My Jobs/My Chats/My Reviews/Admin
        // Dashboard have no equivalent in the generic reference — removing
        // them to match a 6-row template exactly would be a real
        // navigation regression, not a visual one, so they stay,
        // restyled into the reference's single-card look rather than
        // their previous several-small-groups layout). App Mode is the
        // one reference row genuinely new to this screen — wired to the
        // real, already-working themeProvider, not a fake toggle.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              children: [
                _MenuGroup(
                  items: [
                    _MenuItem(
                      icon: Icons.work_outline_rounded,
                      label: 'My Jobs',
                      onTap: () => context.push('/jobs'),
                    ),
                    _MenuItem(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'My Chats',
                      onTap: () => context.push('/my-chats'),
                    ),
                    // Artisans have a real reviews-received view (their own
                    // public profile). No equivalent screen exists yet for
                    // a customer's "reviews I've left" — omitted rather
                    // than left pointing at the wrong screen (it previously
                    // opened Notifications, a copy-paste bug).
                    if (isArtisanMode && user?.uid != null)
                      _MenuItem(
                        icon: Icons.star_outline_rounded,
                        label: 'My Reviews',
                        onTap: () => context.push('/artisan/${user!.uid}'),
                      ),
                    _MenuItem(
                      icon: Icons.person_outline_rounded,
                      label: 'Account Information',
                      onTap: () => context.push('/settings'),
                    ),
                    // No saved-payment-method screen exists anywhere in
                    // this app (Paystack is per-transaction, no card-on-
                    // file management) — routed to Wallet as the closest
                    // real "money" destination rather than a dead link.
                    _MenuItem(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Payment Methods',
                      onTap: () => context.push('/wallet'),
                    ),
                    _MenuItem(
                      icon: Icons.shield_outlined,
                      label: 'Security & Password',
                      onTap: () => context.push('/settings'),
                    ),
                    _MenuItem(
                      icon: Icons.dark_mode_outlined,
                      label: 'App Mode',
                      onTap: () => ref.read(themeProvider.notifier).toggle(),
                      trailing: Switch(
                        value: ref.watch(themeProvider) == ThemeMode.dark,
                        onChanged: (_) =>
                            ref.read(themeProvider.notifier).toggle(),
                        activeThumbColor: context.colors.primary,
                      ),
                    ),
                    _MenuItem(
                      icon: Icons.notifications_outlined,
                      label: 'Notification Settings',
                      onTap: () => context.push('/settings'),
                      trailing: _NotificationBadge(),
                    ),
                    _MenuItem(
                      icon: Icons.help_outline_rounded,
                      label: 'Support Center',
                      onTap: () => context.push('/support'),
                    ),
                    _MenuItem(
                      icon: Icons.info_outline_rounded,
                      label: 'About HandyTrust',
                      onTap: () => context.push('/about'),
                    ),
                    // Admin entry — only rendered once isAdminProvider
                    // resolves true. Replaces the old hidden long-press-
                    // on-greeting + PIN gesture on the customer home tab
                    // (a real admin should reach admin through a
                    // discoverable, gated entry point, not an
                    // undocumented gesture).
                    if (isAdmin)
                      _MenuItem(
                        icon: Icons.admin_panel_settings_outlined,
                        label: 'Admin Dashboard',
                        onTap: () => context.push('/admin'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _MenuGroup(
                  items: [
                    _MenuItem(
                      icon: Icons.logout_rounded,
                      label: 'Logout',
                      color: context.colors.error,
                      centered: true,
                      onTap: () => _signOut(context, ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: SizedBox(
              height: MediaQuery.of(context).padding.bottom + 100),
        ),
      ],
    );
  }

  void _signOut(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        ref.read(authNotifierProvider.notifier).signOut();
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Customer Profile Header
// ---------------------------------------------------------------------------

/// Centered avatar/name/location — pixel-matched to the reference's
/// Profile screenshot (large circular photo, bold centered name, gray
/// centered location line below, no email/role text shown there).
class _CustomerProfileHeader extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final String? location;

  const _CustomerProfileHeader({
    required this.name,
    this.photoUrl,
    this.location,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: context.colors.primarySurface,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
            child: photoUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: context.colors.primary,
                      fontFamily: 'Inter',
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          if (location != null && location!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              location!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Artisan Profile Header
// ---------------------------------------------------------------------------

class _ArtisanProfileHeader extends ConsumerWidget {
  final String userId;

  const _ArtisanProfileHeader({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artisanAsync = ref.watch(artisanProfileProvider(userId));
    return artisanAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: AppShimmer(child: HomeHeaderSkeleton()),
      ),
      error: (e, st) => const SizedBox(),
      data: (artisan) {
        if (artisan == null) return const SizedBox();
        final verified = ArtisanEligibility.isReallyVerified(artisan);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: context.colors.primarySurface,
                    backgroundImage: artisan.profileImageUrl != null
                        ? NetworkImage(artisan.profileImageUrl!)
                        : null,
                    child: artisan.profileImageUrl == null
                        ? Text(
                            artisan.name.isNotEmpty
                                ? artisan.name[0].toUpperCase()
                                : 'A',
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              color: context.colors.primary,
                              fontFamily: 'Inter',
                            ),
                          )
                        : null,
                  ),
                  if (verified)
                    Positioned(
                      right: 0,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: context.colors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: context.colors.background, width: 2),
                        ),
                        child: const Icon(Icons.check_rounded,
                            size: 16, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                artisan.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              if (artisan.location != null && artisan.location!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  artisan.location!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Menu components
// ---------------------------------------------------------------------------

class _MenuGroup extends StatelessWidget {
  final List<_MenuItem> items;

  const _MenuGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              item,
              if (i < items.length - 1)
                Divider(
                  height: 1,
                  indent: 20,
                  endIndent: 0,
                  color: context.colors.border,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Widget? trailing;
  final bool centered;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.trailing,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    // Plain icon, no colored circle background — pixel-matched to the
    // reference's list rows (simple line icon directly on the card
    // surface), a deliberate departure from this app's usual
    // colored-icon-chip convention used elsewhere, scoped to this screen
    // only per the reference.
    final fg = color ?? context.colors.textPrimary;
    if (centered) {
      // Logout row — reference shows this centered (icon + label
      // together, no chevron), not left-aligned like every other row.
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      minLeadingWidth: 28,
      leading: Icon(icon, color: fg, size: 22),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: fg,
          fontFamily: 'Inter',
        ),
      ),
      trailing: trailing ??
          Icon(Icons.chevron_right_rounded,
              color: context.colors.textTertiary, size: 20),
    );
  }
}

class _NotificationBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
    if (unread == 0) {
      return Icon(Icons.chevron_right_rounded,
          color: context.colors.textTertiary, size: 20);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.error,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        unread > 9 ? '9+' : '$unread',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}
