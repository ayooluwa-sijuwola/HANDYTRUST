import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/artisan_model.dart';
import '../../providers/matching_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/star_rating.dart';

class ArtisanListScreen extends ConsumerWidget {
  final String jobId;
  final String category;
  final double? customerLat;
  final double? customerLng;

  const ArtisanListScreen({
    super.key,
    required this.jobId,
    required this.category,
    this.customerLat,
    this.customerLng,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = MatchingParams(
      category: category,
      lat: customerLat,
      lng: customerLng,
    );
    final matchAsync = ref.watch(matchingProvider(params));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(
          category.isEmpty ? 'Choose an Artisan' : category,
          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.borderLight),
        ),
      ),
      body: matchAsync.when(
        loading: () => _LoadingSkeleton(colors: context.colors),
        error: (e, _) => _ErrorState(message: e.toString()),
        data: (artisans) {
          if (artisans.isEmpty) return _EmptyState(category: category);

          final experienced = artisans.where((a) => !a.isRising).toList();
          final rising = artisans.where((a) => a.isRising).toList();

          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              if (experienced.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Top Professionals',
                  subtitle: '${experienced.length} artisan${experienced.length == 1 ? '' : 's'} available',
                  icon: Icons.verified_rounded,
                  iconColor: context.colors.primary,
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ArtisanListTile(
                          artisan: experienced[i],
                          onTap: () => context.push(
                            '/artisan/${experienced[i].uid}',
                            extra: {'jobId': jobId},
                          ),
                        ),
                      ),
                      childCount: experienced.length,
                    ),
                  ),
                ),
              ],
              if (rising.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 4)),
                _SectionHeader(
                  title: 'Rising Professionals',
                  subtitle: 'Fresh talent — eager, available, and affordable',
                  icon: Icons.trending_up_rounded,
                  iconColor: context.colors.risingBadge,
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ArtisanListTile(
                          artisan: rising[i],
                          onTap: () => context.push(
                            '/artisan/${rising[i].uid}',
                            extra: {'jobId': jobId},
                          ),
                          isRisingSection: true,
                        ),
                      ),
                      childCount: rising.length,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? iconColor;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (iconColor ?? context.colors.primary).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 18, color: iconColor ?? context.colors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtisanListTile extends StatelessWidget {
  final ArtisanModel artisan;
  final VoidCallback onTap;
  final bool isRisingSection;

  const _ArtisanListTile({
    required this.artisan,
    required this.onTap,
    this.isRisingSection = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: context.colors.border),
          boxShadow: isDark ? AppShadows.cardDark : AppShadows.card,
        ),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                _Avatar(artisan: artisan),
                if (artisan.isVerified)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: context.colors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.colors.surface, width: 1.5),
                      ),
                      child: const Icon(Icons.check, size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          artisan.displayName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isRisingSection)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: context.colors.risingBadgeSurface,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            '⭐ Rising',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: context.colors.risingBadge,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artisan.category ?? 'General',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      StarRating(rating: artisan.rating, size: 12),
                      const SizedBox(width: 6),
                      Text(
                        artisan.rating.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.work_outline_rounded,
                          size: 11, color: context.colors.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        '${artisan.completedJobs} jobs',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.textTertiary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Trust score pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: context.colors.primarySurface,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_outlined,
                                size: 10, color: context.colors.primary),
                            const SizedBox(width: 3),
                            Text(
                              '${artisan.trustScore.toStringAsFixed(0)}/100',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: context.colors.primary,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (artisan.location != null) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.location_on_outlined,
                            size: 11, color: context.colors.textTertiary),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            artisan.location!,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.colors.textTertiary,
                              fontFamily: 'Inter',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Select button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppGradients.primary,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: AppShadows.button,
              ),
              child: const Text(
                'Select',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final ArtisanModel artisan;

  const _Avatar({required this.artisan});

  @override
  Widget build(BuildContext context) {
    final initials = artisan.displayName.isNotEmpty
        ? artisan.displayName[0].toUpperCase()
        : '?';

    if (artisan.profileImageUrl != null) {
      return CircleAvatar(
        radius: 30,
        backgroundColor: context.colors.primarySurface,
        backgroundImage: NetworkImage(artisan.profileImageUrl!),
        onBackgroundImageError: (e, st) {},
        child: null,
      );
    }

    return CircleAvatar(
      radius: 30,
      backgroundColor: context.colors.primarySurface,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: context.colors.primary,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  final dynamic colors;

  const _LoadingSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) => Container(
        height: 100,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            CircleAvatar(
              radius: 30,
              backgroundColor: context.colors.shimmerBase,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 13,
                    width: 120,
                    decoration: BoxDecoration(
                      color: context.colors.shimmerBase,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 10,
                    width: 80,
                    decoration: BoxDecoration(
                      color: context.colors.shimmerBase,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 10,
                    width: 140,
                    decoration: BoxDecoration(
                      color: context.colors.shimmerBase,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String category;

  const _EmptyState({required this.category});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.colors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off_rounded,
                  size: 40, color: context.colors.textTertiary),
            ),
            const SizedBox(height: 20),
            Text(
              'No artisans available',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              category.isEmpty
                  ? 'Try a different search or check back later.'
                  : 'No $category artisans are available nearby right now.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: context.colors.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.colors.textSecondary, fontFamily: 'Inter'),
            ),
          ],
        ),
      ),
    );
  }
}
