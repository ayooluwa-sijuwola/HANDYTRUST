import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/artisan_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProfileProvider);
    final uid = userAsync.value?.uid;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text(
          'Saved Artisans',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        backgroundColor: context.colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: context.colors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: uid == null
          ? const Center(child: CircularProgressIndicator())
          : _FavoritesList(userId: uid),
    );
  }
}

class _FavoritesList extends ConsumerWidget {
  final String userId;
  const _FavoritesList({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artisansAsync = ref.watch(favoriteArtisansProvider(userId));

    return artisansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Could not load favorites. Check your connection.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ),
      data: (artisans) {
        if (artisans.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_border_rounded,
                      size: 60, color: context.colors.textTertiary),
                  const SizedBox(height: 16),
                  Text(
                    'No saved artisans yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the heart icon on an artisan\'s profile to save them here for quick rehiring.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/browse-artisans'),
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Browse Artisans'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: artisans.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) =>
              _FavoriteCard(artisan: artisans[i], userId: userId),
        );
      },
    );
  }
}

class _FavoriteCard extends ConsumerWidget {
  final ArtisanModel artisan;
  final String userId;

  const _FavoriteCard({required this.artisan, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVerified = artisan.verificationStatus == 'id_verified' ||
        artisan.verificationStatus == 'trusted';

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: context.colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => context.push('/artisan/${artisan.uid}'),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              UserAvatar(
                photoUrl: artisan.photoUrl ?? artisan.profileImageUrl,
                displayName: artisan.displayName,
                size: 52,
                borderWidth: 2,
              ),
              const SizedBox(width: 14),
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
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.verified_rounded,
                              size: 16, color: context.colors.primary),
                        ],
                      ],
                    ),
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
                        Icon(Icons.star_rounded,
                            size: 13, color: const Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(
                          artisan.rating.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textSecondary,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.shield_outlined,
                            size: 13, color: context.colors.primary),
                        const SizedBox(width: 3),
                        Text(
                          '${artisan.trustScore.toStringAsFixed(0)}/100',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textSecondary,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.check_circle_outline_rounded,
                            size: 13, color: context.colors.accent),
                        const SizedBox(width: 3),
                        Text(
                          '${artisan.completedJobs} jobs',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textSecondary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  IconButton(
                    onPressed: () => ref
                        .read(favoriteServiceProvider)
                        .removeFavorite(userId, artisan.uid),
                    icon: Icon(Icons.favorite_rounded,
                        color: context.colors.error),
                    tooltip: 'Remove from favorites',
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        context.push('/request?category=${artisan.category ?? ''}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Inter',
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      elevation: 0,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Hire'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
