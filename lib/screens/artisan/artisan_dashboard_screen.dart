import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/services/workflow_gate_service.dart';
import '../../models/artisan_model.dart';
import '../../models/job_model.dart';
import '../../models/verification_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/verification_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/workflow_timeline.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/shimmer_loaders.dart';
import '../../widgets/trust_score_card.dart';
import '../../widgets/web_content_wrapper.dart';

// ---------------------------------------------------------------------------
// Full-screen entry (used when router navigates directly to this)
// ---------------------------------------------------------------------------

class ArtisanDashboardScreen extends ConsumerWidget {
  const ArtisanDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // This class is kept only for compatibility — HomeScreen now renders
    // ArtisanHomeTabContent directly inside MainShellScreen.
    return const ArtisanHomeTabContent();
  }
}

// ---------------------------------------------------------------------------
// Tab content — no Scaffold, rendered inside MainShellScreen
// ---------------------------------------------------------------------------

class ArtisanHomeTabContent extends ConsumerWidget {
  const ArtisanHomeTabContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProfileProvider);

    return userAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('$e')),
      data: (user) {
        if (user == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final artisanAsync = ref.watch(artisanProfileProvider(user.uid));
        return artisanAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('$e')),
          data: (artisan) {
            if (artisan == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) context.go('/register/artisan');
              });
              return const Center(child: CircularProgressIndicator());
            }
            return _ArtisanDashBody(userId: user.uid, artisan: artisan);
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard body
// ---------------------------------------------------------------------------

class _ArtisanDashBody extends ConsumerWidget {
  final String userId;
  final ArtisanModel artisan;

