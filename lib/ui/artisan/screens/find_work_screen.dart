import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/artisan_eligibility.dart';
import '../../../core/services/artisan_profile_service.dart';
import '../../../core/services/distance_matching.dart';
import '../../../core/utils/geo.dart';
import '../../../models/artisan_model.dart';
import '../../../models/job_model.dart';
import '../../../models/quote_model.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/platform_config_provider.dart';
import '../../../providers/quote_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_format.dart';
import '../../components/ht_kit.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';
import 'quote_composer_screen.dart';
import 'work_ui.dart';

final _findWorkSegmentProvider = StateProvider<int>((ref) => 0);
final _statusFilterProvider = StateProvider<int>((ref) => 0);

/// Why an artisan can't quote yet (mirrors firestore.rules' isArtisanEligible
/// via ArtisanEligibility), or null when eligible.
String? quoteBlockReason(ArtisanModel? a) {
  if (a == null) return null;
  if (a.approvalStatus != 'approved') return 'Your artisan profile is awaiting HandyTrust approval. You can quote once it’s approved.';
  if (!ArtisanEligibility.canQuote(a)) return 'Verify your identity before you can submit quotes.';
  return null;
}

String budgetLabel(JobModel j) {
  final lo = j.budgetMin, hi = j.budgetMax;
  if (lo == null && hi == null) return 'No budget given';
  if (lo != null && hi != null && lo != hi) return '${HtFormat.naira(lo)} – ${HtFormat.naira(hi)}';
  return HtFormat.naira(lo ?? hi);
}

String? distanceLabel(JobModel j, ArtisanModel? a) {
  if (a?.latitude == null || a?.longitude == null || j.areaLat == null || j.areaLng == null) return null;
  final d = Geo.distanceKm(j.areaLat!, j.areaLng!, a!.latitude!, a.longitude!);
  return '${d.toStringAsFixed(d < 10 ? 1 : 0)} km';
}

/// AR-02 Find Work: matched open jobs (job board) and the artisan's quotes
/// on those jobs.
class FindWorkScreen extends ConsumerStatefulWidget {
  const FindWorkScreen({super.key});
  @override
  ConsumerState<FindWorkScreen> createState() => _FindWorkScreenState();
}

class _FindWorkScreenState extends ConsumerState<FindWorkScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final ctx = ref.watch(artisanContextProvider).asData?.value;
    if (ctx == null) return const Column(children: [ArtisanTabHeader(), Expanded(child: ArtisanState.loading())]);
    final artisan = ctx.artisan;
    final category = artisan?.category ?? ctx.user.category ?? '';
    final cfg = ref.watch(platformConfigProvider);
    final segment = ref.watch(_findWorkSegmentProvider);
    final status = ref.watch(_statusFilterProvider);
    final feedAsync = ref.watch(openJobsFeedProvider(category));
    final blocked = quoteBlockReason(artisan);

    final header = <Widget>[
      Row(children: [
        Expanded(child: proTitle(context, 'Find Work')),
        if (artisan != null) _AvailabilityChip(artisan: artisan),
      ]),
      const SizedBox(height: 12),
      ProSegments(labels: const ['Open jobs', 'My quotes'], selected: segment, onSelected: (i) => ref.read(_findWorkSegmentProvider.notifier).state = i),
      if (blocked != null) ...[
        const SizedBox(height: 12),
        HtInfoBanner(icon: Icons.verified_user_outlined, tone: HtTone.warning, text: blocked, trailing: artisan?.approvalStatus == 'approved' ? HtSmallPrimaryButton(label: 'Verify', onPressed: () => context.push('/verification')) : null),
      ],
    ];

    if (category.isEmpty) {
      return ArtisanTabBody(children: [
        ...header,
        const SizedBox(height: 20),
        HtCard(child: HtEmptyView(icon: Icons.category_outlined, title: 'Choose your trade', message: 'Set your service category to see matched jobs.', action: HtSmallPrimaryButton(label: 'Set up profile', onPressed: () => context.push('/register/artisan')))),
      ]);
    }

    return feedAsync.when(
      loading: () => ArtisanTabBody(children: [...header, const SizedBox(height: 40), const HtLoadingView(label: 'Finding matched jobs…')]),
      error: (e, _) => ArtisanTabBody(children: [...header, const SizedBox(height: 24), ArtisanState.error(e, onRetry: () => ref.invalidate(openJobsFeedProvider(category)))]),
      data: (jobs) {
        // Same matching as before: distance-first within the service radius.
        final matched = DistanceMatching.filterJobsForArtisan(jobs, artisan, defaultRadiusKm: cfg.defaultServiceRadiusKm);
        if (segment == 1) {
          return ArtisanTabBody(children: [...header, _MyQuotes(jobs: matched, artisanId: ctx.uid)]);
        }
        final q = _search.text.trim().toLowerCase();
        var shown = q.isEmpty ? matched : matched.where((j) => j.category.toLowerCase().contains(q) || j.description.toLowerCase().contains(q)).toList();
        shown = switch (status) {
          1 => shown.where((j) => clock.now().difference(j.createdAt) < const Duration(hours: 48)).toList(),
          2 => shown.where((j) => j.urgency == 'asap').toList(),
          _ => shown,
        };
        final radius = artisan == null ? cfg.defaultServiceRadiusKm : DistanceMatching.radiusFor(artisan, cfg.defaultServiceRadiusKm);
        return ArtisanTabBody(
          onRefresh: () async => ref.invalidate(openJobsFeedProvider(category)),
          children: [
            ...header,
            const SizedBox(height: 12),
            HtSearchField(controller: _search, hint: 'Search tasks, locations…', onChanged: (_) => setState(() {})),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (i, c) in const ['All Matched', 'Recent', 'Urgent'].indexed) ...[
                  HtChip(label: c, selected: i == status, onTap: () => ref.read(_statusFilterProvider.notifier).state = i),
                  const SizedBox(width: 8),
                ],
              ]),
            ),
            const SizedBox(height: 6),
            Text(artisan?.latitude == null ? 'Matched to $category · set your service area for distance matching' : 'Matched to $category within ${radius.round()} km',
                style: HtType.small(p.textMuted)),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: HtCard(
                  child: HtEmptyView(
                    icon: Icons.travel_explore_outlined,
                    title: matched.isEmpty ? 'No open jobs right now' : 'No jobs match these filters',
                    message: matched.isEmpty ? 'New $category jobs near you appear here.' : 'Try clearing the search or filters.',
                    action: matched.isEmpty
                        ? null
                        : HtSecondaryButton(
                            label: 'Clear filters',
                            onPressed: () {
                              _search.clear();
                              ref.read(_statusFilterProvider.notifier).state = 0;
                              setState(() {});
                            },
                          ),
                  ),
                ),
              )
            else
              for (final j in shown) _BoardRow(job: j, artisan: artisan, artisanId: ctx.uid, blockedReason: blocked),
          ],
        );
      },
    );
  }
}

