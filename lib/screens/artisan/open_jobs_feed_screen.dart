import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/services/artisan_eligibility.dart';
import '../../core/services/distance_matching.dart';
import '../../models/job_model.dart';
import '../../models/quote_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/quote_provider.dart';
import '../../providers/platform_config_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/error_snackbar.dart';
import '../../widgets/pill_tab_selector.dart';

/// Artisan-side Open Jobs Feed — browse jobs still in 'requested' status
/// within the artisan's own category and submit a quote.
class OpenJobsFeedScreen extends ConsumerStatefulWidget {
  final String category;

  const OpenJobsFeedScreen({super.key, required this.category});

  @override
  ConsumerState<OpenJobsFeedScreen> createState() => _OpenJobsFeedScreenState();
}

class _OpenJobsFeedScreenState extends ConsumerState<OpenJobsFeedScreen> {
  final _searchCtrl = TextEditingController();
  int _filterIndex = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleAvailability(String artisanId, bool current) async {
    final firestore = FirebaseFirestore.instance;
    try {
      final batch = firestore.batch();
      batch.set(firestore.collection('artisans').doc(artisanId),
          {'isAvailable': !current}, SetOptions(merge: true));
      batch.set(firestore.collection('users').doc(artisanId),
          {'isAvailable': !current}, SetOptions(merge: true));
      await batch.commit();
    } catch (e) {
      if (mounted) {
        showErrorSnackbar(context, 'Could not update availability: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(openJobsFeedProvider(widget.category));
    final userAsync = ref.watch(currentUserProfileProvider);
    final artisanId = userAsync.value?.uid;
    final artisan = artisanId != null
        ? ref.watch(artisanProfileProvider(artisanId)).value
        : null;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(
          widget.category.isEmpty ? 'Open Jobs' : widget.category,
          style: const TextStyle(
              fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.borderLight),
        ),
      ),
      body: jobsAsync.when(
        loading: () => _FeedLoadingSkeleton(),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 48, color: context.colors.error),
                const SizedBox(height: 12),
                Text(
                  '$e',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter'),
                ),
              ],
            ),
          ),
        ),
        data: (jobs) {
          if (artisanId == null) return const SizedBox.shrink();

          final query = _searchCtrl.text.trim().toLowerCase();
          var filtered = query.isEmpty
              ? jobs
              : jobs
                  .where((j) =>
                      j.category.toLowerCase().contains(query) ||
                      j.description.toLowerCase().contains(query))
                  .toList();
          // Stage 6 (D8): distance-first — jobs within the artisan's own
          // service radius, nearest first; jobs without an area last. Without
          // a service area set, the feed is unchanged (category-wide).
          filtered = DistanceMatching.filterJobsForArtisan(
            filtered,
            artisan,
            defaultRadiusKm: ref.watch(platformConfigProvider).defaultServiceRadiusKm,
          );
          filtered = switch (_filterIndex) {
            1 => filtered.where((j) =>
                DateTime.now().difference(j.createdAt) < const Duration(hours: 48)).toList(),
            2 => filtered.where((j) => j.urgency == 'asap').toList(),
            _ => filtered,
          };

          final resultsArea = jobs.isEmpty
              ? _EmptyFeed(category: widget.category)
              : filtered.isEmpty
                  ? _NoMatchesState(onClear: () {
                      setState(() {
                        _searchCtrl.clear();
                        _filterIndex = 0;
                      });
                    })
                  : _JobResultsGrid(jobs: filtered, artisanId: artisanId);

          if (!context.isDesktop) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _FeedSearchBar(controller: _searchCtrl, onChanged: (_) => setState(() {})),
                ),
                if (artisan != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: _ReadyToWorkToggle(
                      available: artisan.isAvailable,
                      onChanged: () => _toggleAvailability(artisanId, artisan.isAvailable),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: PillTabSelector(
                    tabs: const [
                      PillTabItem('All Matched'),
                      PillTabItem('Recent'),
                      PillTabItem('Urgent'),
                    ],
                    selectedIndex: _filterIndex,
                    onChanged: (i) => setState(() => _filterIndex = i),
                  ),
                ),
                Expanded(child: resultsArea),
              ],
            );
          }

          // Desktop: left filter panel + main results area. No Category/
          // Location/Budget filters here — this screen is already scoped
          // to one category via the route (widget.category), and there is
          // no existing location/budget query dimension in
          // openJobsFeedProvider to filter against; adding those controls
          // without real filtering behind them would be exactly the "fake
          // feature" this task rules out. Status (All Matched/Recent/
          // Urgent) and search are real, existing, working filters.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 260,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filters',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                          color: context.colors.textTertiary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FeedSearchBar(controller: _searchCtrl, onChanged: (_) => setState(() {})),
                      if (artisan != null) ...[
                        const SizedBox(height: 12),
                        _ReadyToWorkToggle(
                          available: artisan.isAvailable,
                          onChanged: () => _toggleAvailability(artisanId, artisan.isAvailable),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        'Status',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                          color: context.colors.textTertiary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final (i, label) in const ['All Matched', 'Recent', 'Urgent'].indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _FilterListTile(
                            label: label,
                            selected: _filterIndex == i,
                            onTap: () => setState(() => _filterIndex = i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              VerticalDivider(width: 1, color: context.colors.borderLight),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: resultsArea,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Single-column ListView on mobile, 2-column grid on desktop — same
/// variable-height Wrap technique as My Bookings' desktop grid, since
/// _OpenJobCard's height depends on its content (description length,
/// number of chips, eligibility banner presence).
class _JobResultsGrid extends StatelessWidget {
  final List<JobModel> jobs;
  final String artisanId;

  const _JobResultsGrid({required this.jobs, required this.artisanId});

  static Widget _heading(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
        child: Text(
          'Matched Job Opportunities',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontFamily: 'Inter',
            color: context.colors.textPrimary,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!context.isDesktop) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: jobs.length + 1,
        separatorBuilder: (_, i) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => i == 0
            ? _heading(context)
            : _OpenJobCard(job: jobs[i - 1], artisanId: artisanId),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final columnWidth = (constraints.maxWidth - spacing) / 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(context),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final j in jobs)
                    SizedBox(width: columnWidth, child: _OpenJobCard(job: j, artisanId: artisanId)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterListTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterListTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.colors.primarySurface : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontFamily: 'Inter',
              color: selected ? context.colors.primary : context.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _FeedSearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: context.colors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search tasks, locations…',
          hintStyle: TextStyle(color: context.colors.textTertiary, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: context.colors.textTertiary, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: context.colors.textTertiary),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

/// Same isAvailable field the Dashboard's own toggle writes — surfaced
/// here too since Stitch's Find Jobs feed puts it directly above the job
/// list, not just on the Dashboard.
class _ReadyToWorkToggle extends StatelessWidget {
  final bool available;
  final VoidCallback onChanged;

  const _ReadyToWorkToggle({required this.available, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: appCardDecoration(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              available ? 'Ready to work!' : 'Not accepting new jobs',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
                color: available ? context.colors.primary : context.colors.textSecondary,
              ),
            ),
          ),
          Switch(
            value: available,
            onChanged: (_) => onChanged(),
            activeThumbColor: context.colors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _NoMatchesState extends StatelessWidget {
  final VoidCallback onClear;
  const _NoMatchesState({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 44, color: context.colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No jobs match your search',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onClear, child: const Text('Clear filters')),
          ],
        ),
      ),
    );
  }
}

class _OpenJobCard extends ConsumerWidget {
  final JobModel job;
  final String artisanId;

  const _OpenJobCard({required this.job, required this.artisanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myQuoteAsync = ref.watch(
      artisanQuoteForJobProvider(ArtisanJobQuoteKey(job.id, artisanId)),
    );
    final myQuote = myQuoteAsync.value;
    final hasActiveQuote =
        myQuote != null && (myQuote.status == QuoteStatus.pending);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ROOT CAUSE FIX: firestore.rules' isArtisanEligible() requires BOTH
    // approvalStatus == 'approved' AND verificationStatus in
    // ['id_verified','trusted'] to create/edit a quote — but this card
    // previously showed "I'm Interested" fully enabled regardless of
    // either, for every artisan who can see the open feed at all (which
    // is deliberately broader — any registered artisan, per the rules'
    // own read scope). An ineligible artisan could fill out the entire
    // quote form and only then get an opaque Firestore permission-denied
    // exception. Computed here, live, so the button re-enables
    // automatically the moment an admin approves them — no refresh needed.
    final artisanAsync = ref.watch(artisanProfileProvider(artisanId));
    final artisan = artisanAsync.value;
    final notApproved = artisan != null && artisan.approvalStatus != 'approved';
    // ArtisanEligibility.canQuote mirrors firestore.rules' isArtisanEligible()
    // — includes the betaTester bypass (design/BETA_TESTING_GUIDE.md) for
    // admin-flagged test accounts, without requiring real verification.
    final notVerified = artisan != null && !notApproved && !ArtisanEligibility.canQuote(artisan);
    final ineligibleReason = notApproved
        ? "Your artisan profile is still awaiting admin approval — you'll be able to quote once it's approved."
        : notVerified
            ? 'Your artisan profile must be verified before you can submit quotes.'
            : null;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: hasActiveQuote
              ? context.colors.primary.withValues(alpha: 0.4)
              : context.colors.border,
          width: hasActiveQuote ? 1.5 : 1,
        ),
        boxShadow: isDark ? AppShadows.cardDark : AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo hero — matches the Stitch "Find Jobs" reference's
          // category-tag/urgency-tag overlay on a photo. Falls back to a
          // solid category-tinted panel with a centered icon when the job
          // has no uploaded photos (real data either way, no placeholder
          // stock image).
          Stack(
            children: [
              if (job.imageUrls.isNotEmpty)
                Image.network(
                  job.imageUrls.first,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _photoFallback(context),
                )
              else
                _photoFallback(context),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: context.colors.ink,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    job.category,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.colors.onInk,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ),
              if (job.urgency == 'asap')
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: context.colors.error,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_fire_department_rounded, size: 12, color: Colors.white),
                        SizedBox(width: 3),
                        Text('Urgent',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'Inter')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Description
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              job.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Budget + location row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (job.budgetMin != null || job.budgetMax != null)
                  _InfoChip(
                    icon: Icons.payments_outlined,
                    label:
                        '₦${_fmt(job.budgetMin ?? 0)} – ₦${_fmt(job.budgetMax ?? job.budgetMin ?? 0)}',
                    color: context.colors.primary,
                    bgColor: context.colors.primarySurface,
                  ),
                if (job.customerAddress != null)
                  _InfoChip(
                    icon: Icons.location_on_outlined,
                    label: job.customerAddress!,
                    color: context.colors.textSecondary,
                    bgColor: context.colors.surfaceVariant,
                    maxWidth: 160,
                  ),
              ],
            ),
          ),
          // Eligibility banner — shown instead of letting the artisan fill
          // out and submit a quote that would then fail with an opaque
          // Firestore permission error (the root cause of "cannot submit
          // quotes"). Only shown when they don't already have an active
          // quote, since editing an existing one is a separate action.
          if (!hasActiveQuote && ineligibleReason != null) ...[
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.warningSurface,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: context.colors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ineligibleReason,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.colors.warning,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Quote status banner
          if (hasActiveQuote) ...[
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.primarySurface,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      size: 14, color: context.colors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      myQuote.materialsCost > 0
                          ? 'Labour ₦${_fmt(myQuote.laborCost)} + Materials ₦${_fmt(myQuote.materialsCost)} = ₦${_fmt(myQuote.amount)} · ${myQuote.durationDays}d'
                          : 'Your quote: ₦${_fmt(myQuote.amount)} · ${myQuote.durationDays}d',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.colors.primary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Divider + action row
          Divider(
              height: 1,
              color: context.colors.borderLight,
              indent: 16,
              endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                // Chat button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openChat(context, ref),
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        size: 15),
                    label: const Text('Chat'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.textSecondary,
                      side: BorderSide(color: context.colors.border),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Quote button
                Expanded(
                  child: hasActiveQuote
                      ? OutlinedButton.icon(
                          onPressed: () =>
                              _openQuoteSheet(context, ref, existing: myQuote),
                          icon:
                              const Icon(Icons.edit_outlined, size: 15),
                          label: const Text('Edit Quote'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.primary,
                            side: BorderSide(
                                color: context.colors.primary
                                    .withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Inter',
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                        )
                      // Black pill — matches the Stitch "Find Jobs"
                      // reference's "Interested" button treatment.
                      : ElevatedButton.icon(
                          onPressed: ineligibleReason != null
                              ? null
                              : () => _openQuoteSheet(context, ref,
                                  existing: null),
                          icon: const Icon(Icons.thumb_up_alt_outlined,
                              size: 15),
                          label: const Text('Interested'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.ink,
                            disabledBackgroundColor: context.colors.ink.withValues(alpha: 0.4),
                            foregroundColor: context.colors.onInk,
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Inter',
                            ),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoFallback(BuildContext context) => Container(
        height: 120,
        width: double.infinity,
        color: context.colors.primarySurface,
        child: Icon(Icons.work_outline_rounded, size: 32, color: context.colors.primary),
      );

  String _fmt(double v) => NumberFormat('#,##0').format(v);

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    try {
      final chatId = await ref.read(chatServiceProvider).getOrCreateJobChat(
            jobId: job.id,
            customerId: job.customerId,
            artisanId: artisanId,
          );
      if (!context.mounted) return;
      context.push(
        '/chat/$chatId',
        extra: {'artisanId': job.customerId, 'artisanName': 'Customer'},
      );
    } catch (e) {
      debugPrint(
          '[OpenJobsFeed] getOrCreateJobChat failed for job ${job.id}: $e');
      if (context.mounted) {
        showErrorSnackbar(context, 'Could not open chat: $e');
      }
    }
  }

  void _openQuoteSheet(
    BuildContext context,
    WidgetRef ref, {
    QuoteModel? existing,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubmitQuoteSheet(
        jobId: job.id,
        artisanId: artisanId,
        existing: existing,
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final double? maxWidth;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: maxWidth != null
          ? BoxConstraints(maxWidth: maxWidth!)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
                fontFamily: 'Inter',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmitQuoteSheet extends ConsumerStatefulWidget {
  final String jobId;
  final String artisanId;
  final QuoteModel? existing;

  const _SubmitQuoteSheet({
    required this.jobId,
    required this.artisanId,
    this.existing,
  });

  @override
  ConsumerState<_SubmitQuoteSheet> createState() => _SubmitQuoteSheetState();
}

class _SubmitQuoteSheetState extends ConsumerState<_SubmitQuoteSheet> {
  late final _laborController = TextEditingController(
    text: widget.existing?.laborCost.toStringAsFixed(0) ?? '',
  );
  late final _materialsController = TextEditingController(
    text: widget.existing != null && widget.existing!.materialsCost > 0
        ? widget.existing!.materialsCost.toStringAsFixed(0)
        : '',
  );
  late final _durationController = TextEditingController(
    text: widget.existing?.durationDays.toString() ?? '1',
  );
  late final _notesController = TextEditingController(
    text: widget.existing?.notes ?? '',
  );
  bool _submitting = false;
  bool _withdrawing = false;

  double get _laborCost =>
      double.tryParse(_laborController.text.trim()) ?? 0.0;
  double get _materialsCost =>
      double.tryParse(_materialsController.text.trim()) ?? 0.0;
  double get _total => _laborCost + _materialsCost;

  @override
  void initState() {
    super.initState();
    _laborController.addListener(() => setState(() {}));
    _materialsController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _laborController.dispose();
    _materialsController.dispose();
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final laborCost = double.tryParse(_laborController.text.trim());
    final duration = int.tryParse(_durationController.text.trim());
    if (laborCost == null || laborCost <= 0) {
      showErrorSnackbar(context, 'Enter a valid labour cost.');
      return;
    }
    if (duration == null || duration <= 0) {
      showErrorSnackbar(context, 'Enter a valid duration in days.');
      return;
    }
    final materialsCost =
        double.tryParse(_materialsController.text.trim()) ?? 0.0;
    // Policy D1 (also enforced by firestore.rules on the quote write).
    final config = ref.read(platformConfigProvider);
    if (!config.meetsMinimum(laborCost + materialsCost)) {
      showErrorSnackbar(context,
          'Quotes must total at least ${config.minJobValueLabel} (the minimum job value for secure payment).');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(quoteServiceProvider).submitQuote(
            jobId: widget.jobId,
            artisanId: widget.artisanId,
            laborCost: laborCost,
            materialsCost: materialsCost,
            durationDays: duration,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // The eligibility gate above should prevent most cases of this ever
      // firing, but a moment-of-write race (e.g. approval status changes
      // between load and submit) can still hit the same rules check —
      // surface something the artisan can actually act on, not a raw
      // Firestore exception string.
      if (mounted) {
        showErrorSnackbar(context, _friendlySubmitError(e));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendlySubmitError(Object e) {
    final message = e.toString();
    if (message.contains('permission-denied') ||
        message.contains('PERMISSION_DENIED')) {
      return "You're not eligible to quote on this job right now — your "
          'profile may need admin approval or identity verification first.';
    }
    if (message.contains('network')) {
      return 'No internet connection. Please check your network and try again.';
    }
    return 'Could not submit quote. Please try again.';
  }

  Future<void> _withdraw() async {
    setState(() => _withdrawing = true);
    try {
      await ref.read(quoteServiceProvider).withdrawQuote(
            jobId: widget.jobId,
            artisanId: widget.artisanId,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not withdraw quote: $e');
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 18),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              isEdit ? 'Edit Your Quote' : 'Submit a Quote',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isEdit
                  ? 'Update your price or timeline.'
                  : 'Set your price and estimated timeline.',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 20),
            _SheetField(
              controller: _laborController,
              label: 'Labour / Service Cost',
              prefix: '₦',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            _SheetField(
              controller: _materialsController,
              label: 'Materials Cost (optional)',
              prefix: '₦',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            if (_total > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: context.colors.primarySurface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Quote',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.colors.primary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    Text(
                      '₦${NumberFormat('#,##0').format(_total)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.colors.primary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _SheetField(
              controller: _durationController,
              label: 'Estimated Duration (days)',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _SheetField(
              controller: _notesController,
              label: 'Notes (optional)',
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting || _withdrawing ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isEdit ? 'Update Quote' : 'Submit Quote'),
              ),
            ),
            if (isEdit) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: _submitting || _withdrawing ? null : _withdraw,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.error,
                    side: BorderSide(color: context.colors.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    ),
                  ),
                  child: _withdrawing
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.error,
                          ),
                        )
                      : const Text('Withdraw Quote'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? prefix;
  final TextInputType? keyboardType;
  final int? maxLines;

  const _SheetField({
    required this.controller,
    required this.label,
    this.prefix,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: 1,
      maxLines: maxLines,
      style: TextStyle(
        color: context.colors.textPrimary,
        fontFamily: 'Inter',
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        filled: true,
        fillColor: context.colors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: context.colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: context.colors.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(
            color: context.colors.textSecondary, fontFamily: 'Inter'),
        alignLabelWithHint: true,
      ),
    );
  }
}

class _FeedLoadingSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: 4,
      separatorBuilder: (_, i) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) => Container(
        height: 160,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: context.colors.borderLight),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.colors.shimmerBase,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 13,
                  width: 100,
                  decoration: BoxDecoration(
                    color: context.colors.shimmerBase,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: context.colors.shimmerBase,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 10,
              width: 200,
              decoration: BoxDecoration(
                color: context.colors.shimmerBase,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.colors.shimmerBase,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.colors.shimmerBase,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  final String category;

  const _EmptyFeed({required this.category});

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
              child: Icon(Icons.work_off_outlined,
                  size: 40, color: context.colors.textTertiary),
            ),
            const SizedBox(height: 20),
            Text(
              'No open jobs right now',
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
                  ? 'New job requests will appear here.'
                  : 'No open $category jobs right now.\nNew requests will appear here.',
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
