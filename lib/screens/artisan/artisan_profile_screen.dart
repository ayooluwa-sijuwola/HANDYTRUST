import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/artisan_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../models/portfolio_project_model.dart';
import '../../providers/portfolio_provider.dart';
import '../../providers/review_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/portfolio_viewer.dart';
import '../../widgets/review_tile.dart';
import '../../widgets/trust_score_card.dart';

class ArtisanProfileScreen extends ConsumerWidget {
  final String artisanId;
  final String? jobId;

  const ArtisanProfileScreen({
    super.key,
    required this.artisanId,
    this.jobId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artisanAsync = ref.watch(artisanProfileProvider(artisanId));
    final reviewsAsync = ref.watch(artisanReviewsProvider(artisanId));

    return Scaffold(
      backgroundColor: context.colors.background,
      body: artisanAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (artisan) {
          if (artisan == null) {
            return const Center(child: Text('Artisan not found'));
          }
          return _ProfileBody(
            artisan: artisan,
            jobId: jobId,
            reviewsAsync: reviewsAsync,
          );
        },
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final ArtisanModel artisan;
  final String? jobId;
  final AsyncValue<({int count, double avg})> reviewsAsync;

  const _ProfileBody({
    required this.artisan,
    required this.jobId,
    required this.reviewsAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final escrowNotifier = ref.watch(escrowNotifierProvider);

    return CustomScrollView(
      slivers: [
        _buildAppBar(context, ref),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(context),
                const SizedBox(height: 20),
                _statsRow(context, reviewsAsync),
                if (artisan.totalRatings > 0 || artisan.totalJobs > 0) ...[
                  const SizedBox(height: 20),
                  TrustScoreCard(artisan: artisan),
                ],
                const SizedBox(height: 20),
                _escrowGuaranteeCard(context),
                if (artisan.bio != null && artisan.bio!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _section(context, 'About', artisan.bio!),
                ],
                if (artisan.skills.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _section(context, 'Skills', artisan.skills),
                ],
                if (artisan.accountType == 'business') ...[
                  const SizedBox(height: 20),
                  _businessDetailsSection(context),
                ],
                _ProjectsSection(artisanId: artisan.uid),
                if (artisan.portfolioImageUrls.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _portfolioSection(context, ref),
                ],
                if (artisan.totalRatings > 0) ...[
                  const SizedBox(height: 20),
                  _reviewsSection(context, ref),
                ],
                const SizedBox(height: 32),
                if (jobId != null)
                  _actionButton(context, ref, escrowNotifier)
                else
                  // No existing job context — this is a customer browsing
                  // the artisan cold (Home/Browse Artisans), the real gap
                  // the Secure Booking wizard fills (design/
                  // STITCH_BUILD_ORDER.md Group 7). Previously this screen
                  // showed no action at all in this case.
                  CommitButton(
                    label: 'Start Secure Booking',
                    icon: Icons.lock_outline_rounded,
                    onPressed: () => context.push('/secure-booking/${artisan.uid}'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(currentUserProfileProvider).value?.uid;
    final isFav = currentUid != null
        ? (ref.watch(favoriteIdsProvider(currentUid)).value?.contains(artisan.uid) ?? false)
        : false;

    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: context.colors.surface,
      foregroundColor: context.colors.textPrimary,
      actions: [
        if (currentUid != null && currentUid != artisan.uid)
          IconButton(
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFav ? context.colors.error : context.colors.textPrimary,
            ),
            tooltip: isFav ? 'Remove from favorites' : 'Save artisan',
            onPressed: () => ref
                .read(favoriteServiceProvider)
                .toggleFavorite(currentUid, artisan.uid),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: artisan.profileImageUrl != null
            ? Image.network(
                artisan.profileImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, err, stack) => _avatarHeader(context),
              )
            : _avatarHeader(context),
      ),
    );
  }

  Widget _avatarHeader(BuildContext context) => Container(
        color: context.colors.primarySurface,
        child: Center(
          child: Text(
            artisan.displayName.isNotEmpty
                ? artisan.displayName[0].toUpperCase()
                : '?',
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w700,
              color: context.colors.primary,
              fontFamily: 'Inter',
            ),
          ),
        ),
      );

  Widget _infoRow(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        artisan.displayName,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (artisan.accountType == 'business') ...[
                      const SizedBox(width: 6),
                      Icon(Icons.storefront_outlined,
                          size: 18, color: context.colors.textTertiary),
                    ],
                    if (artisan.isVerified) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.verified_rounded,
                          size: 20, color: context.colors.accent),
                    ],
                  ],
                ),
                if (artisan.username != null &&
                    artisan.username!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@${artisan.username}',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.primary,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  artisan.category ?? 'General',
                  style: TextStyle(
                    fontSize: 15,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
                if (artisan.location != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: context.colors.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        artisan.location!,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textTertiary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ],
                if (artisan.skills.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  // Specialty pills — matches the Stitch TrustScore-variant
                  // reference's small gray specialty chips ("Electrical",
                  // "Smart Tech", "Lighting"). Real data: splits the
                  // artisan's own comma-separated skills string, not
                  // fabricated categories.
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: artisan.skills
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .take(6)
                        .map((s) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: context.colors.surfaceVariant,
                                borderRadius: BorderRadius.circular(AppRadius.full),
                              ),
                              child: Text(
                                s,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textSecondary,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (artisan.isRising)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: context.colors.risingBadgeSurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Rising Pro',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.colors.risingBadge,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              if (trustTierBadge(context, artisan.trustTier) != null) ...[
                if (artisan.isRising) const SizedBox(height: 6),
                trustTierBadge(context, artisan.trustTier)!,
              ],
            ],
          ),
        ],
      );

  // Navy card treatment — first real use of the Stitch-derived navy tokens
  // (Group 1). The TrustScoreCard right below keeps its normal light
  // styling since it's shared with the artisan's own dashboard sheet;
  // this stats strip is local to this screen, so it's a safe place to
  // bring in the dark-card look Stitch's profile screens used.
  Widget _statsRow(
    BuildContext context,
    AsyncValue<({int count, double avg})> reviewsAsync,
  ) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: context.colors.navy,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Row(
          children: [
            _statCard(
              context,
              label: 'Rating',
              value: reviewsAsync.when(
                data: (r) => r.avg == 0 ? 'New' : r.avg.toStringAsFixed(1),
                loading: () => '...',
                error: (_, stack) => '—',
              ),
              icon: Icons.star_rounded,
              iconColor: context.colors.ratingGold,
            ),
            _statCard(
              context,
              label: 'Jobs done',
              value: '${artisan.completedJobs}',
              icon: Icons.check_circle_outline_rounded,
              iconColor: context.colors.primary,
            ),
            _statCard(
              context,
              label: 'Response',
              value: artisan.responseTimeMinutes < 60
                  ? '${artisan.responseTimeMinutes.toInt()}m'
                  : '${(artisan.responseTimeMinutes / 60).toStringAsFixed(1)}h',
              icon: Icons.timer_outlined,
              iconColor: context.colors.primary,
            ),
          ],
        ),
      );

