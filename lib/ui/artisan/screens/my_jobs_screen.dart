import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/artisan_work_logic.dart';
import '../../../models/job_model.dart';
import '../../../providers/escrow_provider.dart';
import '../../../providers/platform_config_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_format.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';
import 'work_ui.dart';

final myJobsFilterProvider = StateProvider<ArtisanPipeline?>((ref) => null);
final _historyProvider = StateProvider<bool>((ref) => false);

/// AR-03 My Jobs: stage chips, stage-grouped work-order tickets; stage
/// columns on wide screens (tablet board).
class MyJobsScreen extends ConsumerWidget {
  const MyJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = ref.watch(artisanContextProvider).asData?.value;
    if (ctx == null) return const Column(children: [ArtisanTabHeader(), Expanded(child: ArtisanState.loading())]);
    final jobsAsync = ref.watch(artisanJobsProvider(ctx.uid));
    final pipeline = ref.watch(myJobsFilterProvider);
    final history = ref.watch(_historyProvider);
    final cfg = ref.watch(platformConfigProvider);
    final now = clock.now();

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      return jobsAsync.when(
        loading: () => _frame(context, ref, const [], pipeline, history, child: const _LoadingSkeleton()),
        error: (e, _) => _frame(context, ref, const [], pipeline, history, child: ArtisanState.error(e, onRetry: () => ref.invalidate(artisanJobsProvider(ctx.uid)))),
        data: (jobs) {
          final active = jobs.where(ArtisanWorkLogic.isActive).toList();
          final done = jobs.where(ArtisanWorkLogic.isHistory).toList()..sort((a, b) => (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));
          if (wide && !history && pipeline == null) {
            return Column(children: [
              const ArtisanTabHeader(title: 'My Jobs'),
              _chips(context, ref, jobs, pipeline, history),
              Expanded(child: _Board(jobs: active, bookingHours: cfg.bookingConfirmationHours, now: now)),
            ]);
          }
          final shown = history ? done : (pipeline == null ? active : active.where((j) => ArtisanWorkLogic.pipelineOf(j) == pipeline).toList());
          final groups = history ? [('History', shown)] : ArtisanWorkLogic.groupForMyJobs(shown);
          return _frame(context, ref, jobs, pipeline, history,
              child: shown.isEmpty
                  ? HtCard(
                      child: HtEmptyView(
                        icon: Icons.assignment_outlined,
                        title: history ? 'No finished jobs yet' : 'No jobs here',
                        message: history ? 'Completed and closed jobs appear here.' : 'Quote on matched jobs in Find Work to get booked.',
                        action: history ? null : HtSmallPrimaryButton(label: 'Find Work', onPressed: () => ref.read(artisanTabProvider.notifier).state = ArtisanTab.findWork),
                      ),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final (label, list) in groups) ...[
                        ProSection(label, count: list.length),
                        for (final j in list) _ticket(context, j, cfg.bookingConfirmationHours, now),
                      ],
                    ]));
        },
      );
    });
  }

  Widget _chips(BuildContext context, WidgetRef ref, List<JobModel> jobs, ArtisanPipeline? pipeline, bool history) {
    final counts = ArtisanWorkLogic.pipelineCounts(jobs);
    final activeCount = jobs.where(ArtisanWorkLogic.isActive).length;
    final doneCount = jobs.where(ArtisanWorkLogic.isHistory).length;
    void set(ArtisanPipeline? p, bool h) {
      ref.read(myJobsFilterProvider.notifier).state = p;
      ref.read(_historyProvider.notifier).state = h;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 4, HtSpace.gutter, 4),
      child: Row(children: [
        HtChip(label: 'Active', count: activeCount, selected: pipeline == null && !history, onTap: () => set(null, false)),
        for (final s in ArtisanPipeline.values) ...[
          const SizedBox(width: 8),
          HtChip(label: ArtisanWorkLogic.pipelineLabel(s), count: counts[s], selected: pipeline == s && !history, onTap: () => set(s, false)),
        ],
        const SizedBox(width: 8),
        HtChip(label: 'History', count: doneCount, selected: history, onTap: () => set(null, true)),
      ]),
    );
  }

  Widget _frame(BuildContext context, WidgetRef ref, List<JobModel> jobs, ArtisanPipeline? pipeline, bool history, {required Widget child}) {
    return Column(children: [
      const ArtisanTabHeader(),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 28),
          children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: HtSpace.gutter), child: proTitle(context, 'My Jobs')),
            const SizedBox(height: 12),
            _chips(context, ref, jobs, pipeline, history),
            Padding(padding: const EdgeInsets.symmetric(horizontal: HtSpace.gutter), child: child),
          ],
        ),
      ),
    ]);
  }
}

Widget _ticket(BuildContext context, JobModel j, int bookingHours, DateTime now, {bool compact = false}) {
  final stage = ArtisanWorkLogic.stageOf(j);
  final (day, month) = ticketDate(j);
  final amount = j.agreedAmount != null ? HtFormat.naira(j.agreedAmount) : null;
  final chatOpen = stage != ArtisanStage.request && stage != ArtisanStage.closed && j.status != JobStatus.matched;
  return ProTicket(
    day: day,
    month: month,
    title: workTitle(j),
    meta: '${jobArea(j)} · #${HtFormat.bookingRef(j.id)}',
    stage: ArtisanWorkLogic.stageLabel(j),
    stageTone: stageTone(stage),
    deadline: ticketDeadline(j, bookingHours, now),
    amount: compact ? null : amount,
    action: compact ? null : ticketAction(j),
    icon: categoryIcon(j.category),
    compact: compact,
    onTap: () => context.push('/job/${j.id}'),
    onChat: compact || !chatOpen ? null : () => context.push('/chat/${j.id}'),
  );
}

class _Board extends StatelessWidget {
  const _Board({required this.jobs, required this.bookingHours, required this.now});
  final List<JobModel> jobs;
  final int bookingHours;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    // Pipeline columns, plus Disputed when there is one (same jobs as the
    // phone list's groups).
    final disputed = jobs.where((j) => ArtisanWorkLogic.stageOf(j) == ArtisanStage.disputed).toList();
    final columns = <(String, List<JobModel>)>[
      for (final s in ArtisanPipeline.values) (ArtisanWorkLogic.pipelineLabel(s), jobs.where((j) => ArtisanWorkLogic.pipelineOf(j) == s).toList()),
      if (disputed.isNotEmpty) ('Disputed', disputed),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 8, 8, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (label, list) in columns)
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.isDark ? p.backgroundDeep : p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.border)),
              child: Builder(builder: (context) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Flexible(child: Text(label.toUpperCase(), style: HtType.caps(p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    Text('${list.length}', style: HtType.smallStrong(p.textMuted)),
                  ]),
                  const SizedBox(height: 10),
                  Expanded(
                    child: list.isEmpty
                        ? Text('Nothing here', style: HtType.small(p.textMuted))
                        : ListView(children: [for (final j in list) _ticket(context, j, bookingHours, now, compact: true)]),
                  ),
                ]);
              }),
            ),
          ),
      ]),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    Widget bone(double h, {double? w}) => Container(height: h, width: w, margin: const EdgeInsets.only(bottom: 12, top: 4), decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.tile + 2)));
    return Semantics(
      label: 'Loading your jobs',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        bone(112),
        bone(112),
        bone(112),
        Center(child: Text('Loading your jobs…', style: HtType.small(p.textMuted))),
      ]),
    );
  }
}
