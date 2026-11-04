import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';

/// Wraps any widget in a shimmer animation using theme-aware colors.
class AppShimmer extends StatelessWidget {
  final Widget child;

  const AppShimmer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.colors.shimmerBase,
      highlightColor: context.colors.shimmerHighlight,
      child: child,
    );
  }
}

/// Shimmer placeholder box.
class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.shimmerBase,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton for a job card.
class JobCardSkeleton extends StatelessWidget {
  const JobCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            ShimmerBox(width: 48, height: 48, radius: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(
                      width: double.infinity, height: 14, radius: 6),
                  const SizedBox(height: 8),
                  ShimmerBox(width: 160, height: 12, radius: 6),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ShimmerBox(width: 70, height: 26, radius: 20),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for an artisan list item.
class ArtisanListSkeleton extends StatelessWidget {
  const ArtisanListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            ShimmerBox(width: 52, height: 52, radius: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(width: 120, height: 14, radius: 6),
                  const SizedBox(height: 6),
                  ShimmerBox(width: 90, height: 12, radius: 6),
                  const SizedBox(height: 6),
                  ShimmerBox(width: 70, height: 10, radius: 6),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ShimmerBox(width: 40, height: 18, radius: 6),
          ],
        ),
      ),
    );
  }
}

/// A list of job card skeletons.
class JobListSkeleton extends StatelessWidget {
  final int count;

  const JobListSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => const JobCardSkeleton()),
    );
  }
}

/// A list of artisan skeletons.
class ArtisanListSkeletons extends StatelessWidget {
  final int count;

  const ArtisanListSkeletons({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => const ArtisanListSkeleton()),
    );
  }
}

/// Skeleton for the home screen header area.
class HomeHeaderSkeleton extends StatelessWidget {
  const HomeHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBox(width: 180, height: 26, radius: 8),
            const SizedBox(height: 6),
            ShimmerBox(width: 240, height: 16, radius: 6),
            const SizedBox(height: 16),
            ShimmerBox(width: double.infinity, height: 48, radius: 14),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for a stats row (3 cards).
class StatsRowSkeleton extends StatelessWidget {
  const StatsRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Row(
        children: List.generate(
          3,
          (i) => Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 2 ? 10 : 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.colors.border),
              ),
              child: Column(
                children: [
                  ShimmerBox(width: 24, height: 24, radius: 12),
                  const SizedBox(height: 8),
                  ShimmerBox(width: 40, height: 18, radius: 6),
                  const SizedBox(height: 4),
                  ShimmerBox(width: 50, height: 12, radius: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
