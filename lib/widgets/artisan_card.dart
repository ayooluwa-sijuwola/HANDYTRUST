import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/services/trust_score_service.dart';
import '../models/artisan_model.dart';
import '../theme/app_design_system.dart';
import '../theme/app_theme.dart';
import 'star_rating.dart';
import 'trust_score_card.dart';

class ArtisanCard extends StatelessWidget {
  final ArtisanModel artisan;
  final VoidCallback onTap;

  const ArtisanCard({super.key, required this.artisan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: context.colors.border),
          boxShadow: Theme.of(context).brightness == Brightness.dark
              ? AppShadows.cardDark
              : AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar / image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.xl)),
                  child: artisan.profileImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: artisan.profileImageUrl!,
                          height: 130,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (ctx, url) => _avatarPlaceholder(context),
                          errorWidget: (ctx, url, err) => _avatarPlaceholder(context),
                        )
                      : _avatarPlaceholder(context),
                ),
                if (artisan.isRising)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _badge(
                      '⭐ Rising Pro',
                      context.colors.risingBadge,
                      context.colors.risingBadgeSurface,
                    ),
                  ),
                if (artisan.isVerified)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _badge(
                      '✓ Verified',
                      context.colors.primary,
                      context.colors.primarySurface,
                    ),
                  ),
                if (trustTierBadge(context, artisan.trustTier) != null)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: trustTierBadge(context, artisan.trustTier)!,
                  ),
              ],
            ),

            // Info section
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          artisan.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (artisan.accountType == 'business') ...[
                        const SizedBox(width: 4),
                        Icon(Icons.storefront_outlined,
                            size: 14,
                            color: context.colors.textTertiary),
                      ],
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
                  const SizedBox(height: 8),
                  StarRating(rating: artisan.rating, size: 13),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.work_outline_rounded,
                          size: 12,
                          color: context.colors.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        '${artisan.completedJobs} jobs',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.textTertiary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      if (artisan.location != null) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.location_on_outlined,
                            size: 12,
                            color: context.colors.textTertiary),
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
                  const SizedBox(height: 6),
                  // Trust score chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: context.colors.primarySurface,
                      borderRadius:
                          BorderRadius.circular(AppRadius.full),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_outlined,
                            size: 11,
                            color: context.colors.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Trust ${artisan.trustScore.toStringAsFixed(0)}/100 · ${TrustScoreService.tierLabel(artisan.trustScore)}',
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarPlaceholder(BuildContext context) => Container(
        height: 130,
        width: double.infinity,
        color: context.colors.primarySurface,
        child: Center(
          child: Text(
            artisan.displayName.isNotEmpty
                ? artisan.displayName[0].toUpperCase()
                : '?',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: context.colors.primary,
              fontFamily: 'Inter',
            ),
          ),
        ),
      );

  Widget _badge(String label, Color fg, Color bg) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: fg,
            fontFamily: 'Inter',
          ),
        ),
      );
}