  const _ArtisanDashBody({
    required this.userId,
    required this.artisan,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(artisanJobsProvider(userId));

    return WebContentWrapper(
      child: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(context, ref)),
        if (artisan.approvalStatus == 'pending')
          SliverToBoxAdapter(child: _buildPendingBanner(context)),
        if (artisan.approvalStatus == 'approved')
          SliverToBoxAdapter(
              child: _buildAvailabilityToggle(context, ref)),
        SliverToBoxAdapter(
            child: _buildVerificationCard(context, ref)),
        SliverToBoxAdapter(child: _buildStatsRow(context)),
        SliverToBoxAdapter(child: _buildQuickActions(context)),
        SliverToBoxAdapter(
            child: _buildJobsSection(context, jobsAsync)),
        SliverToBoxAdapter(
          child: SizedBox(
              height: MediaQuery.of(context).padding.bottom + 100),
        ),
      ],
      ),
    );
  }

  Future<void> _toggleAvailability(
    BuildContext context,
    WidgetRef ref,
    bool current,
  ) async {
    final firestore = FirebaseFirestore.instance;
    try {
      final batch = firestore.batch();
      batch.set(firestore.collection('artisans').doc(userId),
          {'isAvailable': !current}, SetOptions(merge: true));
      batch.set(firestore.collection('users').doc(userId),
          {'isAvailable': !current}, SetOptions(merge: true));
      await batch.commit();
    } catch (e) {
      debugPrint('[ArtisanDashboard] toggleAvailability failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update availability: $e'),
            backgroundColor: context.colors.error,
          ),
        );
      }
    }
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) =>
      Container(
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
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
                        fontWeight: FontWeight.w800,
                        color: context.colors.primary,
                        fontFamily: 'Inter',
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // "Find Jobs" — pixel-matched to Stitch's artisan home headline
            // (previously "Hello, {name}"). The greeting/category subtitle
            // is dropped since Stitch's reference doesn't show one here —
            // same trade this app made on the Customer Home screen.
            Expanded(
              child: Text(
                'Find Jobs',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  color: context.colors.textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.swap_horiz_rounded,
                  color: context.colors.textSecondary, size: 20),
              tooltip: 'Switch to Customer View',
              onPressed: () =>
                  ref.read(authServiceProvider).updateUserProfile(
                userId,
                {
                  'roles': FieldValue.arrayUnion(['customer']),
                  'activeRole': 'customer',
                },
              ),
            ),
            const NotificationBell(),
            IconButton(
              icon: Icon(Icons.logout_outlined,
                  color: context.colors.textSecondary, size: 20),
              onPressed: () =>
                  ref.read(authNotifierProvider.notifier).signOut(),
            ),
          ],
        ),
      );

  Widget _buildPendingBanner(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.warningSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
              color: context.colors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top_rounded,
                color: context.colors.warning, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your profile is under review (24–48 hours).',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textPrimary,
                  fontFamily: 'Inter',
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildAvailabilityToggle(
          BuildContext context, WidgetRef ref) =>
      Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: artisan.isAvailable
                    ? context.colors.primary
                    : context.colors.textTertiary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                artisan.isAvailable
                    ? 'Available for new jobs'
                    : 'Not accepting new jobs',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: artisan.isAvailable
                      ? context.colors.primary
                      : context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            Switch(
              value: artisan.isAvailable,
              onChanged: (val) =>
                  _toggleAvailability(context, ref, artisan.isAvailable),
              activeThumbColor: context.colors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      );

  Widget _buildVerificationCard(BuildContext context, WidgetRef ref) {
    final verificationAsync =
        ref.watch(verificationStatusProvider(userId));

    return verificationAsync.when(
      loading: () => const SizedBox(),
      error: (e, st) => const SizedBox(),
      data: (verification) {
        final spec = _verificationSpec(context, verification);

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: spec.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
                color: spec.color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(spec.icon, color: spec.color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      spec.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              if (spec.actionLabel != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => context.push('/verification'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: spec.color.withValues(alpha: 0.15),
                      borderRadius:
                          BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      spec.actionLabel!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: spec.color,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  _VerificationSpec _verificationSpec(
    BuildContext context,
    VerificationModel? verification,
  ) =>
      switch (verification?.status) {
        null => _VerificationSpec(
            icon: Icons.verified_user_outlined,
            color: context.colors.warning,
            surface: context.colors.warningSurface,
            title: 'Verify Your Identity',
            subtitle:
                'Upload selfie + ID to earn the Verified badge.',
            actionLabel: 'Verify',
          ),
        VerificationStatus.pendingLater => _VerificationSpec(
            icon: Icons.schedule_outlined,
            color: context.colors.warning,
            surface: context.colors.warningSurface,
            title: 'Verification Deferred',
            subtitle: 'Verify anytime to unlock quoting.',
            actionLabel: 'Verify Now',
          ),
        VerificationStatus.pending => _VerificationSpec(
            icon: Icons.hourglass_top_rounded,
            color: context.colors.primary,
            surface: context.colors.primarySurface,
            title: 'Verification Under Review',
            subtitle: 'Documents being reviewed (24–48 hours).',
          ),
        VerificationStatus.approved => _VerificationSpec(
            icon: Icons.verified_rounded,
            color: context.colors.primary,
            surface: context.colors.primarySurface,
            title: 'Identity Verified ✓',
            subtitle: 'You appear with the Verified badge.',
          ),
        VerificationStatus.rejected => _VerificationSpec(
            icon: Icons.cancel_outlined,
            color: context.colors.error,
            surface: context.colors.errorSurface,
            title: 'Verification Rejected',
            subtitle: verification?.rejectionReason?.isNotEmpty == true
                ? verification!.rejectionReason!
                : 'Please resubmit with clearer photos.',
            actionLabel: 'Resubmit',
          ),
      };

  Widget _buildStatsRow(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            _StatCard(
              label: 'Rating',
              value: artisan.rating == 0
                  ? 'New'
                  : artisan.rating.toStringAsFixed(1),
              icon: Icons.star_rounded,
              color: context.colors.ratingGold,
            ),
            const SizedBox(width: 10),
            _StatCard(
              label: 'Completed',
              value: '${artisan.completedJobs}',
              icon: Icons.check_circle_outline_rounded,
              color: context.colors.primary,
            ),
            const SizedBox(width: 10),
            _StatCard(
              label: 'Trust Score',
              value: '${artisan.trustScore.toInt()}',
              icon: Icons.verified_outlined,
              color: context.colors.accent,
              onTap: () => showTrustScoreSheet(context, artisan),
            ),
          ],
        ),
      );

  Widget _buildQuickActions(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.work_outline_rounded,
                    label: 'Browse Open Jobs',
                    primary: true,
                    onTap: () => context.push(
                      '/open-jobs',
                      extra: {'category': artisan.category ?? ''},
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'My Chats',
                    primary: false,
                    onTap: () => context.push('/my-chats'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.account_balance_outlined,
                    label: 'Payout Details',
                    primary: false,
                    onTap: () => context.push('/bank-details'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Portfolio',
                    primary: false,
                    onTap: () => context.push('/portfolio'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _ActionButton(
                icon: Icons.storefront_outlined,
                label: 'Business Profile',
                primary: false,
                onTap: () => context.push('/business-profile'),
              ),
            ),
          ],
        ),
      );

  Widget _buildJobsSection(
    BuildContext context,
    AsyncValue<List<JobModel>> jobsAsync,
  ) =>
      jobsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: JobListSkeleton(),
        ),
        error: (e, st) => const SizedBox(),
        data: (jobs) {
          final active =
              jobs.where((j) => !j.status.isTerminal).toList();
          final recent = jobs
              .where((j) => j.status.isTerminal)
              .take(5)
              .toList();

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (active.isNotEmpty) ...[
                  Text(
                    'Active Jobs (${active.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                      color: context.colors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...active.map((j) => _ArtisanJobTile(job: j)),
                  const SizedBox(height: 20),
                ],
                if (recent.isNotEmpty) ...[
                  Text(
                    'Recent Jobs',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                      color: context.colors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...recent.map((j) => _ArtisanJobTile(job: j)),
                ],
                if (jobs.isEmpty) _emptyState(context),
              ],
            ),
          );
        },
      );

  Widget _emptyState(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          children: [
            Icon(Icons.work_outline_rounded,
                size: 48, color: context.colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No jobs yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Once your profile is approved, customers will find you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

class _VerificationSpec {
  final IconData icon;
  final Color color;
  final Color surface;
  final String title;
  final String subtitle;
  final String? actionLabel;

  const _VerificationSpec({
    required this.icon,
    required this.color,
    required this.surface,
    required this.title,
    required this.subtitle,
    this.actionLabel,
  });
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.colors.border),
            ),
            child: Column(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.textTertiary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary
        ? context.colors.primary
        : context.colors.surface;
    final fg = primary ? Colors.white : context.colors.textPrimary;
    final borderColor =
        primary ? context.colors.primary : context.colors.border;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: borderColor),
          boxShadow: primary ? AppShadows.button : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
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
}

class _ArtisanJobTile extends StatelessWidget {
  final JobModel job;

  const _ArtisanJobTile({required this.job});

  @override
  Widget build(BuildContext context) {
    // Phase comes from WorkflowGateService, not a raw job.status label —
    // same decision Home and My Bookings read for the customer side.
    final step = WorkflowGateService.describeStep(job, viewerIsCustomer: false);
    final needsAction = step.primaryAction != WorkflowAction.none;

    return GestureDetector(
        onTap: () => context.push('/job/${job.id}'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.colors.primarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(Icons.build_circle_outlined,
                    color: context.colors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.category,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        fontFamily: 'Inter',
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      job.description.length > 55
                          ? '${job.description.substring(0, 55)}…'
                          : job.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd MMM yyyy').format(job.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textTertiary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 6),
                    WorkflowTimeline(job: job, compact: true),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AppBadge(
                label: step.phase,
                color: needsAction ? context.colors.primary : context.colors.textSecondary,
                backgroundColor:
                    needsAction ? context.colors.primarySurface : context.colors.surfaceVariant,
              ),
            ],
          ),
        ),
      );
  }
}