  Widget _statCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) =>
      Expanded(
        child: Column(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.colors.onNavy,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: context.colors.onNavySecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      );

  // Matches the Stitch TrustScore-variant reference's light-green bordered
  // "HandyTrust Escrow Guarantee" card. Static explanatory copy — no data
  // dependency, describes the real escrow mechanism unchanged elsewhere in
  // the app (payment_screen.dart's identical explanation).
  Widget _escrowGuaranteeCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: context.colors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HandyTrust Escrow Guarantee',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your funds are held securely until you approve the completed work. No upfront risk.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                      height: 1.4,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _section(BuildContext context, String title, String content) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
              height: 1.6,
              fontFamily: 'Inter',
            ),
          ),
        ],
      );

  Widget _businessDetailsSection(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storefront_outlined,
                    size: 16, color: context.colors.textSecondary),
                SizedBox(width: 6),
                Text(
                  'Registered Business',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
            if (artisan.businessRegistrationNumber != null &&
                artisan.businessRegistrationNumber!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Reg. No: ${artisan.businessRegistrationNumber}',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
            if (artisan.businessAddress != null &&
                artisan.businessAddress!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                artisan.businessAddress!,
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ],
        ),
      );

  Widget _portfolioSection(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Portfolio',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: artisan.portfolioImageUrls.length,
              separatorBuilder: (_, index) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () {
                  ref.read(portfolioServiceProvider).recordView(artisan.uid);
                  showPortfolioViewer(
                    context,
                    imageUrls: artisan.portfolioImageUrls,
                    initialIndex: i,
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    artisan.portfolioImageUrls[i],
                    width: 160,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, err, stack) => Container(
                      width: 160,
                      height: 160,
                      color: context.colors.surfaceVariant,
                      child: Icon(Icons.broken_image_outlined,
                          size: 32, color: context.colors.textTertiary),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _reviewsSection(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(artisanReviewListProvider(artisan.uid));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reviews',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
            fontFamily: 'Inter',
          ),
        ),
        const SizedBox(height: 10),
        reviewsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error: $e',
              style: TextStyle(color: context.colors.error, fontFamily: 'Inter')),
          data: (reviews) {
            if (reviews.isEmpty) {
              return Text(
                'No reviews yet',
                style: TextStyle(color: context.colors.textTertiary, fontFamily: 'Inter'),
              );
            }
            return Column(
              children: reviews.map((r) => ReviewTile(review: r)).toList(),
            );
          },
        ),
      ],
    );
  }

  // Black "commitment" button — hiring an artisan is the same category of
  // one-time, high-commitment action as Post Job / Lock Funds in Escrow,
  // and the closest existing analogue to Stitch's "Start Secure Booking" /
  // "Book Now" buttons on this screen.
  Widget _actionButton(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<void> state,
  ) =>
      CommitButton(
        label: 'Hire This Artisan',
        loading: state.isLoading,
        onPressed: () => _confirmHire(context, ref),
      );

  Future<void> _confirmHire(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Selection',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to hire ${artisan.displayName}.',
              style: const TextStyle(fontFamily: 'Inter'),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.primarySurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'A chat will open to discuss the job. You will only pay after agreeing on a price — funds are held in escrow until the work is confirmed complete.',
                style: TextStyle(
                    fontSize: 13, fontFamily: 'Inter', height: 1.5,
                    color: context.colors.primary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await ref.read(escrowNotifierProvider.notifier).acceptArtisan(jobId!, artisan.uid);

    if (context.mounted) {
      context.push('/chat/$jobId', extra: {
        'artisanId': artisan.uid,
        'artisanName': artisan.displayName,
      });
    }
  }
}

// ─── Portfolio projects section ───────────────────────────────────────────────

class _ProjectsSection extends ConsumerWidget {
  final String artisanId;
  const _ProjectsSection({required this.artisanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(portfolioProjectsProvider(artisanId));
    return projectsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (projects) {
        if (projects.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text(
              'Projects',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 10),
            ...projects.map((p) => _ProjectCard(project: p)),
          ],
        );
      },
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final PortfolioProjectModel project;
  const _ProjectCard({required this.project});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (project.imageUrls.isNotEmpty)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              child: SizedBox(
                height: 160,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: project.imageUrls.length,
                  itemBuilder: (_, i) => Image.network(
                    project.imageUrls[i],
                    width: 160,
                    height: 160,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        project.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: context.colors.primarySurface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        project.category,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.primary,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (project.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    project.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textSecondary,
                      height: 1.5,
                      fontFamily: 'Inter',
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
