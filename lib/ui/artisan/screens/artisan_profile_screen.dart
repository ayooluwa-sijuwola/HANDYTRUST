import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/artisan_eligibility.dart';
import '../../../core/services/trust_score_service.dart';
import '../../../models/user_model.dart';
import '../../../providers/artisan_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/portfolio_provider.dart';
import '../../../providers/verification_provider.dart';
import '../../../models/verification_model.dart';
import '../../components/ht_components.dart';
import '../../components/ht_format.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';
import 'artisan_home_screen.dart' show showTrustBreakdown;

/// AR-P Artisan profile (Profile tab): how customers see you, your
/// business, account. Artisan-only; customers keep the Stage 8 profile.
class ArtisanProProfileScreen extends ConsumerStatefulWidget {
  const ArtisanProProfileScreen({super.key});
  @override
  ConsumerState<ArtisanProProfileScreen> createState() => _ArtisanProfileScreenState();
}

class _ArtisanProfileScreenState extends ConsumerState<ArtisanProProfileScreen> {
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
      if (mounted) htSnack(context, 'Could not update your photo. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _toCustomer(UserModel user) async {
    setState(() => _switching = true);
    try {
      await ref.read(profileServiceProvider).setActiveRole(user.uid, 'customer');
      if (mounted) context.go('/home');
    } catch (_) {
      if (mounted) htSnack(context, 'Could not switch mode. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await htConfirm(context, title: 'Log out of HandyTrust?', message: 'You can sign back in at any time.', confirmLabel: 'Log Out');
    if (!ok || !mounted) return;
    await ref.read(authNotifierProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final ctx = ref.watch(artisanContextProvider).asData?.value;
    if (ctx == null) return const Column(children: [ArtisanTabHeader(), Expanded(child: ArtisanState.loading())]);
    final user = ctx.user;
    final a = ctx.artisan;
    final isAdmin = ref.watch(isAdminProvider).asData?.value ?? false;
    final projects = ref.watch(portfolioProjectsProvider(ctx.uid)).asData?.value.length;
    final views = ref.watch(portfolioViewCountProvider(ctx.uid)).asData?.value;
    final payoutReady = ref.watch(artisanPayoutReadyProvider(ctx.uid)).asData?.value;
    final verification = ref.watch(verificationStatusProvider(ctx.uid)).asData?.value;
    final verified = a != null && ArtisanEligibility.isReallyVerified(a);
    final verificationText = verified
        ? 'Verified'
        : switch (verification?.status) {
            VerificationStatus.pending => 'Under review',
            VerificationStatus.rejected => 'Needs attention',
            VerificationStatus.approved => 'Verified',
            _ => 'Not started',
          };
    final skills = (a?.skills ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final score = (a?.trustScore ?? 0).clamp(0, 100).toDouble();
    final dualRole = user.roles.contains('customer') || user.isCustomer;

    return ArtisanTabBody(children: [
      proTitle(context, 'Profile'),
      ProSection('How customers see you', trailing: 'Preview', onTrailing: () => context.push('/artisan/${ctx.uid}')),
      HtCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Semantics(
              button: true,
              label: 'Change profile photo',
              child: GestureDetector(
                onTap: _uploading ? null : () => _changePhoto(user),
                child: Stack(children: [
                  HtAvatar(name: ctx.name, imageUrl: a?.profileImageUrl ?? user.photoUrl, size: 64, ring: true, online: a?.isAvailable ?? false),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: proAccent(p), shape: BoxShape.circle, border: Border.all(color: p.surface, width: 2)),
                      child: _uploading
                          ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: proOnAccent(p)))
                          : Icon(Icons.photo_camera_outlined, size: 12, color: proOnAccent(p)),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ctx.name, style: HtType.cardTitle(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(ctx.trade.isEmpty ? 'Artisan' : ctx.trade, style: HtType.small(p.textSecondary)),
                const SizedBox(height: 6),
                if (verified) const HtVerifiedBadge() else HtStatusPill(label: 'Verification: $verificationText', tone: HtTone.warning),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: ProStat(label: 'Rating', value: (a?.totalRatings ?? 0) == 0 ? '—' : a!.rating.toStringAsFixed(1), sub: '${a?.totalRatings ?? 0} reviews')),
            const SizedBox(width: 8),
            Expanded(child: ProStat(label: 'Jobs done', value: '${a?.completedJobs ?? 0}')),
            const SizedBox(width: 8),
            Expanded(child: ProStat(label: 'Trust', value: '${score.round()}', sub: TrustScoreService.tierLabel(score), onTap: a == null ? null : () => showTrustBreakdown(context, a))),
          ]),
          if (skills.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final s in skills) HtStatusPill(label: s, tone: HtTone.accent)]),
          ],
          if (a?.bio != null && a!.bio!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(a.bio!.trim(), style: HtType.small(p.textSecondary), maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
        ]),
      ),
      const ProSection('Your business'),
      HtCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          HtMenuRow(
            icon: Icons.storefront_outlined,
            title: 'Business profile',
            subtitle: [
              if (a?.accountType == 'business' && (a?.businessName?.isNotEmpty ?? false)) a!.businessName! else 'Individual',
              if (a?.serviceRadiusKm != null) '${a!.serviceRadiusKm!.round()} km radius',
            ].join(' · '),
            onTap: () => context.push('/business-profile'),
          ),
          HtMenuRow(
            icon: Icons.photo_library_outlined,
            title: 'Portfolio',
            subtitle: [if (projects != null) '$projects ${projects == 1 ? 'project' : 'projects'}', if (views != null) '$views views'].join(' · '),
            onTap: () => context.push('/portfolio'),
          ),
          HtMenuRow(icon: Icons.verified_user_outlined, title: 'Identity verification', subtitle: verificationText, onTap: () => context.push('/verification')),
          HtMenuRow(
            icon: Icons.star_outline_rounded,
            title: 'My reviews',
            subtitle: (a?.totalRatings ?? 0) == 0 ? 'No reviews yet' : '${a!.rating.toStringAsFixed(1)} average · ${a.totalRatings} reviews',
            onTap: () => context.push('/artisan/${ctx.uid}'),
          ),
          HtMenuRow(icon: Icons.account_balance_outlined, title: 'Payout account', subtitle: payoutReady == true ? 'Bank account on file' : 'Not set up', onTap: () => context.push('/bank-details')),
        ]),
      ),
      const ProSection('Account'),
      HtCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          if (dualRole)
            HtMenuRow(
              icon: Icons.swap_horiz_rounded,
              title: 'Switch to Customer mode',
              subtitle: 'You have both roles',
              trailing: _switching ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: proAccent(p))) : null,
              onTap: _switching ? null : () => _toCustomer(user),
            ),
          HtMenuRow(icon: Icons.chat_bubble_outline_rounded, title: 'Messages', subtitle: 'Conversations with customers', onTap: () => context.push('/my-chats')),
          HtMenuRow(icon: Icons.settings_outlined, title: 'Settings', subtitle: 'Account, security, notifications', onTap: () => context.push('/settings')),
          HtMenuRow(icon: Icons.support_agent_rounded, title: 'Help & Support', onTap: () => context.push('/support')),
          HtMenuRow(icon: Icons.info_outline_rounded, title: 'About HandyTrust', onTap: () => context.push('/about')),
          if (isAdmin) HtMenuRow(icon: Icons.admin_panel_settings_outlined, title: 'Admin dashboard', subtitle: 'Administrator access', onTap: () => context.go('/admin')),
          HtMenuRow(icon: Icons.logout_rounded, title: 'Log out', destructive: true, showChevron: false, onTap: _signOut),
        ]),
      ),
      const SizedBox(height: 8),
      Center(child: Text('Joined ${HtFormat.date(user.createdAt.toLocal())}', style: HtType.small(p.textMuted))),
    ]);
  }
}
