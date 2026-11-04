import 'package:flutter/material.dart';
import '../core/services/trust_score_service.dart';
import '../models/artisan_model.dart';
import '../theme/app_theme.dart';

/// Small pill badge for an artisan's trust tier. Returns null for
/// 'standard' tier — only 'trusted'/'elite' artisans are called out, to
/// avoid clutter for brand-new artisans whose score is still neutral.
Widget? trustTierBadge(BuildContext context, String tier, {double fontSize = 10}) {
  late final Color fg;
  late final Color bg;
  late final String label;
  switch (tier) {
    case 'elite':
      fg = context.colors.trustElite;
      bg = context.colors.trustEliteSurface;
      label = 'Elite Pro';
      break;
    case 'trusted':
      fg = context.colors.trustTrusted;
      bg = context.colors.trustTrustedSurface;
      label = 'Trusted';
      break;
    default:
      return null;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: fg,
        fontFamily: 'Inter',
      ),
    ),
  );
}

/// Trust score card — dark navy, pixel-matched to Stitch's "TrustScore"
/// card (the variant chosen over the lighter "HandyTrust Score" one).
/// Score/tier badge are real (ArtisanModel.trustScore, always computed and
/// written by Cloud Functions). The two sub-stat chips below use real
/// TrustScoreService.breakdown() components — NOT Stitch's literal
/// "Craftsmanship"/"Punctuality" labels, which don't correspond to
/// anything this backend actually computes (the 5 real weighted
/// components are Completed Jobs / Customer Rating / Verification /
/// Response Speed / Dispute History, see trust_score_service.dart). Using
/// the real top two rather than inventing fake labels for two Stitch
/// never-computed metrics. Stitch's "Top 5%" percentile badge is also
/// omitted for the same reason — no artisan-wide percentile ranking is
/// computed anywhere in this backend; a real one would need a new Cloud
/// Function comparing this artisan's score against the full population,
/// which doesn't exist today (documented gap, not faked).
class TrustScoreCard extends StatelessWidget {
  final ArtisanModel artisan;

  const TrustScoreCard({super.key, required this.artisan});

  @override
  Widget build(BuildContext context) {
    final badge = trustTierBadge(context, artisan.trustTier, fontSize: 11);
    final tierLabel = TrustScoreService.tierLabel(artisan.trustScore);
    final components = TrustScoreService.breakdown(artisan);
    final top2 = components.length >= 2 ? components.sublist(0, 2) : components;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // context.colors.navy, not the AppColors.darkBackground literal
        // this previously hardcoded: on a light page navy is a fixed dark
        // tone that pops correctly either way, but on the dark-mode page
        // that literal is byte-identical to the scaffold background,
        // making the whole card disappear. The theme extension already
        // carries a dark-mode-appropriate navy — this just needed to
        // actually use it.
        color: context.colors.navy,
        borderRadius: BorderRadius.circular(20),
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.08))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'TrustScore',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFamily: 'Inter',
                ),
              ),
              const Spacer(),
              ?badge,
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                artisan.trustScore.toStringAsFixed(0),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontFamily: 'Inter',
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/100 · $tierLabel',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.6),
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < top2.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _componentChip(context, top2[i])),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _componentChip(BuildContext context, TrustComponent c) {
    final fraction = c.maxScore == 0 ? 0.0 : (c.score / c.maxScore).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.6),
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${(fraction * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [TrustScoreCard] in a bottom sheet — used for the artisan's own
/// self-view from the dashboard stat card.
Future<void> showTrustScoreSheet(BuildContext context, ArtisanModel artisan) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(16),
      child: TrustScoreCard(artisan: artisan),
    ),
  );
}