class _AvailabilityChip extends ConsumerStatefulWidget {
  const _AvailabilityChip({required this.artisan});
  final ArtisanModel artisan;
  @override
  ConsumerState<_AvailabilityChip> createState() => _AvailabilityChipState();
}

class _AvailabilityChipState extends ConsumerState<_AvailabilityChip> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final on = widget.artisan.isAvailable;
    return Semantics(
      button: true,
      toggled: on,
      label: 'Ready to work',
      child: InkWell(
        borderRadius: BorderRadius.circular(HtRadius.pill),
        onTap: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  await ref.read(artisanProfileServiceProvider).setAvailability(widget.artisan.uid, !on);
                } catch (_) {
                  if (context.mounted) htSnack(context, 'Could not update availability. Please try again.', error: true);
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        child: HtStatusPill(label: _busy ? 'Updating…' : (on ? 'Ready to work' : 'Not accepting jobs'), tone: on ? HtTone.success : HtTone.neutral, dot: true),
      ),
    );
  }
}

Future<void> openJobChat(BuildContext context, WidgetRef ref, JobModel job, String artisanId) async {
  try {
    final chatId = await ref.read(chatServiceProvider).getOrCreateJobChat(jobId: job.id, customerId: job.customerId, artisanId: artisanId);
    if (!context.mounted) return;
    context.push('/chat/$chatId', extra: {'artisanId': job.customerId, 'artisanName': 'Customer'});
  } catch (_) {
    if (context.mounted) htSnack(context, 'Could not open the chat. Please try again.', error: true);
  }
}

class _BoardRow extends ConsumerWidget {
  const _BoardRow({required this.job, required this.artisan, required this.artisanId, required this.blockedReason});
  final JobModel job;
  final ArtisanModel? artisan;
  final String artisanId;
  final String? blockedReason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final quote = ref.watch(artisanQuoteForJobProvider(ArtisanJobQuoteKey(job.id, artisanId))).asData?.value;
    final pending = quote != null && quote.status == QuoteStatus.pending;
    final dist = distanceLabel(job, artisan);
    final meta = [if (job.areaLabel != null) job.areaLabel!, ?dist, 'posted ${HtFormat.timeAgo(job.createdAt)}'].join(' · ');

