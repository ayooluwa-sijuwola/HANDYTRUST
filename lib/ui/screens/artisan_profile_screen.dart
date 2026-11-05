import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/artisan_eligibility.dart';
import '../../models/artisan_model.dart';
import '../../models/review_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../providers/review_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../theme/ht_theme.dart';

/// Artisan profile (references 2 dark, 16 light). Data: artisanProfileProvider,
/// artisanReviewListProvider, portfolioProjectsProvider, favorites.
/// Not shown (no backend data): service rates, starting price, years of
/// experience, "biometrics" verification, reviewer names/areas.
///
/// With [jobId] (opened from the matched-artisans list) the CTA books this
/// artisan for that job (escrowNotifier.acceptArtisan); otherwise it starts
/// the existing Secure Booking flow.
class ArtisanProfileScreen extends ConsumerWidget {
  const ArtisanProfileScreen({super.key, required this.artisanId, this.jobId});
  final String artisanId;
  final String? jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final async = ref.watch(artisanProfileProvider(artisanId));
    return Scaffold(
      backgroundColor: p.backgroundDeep,
      body: HtBackground(
        deep: true,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const HtLoadingView(),
            error: (e, _) => Column(children: [
              const HtScreenHeader(title: ''),
              HtErrorView(message: 'This profile could not be loaded.', onRetry: () => ref.invalidate(artisanProfileProvider(artisanId))),
            ]),
            data: (a) => a == null
                ? const Column(children: [HtScreenHeader(title: ''), HtEmptyView(icon: Icons.person_off_outlined, title: 'Artisan not found')])
                : _Body(artisan: a, jobId: jobId),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.artisan, required this.jobId});
  final ArtisanModel artisan;
  final String? jobId;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _hiring = false;

