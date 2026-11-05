import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/user_model.dart';
import '../../providers/chat_provider.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/theme_provider.dart';
import '../components/ht_components.dart';
import '../theme/ht_theme.dart';
import 'customer_shell.dart';
import 'discovery_screen.dart' show ArtisanDiscoveryCard;

/// Profile (references 6 dark, 22 light) — used for both customer and
/// artisan mode. Only real data and real destinations: unsupported
/// reference items (BVN/biometrics badges, trust tiers, escrow caps, QR,
/// customer trust score, 2FA) are omitted (design/STAGE8_SCREEN_INVENTORY.md).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.standalone = false});

  /// True when pushed as /profile (shows a back button) rather than a tab.
  final bool standalone;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploading = false;
  bool _switching = false;

  Future<void> _changePhoto(UserModel user) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048);
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      // ProfileService strips photo metadata (Stage 7.1) before upload.
      await ref.read(profileServiceProvider).uploadAvatar(user.uid, bytes);
      if (mounted) htSnack(context, 'Profile photo updated');
    } catch (e) {
      if (mounted) htSnack(context, 'Could not update your photo: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _switchRole(UserModel user, bool toArtisan) async {
    setState(() => _switching = true);
    try {
      await ref.read(profileServiceProvider).setActiveRole(user.uid, toArtisan ? 'artisan' : 'customer');
    } catch (e) {
      if (mounted) htSnack(context, 'Could not switch mode: $e', error: true);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await htConfirm(context, title: 'Log out of HandyTrust?', message: 'You can sign back in at any time.', confirmLabel: 'Log Out');
    if (!ok || !mounted) return;
    await ref.read(authNotifierProvider.notifier).signOut();
  }

  void _openJobs(UserModel user) {
    final artisanMode = user.isArtisan && user.activeRole == 'artisan';
    if (!widget.standalone && !artisanMode) {
      ref.read(customerTabProvider.notifier).state = CustomerTab.bookings;
    } else {
      context.push('/jobs');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final userAsync = ref.watch(currentUserProvider);
    final isAdmin = ref.watch(isAdminProvider).asData?.value ?? false;
    final themeMode = ref.watch(themeProvider);

    return HtBackground(
      deep: p.isDark,
      child: SafeArea(
        bottom: false,
        child: userAsync.when(
          loading: () => const HtLoadingView(),
          error: (e, _) => HtErrorView(message: 'Your profile could not be loaded.', onRetry: () => ref.invalidate(currentUserProfileProvider)),
          data: (user) {
            if (user == null) return const HtLoadingView();
            final artisanMode = user.isArtisan && user.activeRole == 'artisan';
            final unreadChats = ref.watch(unreadMessagesTotalProvider((uid: user.uid, asArtisan: false)));
            final artisan = user.isArtisan ? ref.watch(artisanProfileProvider(user.uid)).asData?.value : null;
            final jobs = artisanMode ? null : ref.watch(customerJobsProvider(user.uid)).asData?.value;
            final active = jobs?.where((j) => !j.status.isTerminal).length;
            return ListView(
              padding: EdgeInsets.only(bottom: widget.standalone ? 40 : CustomerShell.bottomInset),
              children: [
                if (widget.standalone)
                  HtScreenHeader(
                    title: 'Profile',
                    trailing: HtIconCircle(icon: Icons.settings_outlined, tooltip: 'Settings', onTap: () => context.push('/settings')),
                  )
                else
                  HtAppHeader(
                    title: p.isDark ? 'HandyTrust' : 'Profile',
                    actions: [HtIconCircle(icon: Icons.settings_outlined, tooltip: 'Settings', onTap: () => context.push('/settings'))],
                  ),
                if (p.isDark)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 6, HtSpace.gutter, 0),
                    child: Text('Profile & Trust', style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 24)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 18, HtSpace.gutter, 0),
                  child: HtCard(
                    radius: 30,
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _uploading ? null : () => _changePhoto(user),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              HtAvatar(name: user.name, imageUrl: user.photoUrl ?? artisan?.profileImageUrl, size: 104, ring: true),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(color: p.surfaceRaised, shape: BoxShape.circle, border: Border.all(color: p.surface, width: 2)),
                                  child: _uploading
                                      ? Padding(padding: const EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                                      : Icon(Icons.photo_camera_outlined, size: 17, color: p.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text(user.name, style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 22.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            if (artisan != null && ArtisanDiscoveryCard.isIdVerified(artisan)) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.verified_rounded, color: p.success, size: 22),
                            ],
                          ],
                        ),
                        if ((user.location ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on_outlined, size: 16, color: p.textSecondary),
                              const SizedBox(width: 4),
                              Text(user.location!, style: HtType.small(p.textSecondary)),
                            ],
                          ),
                        ],
                        if (artisan != null && ArtisanDiscoveryCard.isIdVerified(artisan)) ...[
                          const SizedBox(height: 12),
                          const HtVerifiedBadge(),
                        ],
                        const SizedBox(height: 18),
                        _StatsRow(
                          stats: artisanMode
                              ? [
                                  ('${artisan?.completedJobs ?? 0}', 'Jobs Done'),
                                  (artisan == null || artisan.totalRatings == 0 ? 'New' : artisan.rating.toStringAsFixed(1), 'Rating'),
                                  ('${artisan?.trustScore.round() ?? 0}', 'Trust Score'),
                                ]
                              : [
                                  ('${jobs?.length ?? 0}', 'Jobs Posted'),
                                  ('${active ?? 0}', 'Active'),
                                  ('${jobs?.where((j) => j.status.name == 'completed').length ?? 0}', 'Completed'),
                                ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 18, HtSpace.gutter, 0),
                  child: HtCard(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        HtMenuRow(
                          icon: Icons.work_outline_rounded,
                          title: 'My Jobs',
                          subtitle: active == null || artisanMode ? null : '$active active',
                          trailing: (active ?? 0) > 0 ? HtStatusPill(label: '$active Active', tone: HtTone.accent) : null,
                          onTap: () => _openJobs(user),
                        ),
                        HtMenuRow(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'My Chats',
                          subtitle: 'Messages with artisans',
                          // Stage 8.2: customer-side conversations only (role-separated).
                          trailing: unreadChats > 0 ? HtStatusPill(label: '$unreadChats unread', tone: HtTone.accent) : null,
                          onTap: () => context.push('/my-chats'),
                        ),
                        // Stage 8.1: artisan reviews, earnings and verification
                        // live in the artisan experience (Artisan Mode).
                        if (!artisanMode)
                          HtMenuRow(
                            icon: Icons.receipt_long_outlined,
                            title: 'Payment History',
                            subtitle: 'Escrow payments and refunds',
                            onTap: () => widget.standalone ? context.push('/wallet') : ref.read(customerTabProvider.notifier).state = CustomerTab.wallet,
                          ),
                        // Stage 8.2: each row opens its own destination.
                        HtMenuRow(icon: Icons.badge_outlined, title: 'Account Information', subtitle: 'Personal details and email', onTap: () => context.push('/settings/personal')),
                        HtMenuRow(icon: Icons.lock_outline_rounded, title: 'Security & Password', onTap: () => context.push('/settings/security')),
                        HtMenuRow(icon: Icons.notifications_active_outlined, title: 'Notification Settings', onTap: () => context.push('/settings/notifications')),
                        HtMenuRow(
                          icon: Icons.dark_mode_outlined,
                          title: 'Obsidian Dark Mode',
                          onTap: () => ref.read(themeProvider.notifier).toggle(),
                          showChevron: false,
                          trailing: Switch(
                            value: themeMode == ThemeMode.dark,
                            onChanged: (_) => ref.read(themeProvider.notifier).toggle(),
                            activeThumbColor: p.isDark ? p.onPrimary : Colors.white,
                            activeTrackColor: p.isDark ? p.accent : p.accentStrong,
                          ),
                        ),
                        if (user.hasBothRoles)
                          HtMenuRow(
                            icon: Icons.handyman_outlined,
                            title: 'Artisan Mode',
                            subtitle: artisanMode ? 'Accepting nearby jobs' : 'Switch to find work',
                            showChevron: false,
                            trailing: _switching
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                : Switch(
                                    value: artisanMode,
                                    onChanged: (v) => _switchRole(user, v),
                                    activeThumbColor: p.isDark ? p.onPrimary : Colors.white,
                                    activeTrackColor: p.isDark ? p.accent : p.accentStrong,
                                  ),
                          ),
                        HtMenuRow(icon: Icons.support_agent_outlined, title: 'Support Center', subtitle: 'Disputes and account help', onTap: () => context.push('/support')),
                        HtMenuRow(icon: Icons.info_outline_rounded, title: 'About HandyTrust', onTap: () => context.push('/about')),
                      ],
                    ),
                  ),
                ),
                if (isAdmin)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 16, HtSpace.gutter, 0),
                    child: HtCard(
                      padding: EdgeInsets.zero,
                      onTap: () => context.go('/admin'),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(color: p.isDark ? p.accentSoft : p.accentStrong, shape: BoxShape.circle),
                              child: Icon(Icons.admin_panel_settings_outlined, color: p.isDark ? p.accent : Colors.white),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text('Admin Dashboard', style: HtType.cardTitle(p.textPrimary)),
                                    const SizedBox(width: 8),
                                    const HtStatusPill(label: 'Staff', tone: HtTone.accent),
                                  ]),
                                  Text('Disputes, verification and payouts', style: HtType.small(p.textSecondary)),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_rounded, color: p.textSecondary),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 16, HtSpace.gutter, 0),
                  child: HtCard(
                    padding: EdgeInsets.zero,
                    color: p.isDark ? p.surface : p.surfaceRaised,
                    child: HtMenuRow(icon: Icons.logout_rounded, title: 'Log Out from HandyTrust', destructive: true, showChevron: false, onTap: _signOut),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.inner)),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++)
            Expanded(
              child: Column(
                children: [
                  Text(stats[i].$1, style: HtType.cardTitle(i == 1 ? (p.isDark ? p.accent : p.accentStrong) : p.textPrimary).copyWith(fontSize: 19)),
                  const SizedBox(height: 2),
                  Text(stats[i].$2, style: HtType.small(p.textSecondary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