    void compose() {
      if (blockedReason != null) {
        htSnack(context, blockedReason!, error: true);
        return;
      }
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => QuoteComposerScreen(job: job, artisanId: artisanId, existing: pending ? quote : null)));
    }

    return InkWell(
      onTap: compose,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          htIconTile(context, categoryIcon(job.category), size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(workTitle(job), style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (job.urgency == 'asap') ...[const SizedBox(width: 6), Icon(Icons.bolt_rounded, size: 15, color: p.warning), Text('Urgent', style: HtType.smallStrong(p.warning).copyWith(fontSize: 11.5))],
              ]),
              Text(meta, style: HtType.small(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Text(budgetLabel(job), style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(
                  tooltip: 'Chat with the customer',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => openJobChat(context, ref, job, artisanId),
                  icon: Icon(Icons.chat_bubble_outline_rounded, size: 19, color: p.textSecondary),
                ),
                const SizedBox(width: 4),
                if (pending)
                  HtStatusPill(label: 'Quoted ${HtFormat.naira(quote.laborCost + quote.materialsCost)}', tone: HtTone.accent, dot: true)
                else
                  Opacity(
                    opacity: blockedReason == null ? 1 : 0.5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(color: proAccent(p), borderRadius: BorderRadius.circular(HtRadius.pill)),
                      child: Text('Quote', style: HtType.smallStrong(proOnAccent(p))),
                    ),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// My quotes: the artisan's quotes on jobs still open in their matches
/// (read per job; there is no cross-job quote query in the backend).
class _MyQuotes extends ConsumerWidget {
  const _MyQuotes({required this.jobs, required this.artisanId});
  final List<JobModel> jobs;
  final String artisanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final entries = <(JobModel, QuoteModel)>[];
    var loading = false;
    for (final j in jobs) {
      final a = ref.watch(artisanQuoteForJobProvider(ArtisanJobQuoteKey(j.id, artisanId)));
      if (a.isLoading) loading = true;
      final q = a.asData?.value;
      if (q != null) entries.add((j, q));
    }
    final waiting = entries.where((e) => e.$2.status == QuoteStatus.pending).toList();
    final closed = entries.where((e) => e.$2.status != QuoteStatus.pending).toList();
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: loading
            ? const HtLoadingView(label: 'Loading your quotes…')
            : HtCard(child: HtEmptyView(icon: Icons.request_quote_outlined, title: 'No quotes yet', message: 'Quotes you send on open jobs appear here.')),
      );
    }
    Widget row((JobModel, QuoteModel) e) {
      final (j, q) = e;
      final isPending = q.status == QuoteStatus.pending;
      final (label, tone) = switch (q.status) {
        QuoteStatus.pending => ('Pending', HtTone.warning),
        QuoteStatus.accepted => ('Accepted', HtTone.success),
        QuoteStatus.rejected => ('Declined', HtTone.neutral),
        QuoteStatus.withdrawn => ('Withdrawn', HtTone.neutral),
        QuoteStatus.expired => ('Expired', HtTone.neutral),
        QuoteStatus.closed => ('Closed', HtTone.neutral),
      };
      return HtCard(
        radius: HtRadius.tile + 2,
        padding: const EdgeInsets.all(14),
        onTap: isPending ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => QuoteComposerScreen(job: j, artisanId: artisanId, existing: q))) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(workTitle(j), style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)), HtStatusPill(label: label, tone: tone, dot: true)]),
          Text([j.areaLabel ?? j.category, if ((q.updatedAt ?? q.createdAt) != null) 'sent ${HtFormat.timeAgo((q.updatedAt ?? q.createdAt)!)}'].join(' · '), style: HtType.small(p.textSecondary)),
          const SizedBox(height: 10),
          Row(children: [
            Text(HtFormat.naira(q.laborCost + q.materialsCost), style: HtType.amount(p.textPrimary, size: 18)),
            const SizedBox(width: 8),
            Text('${q.durationDays} ${q.durationDays == 1 ? 'day' : 'days'}', style: HtType.small(p.textMuted)),
            const Spacer(),
            if (isPending) Text('Edit or withdraw', style: HtType.smallStrong(proAccent(p))),
          ]),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (waiting.isNotEmpty) ...[ProSection('Waiting for the customer', count: waiting.length), for (final e in waiting) Padding(padding: const EdgeInsets.only(bottom: 10), child: row(e))],
      if (closed.isNotEmpty) ...[const ProSection('Closed'), for (final e in closed) Padding(padding: const EdgeInsets.only(bottom: 10), child: row(e))],
      const SizedBox(height: 6),
      const HtInfoBanner(icon: Icons.info_outline_rounded, tone: HtTone.neutral, text: 'Shows your quotes on jobs still open in your matches. Accepted quotes become bookings in My Jobs.'),
    ]);
  }
}