  Future<void> _book() async {
    final a = widget.artisan;
    final jobId = widget.jobId;
    if (jobId == null) {
      context.push('/secure-booking/${a.uid}');
      return;
    }
    final ok = await htConfirm(
      context,
      title: 'Book ${a.displayName}?',
      message: 'A chat will open to agree the price and schedule. You only pay after agreeing — funds are held in escrow until you approve the completed work.',
      confirmLabel: 'Send Booking Request',
    );
    if (!ok || !mounted) return;
    setState(() => _hiring = true);
    await ref.read(escrowNotifierProvider.notifier).acceptArtisan(jobId, a.uid);
    if (!mounted) return;
    setState(() => _hiring = false);
    final r = ref.read(escrowNotifierProvider);
    if (r.hasError) {
      htSnack(context, 'Could not send the booking request: ${r.error}', error: true);
      return;
    }
    context.push('/chat/$jobId', extra: {'artisanId': a.uid, 'artisanName': a.displayName});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final a = widget.artisan;
    final uid = ref.watch(authStateChangesProvider).asData?.value?.uid;
    final isSelf = uid == a.uid;
    final favs = uid == null ? const <String>{} : (ref.watch(favoriteIdsProvider(uid)).asData?.value ?? const <String>{});
    final isFav = favs.contains(a.uid);
    final reviews = ref.watch(artisanReviewListProvider(a.uid)).asData?.value ?? const <ReviewModel>[];
    final projects = ref.watch(portfolioProjectsProvider(a.uid)).asData?.value ?? const [];
    final images = [...a.portfolioImageUrls, for (final pr in projects) ...pr.imageUrls];
    final canBook = !isSelf && ArtisanEligibility.canQuote(a) && !a.isSuspended;
    final area = HtFormat.area(a.serviceAddress);
    final skills = a.skills.split(RegExp(r'[,\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 140),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 8, HtSpace.gutter, 0),
              child: Row(
                children: [
                  HtIconCircle(icon: Icons.chevron_left_rounded, tooltip: 'Back', onTap: () => Navigator.of(context).maybePop()),
                  const Spacer(),
                  if (uid != null && !isSelf)
                    HtIconCircle(
                      icon: isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      tooltip: isFav ? 'Remove from favourites' : 'Save to favourites',
                      iconColor: isFav ? (p.isDark ? p.accent : p.accentStrong) : null,
                      onTap: () => ref.read(favoriteServiceProvider).toggleFavorite(uid, a.uid),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(child: HtAvatar(name: a.name, imageUrl: a.profileImageUrl, size: 124, ring: true, online: a.isAvailable)),
            const SizedBox(height: 16),
            Center(child: Text(a.displayName, style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 26), textAlign: TextAlign.center)),
            const SizedBox(height: 6),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(a.category ?? 'Artisan', style: HtType.body(p.textSecondary).copyWith(fontSize: 14)),
                  if (area != null) ...[
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('•', style: HtType.body(p.textMuted))),
                    Icon(Icons.location_on, size: 16, color: p.isDark ? p.accentStrong : p.textSecondary),
                    const SizedBox(width: 4),
                    Text(area, style: HtType.body(p.textSecondary).copyWith(fontSize: 14)),
                  ],
                ],
              ),
            ),
            if (ArtisanEligibility.isReallyVerified(a)) ...[const SizedBox(height: 14), const Center(child: HtVerifiedBadge())],
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HtSpace.gutter),
              child: Row(
                children: [
                  Expanded(child: HtStatTile(value: a.totalRatings > 0 ? a.rating.toStringAsFixed(1) : 'New', label: 'Rating', icon: Icons.star_rounded)),
                  const SizedBox(width: 12),
                  Expanded(child: HtStatTile(value: '${a.completedJobs}', label: 'Jobs Done')),
                  const SizedBox(width: 12),
                  Expanded(child: HtStatTile(value: '${a.trustScore.round()}', label: 'Trust Score')),
                ],
              ),
            ),
            if ((a.bio ?? '').trim().isNotEmpty)
              _section(context, title: 'About', child: Text(a.bio!.trim(), style: HtType.body(p.textSecondary).copyWith(fontSize: 14, height: 1.6))),
            if (skills.isNotEmpty)
              _section(
                context,
                title: 'Services',
                trailing: 'Rates agreed per job',
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < skills.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: p.border, indent: 20, endIndent: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: p.surfaceRaised, shape: BoxShape.circle),
                              child: Icon(Icons.build_outlined, size: 18, color: p.isDark ? p.accent : p.accentStrong),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Text(skills[i], style: HtType.body(p.textPrimary).copyWith(fontSize: 14))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (images.isNotEmpty)
              _section(
                context,
                title: 'Portfolio',
                child: SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: images.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _showImage(context, images[i]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(HtRadius.tile),
                        child: Image.network(images[i], width: 110, height: 110, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(width: 110, color: p.surfaceRaised, child: Icon(Icons.broken_image_outlined, color: p.textMuted))),
                      ),
                    ),
                  ),
                ),
              ),
            _section(
              context,
              title: p.isDark ? 'Client Reviews' : 'Recent Reviews',
              titleSuffix: '(${a.totalRatings})',
              trailing: 'Verified hires',
              padding: EdgeInsets.zero,
              child: reviews.isEmpty
                  ? Padding(padding: const EdgeInsets.all(20), child: Text('No reviews yet.', style: HtType.body(p.textSecondary)))
                  : Column(
                      children: [
                        for (var i = 0; i < reviews.take(5).length; i++) ...[
                          if (i > 0) Divider(height: 1, color: p.border, indent: 20, endIndent: 20),
                          _ReviewTile(review: reviews[i]),
                        ],
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(HtSpace.gutter + 8, 22, HtSpace.gutter + 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_outlined, size: 20, color: p.isDark ? const Color(0xFF7FC4E6) : p.accentStrong),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text('Funds held safely in Escrow. Released only upon your sign-off.',
                        style: HtType.small(p.textSecondary).copyWith(fontSize: 12), textAlign: TextAlign.center),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!isSelf)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(HtSpace.gutter, 14, HtSpace.gutter, 14 + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(
                color: p.isDark ? const Color(0xFF0C0F0B) : p.surface,
                border: Border(top: BorderSide(color: p.border)),
                borderRadius: p.isDark ? null : const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: canBook
                  ? HtPrimaryButton(
                      label: 'Book ${a.displayName.split(' ').first}',
                      icon: Icons.arrow_forward_rounded,
                      loading: _hiring,
                      onPressed: _book,
                    )
                  : Text(
                      'This artisan is not currently available for booking.',
                      style: HtType.body(p.textSecondary),
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
      ],
    );
  }

  Widget _section(BuildContext context, {required String title, String? titleSuffix, String? trailing, required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(20)}) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 18, HtSpace.gutter, 0),
      child: HtCard(
        radius: 28,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Row(
                children: [
                  Text(p.isDark ? title.toUpperCase() : title, style: p.isDark ? HtType.cardTitle(p.textPrimary).copyWith(letterSpacing: 1) : HtType.cardTitle(p.textPrimary)),
                  if (titleSuffix != null) ...[const SizedBox(width: 6), Text(titleSuffix, style: HtType.body(p.textSecondary))],
                  const Spacer(),
                  if (trailing != null) Text(trailing, style: HtType.smallStrong(p.isDark ? p.accent : p.accentStrong)),
                ],
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }

  void _showImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: ClipRRect(borderRadius: BorderRadius.circular(HtRadius.inner), child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain))),
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final ReviewModel review;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                Icon(i < review.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 20, color: p.isDark ? const Color(0xFFF5B83D) : p.accentStrong),
              const Spacer(),
              Text(HtFormat.timeAgo(review.createdAt), style: HtType.small(p.textSecondary)),
            ],
          ),
          if (review.comment.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('"${review.comment.trim()}"', style: HtType.body(p.textPrimary).copyWith(fontSize: 13.5, height: 1.55)),
          ],
          const SizedBox(height: 8),
          Text('Verified customer', style: HtType.smallStrong(p.textSecondary)),
        ],
      ),
    );
  }
}
