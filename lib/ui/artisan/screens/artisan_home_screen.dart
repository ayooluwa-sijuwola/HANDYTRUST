import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/artisan_earnings_summary.dart';
import '../../../core/services/artisan_eligibility.dart';
import '../../../core/services/artisan_profile_service.dart';
import '../../../core/services/artisan_work_logic.dart';
import '../../../core/services/trust_score_service.dart';
import '../../../models/artisan_model.dart';
import '../../../models/job_model.dart';
import '../../../providers/artisan_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/escrow_provider.dart';
import '../../../providers/payment_provider.dart';
import '../../../providers/platform_config_provider.dart';
import '../../../providers/verification_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_format.dart';
import '../../components/ht_kit.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';
import 'my_jobs_screen.dart';
import 'work_ui.dart';

/// AR-01 Artisan Home: availability, setup steps, action queue, work
/// pipeline, next appointment, this month, trust score.
class ArtisanHomeScreen extends ConsumerWidget {
  const ArtisanHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctxAsync = ref.watch(artisanContextProvider);
    return ctxAsync.when(
      loading: () => const Column(children: [ArtisanTabHeader(), Expanded(child: ArtisanState.loading(label: 'Loading your work…'))]),
      error: (e, _) => Column(children: [const ArtisanTabHeader(), ArtisanState.error(e, onRetry: () => ref.invalidate(currentUserProfileProvider))]),
      data: (ctx) {
        if (ctx == null) return const SizedBox.shrink();
        return _HomeBody(ctx: ctx);
      },
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.ctx});
  final ArtisanContext ctx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final cfg = ref.watch(platformConfigProvider);
    final jobsAsync = ref.watch(artisanJobsProvider(ctx.uid));
    final payments = ref.watch(artisanPaymentsProvider(ctx.uid)).asData?.value ?? const [];
    final payoutReady = ref.watch(artisanPayoutReadyProvider(ctx.uid)).asData?.value;
    final artisan = ctx.artisan;
    final now = clock.now();
    final jobs = jobsAsync.asData?.value ?? const <JobModel>[];
    final queue = ArtisanWorkLogic.actionQueue(jobs, bookingConfirmationHours: cfg.bookingConfirmationHours);
    final counts = ArtisanWorkLogic.pipelineCounts(jobs);
    final next = ArtisanWorkLogic.nextAppointment(jobs, now);
    final summary = ArtisanEarningsSummary.of(payments, {for (final j in jobs) j.id: j}, now);
    final eligible = artisan != null && ArtisanEligibility.canQuote(artisan);
    final radius = artisan?.serviceRadiusKm ?? cfg.defaultServiceRadiusKm;
    final area = HtFormat.area(artisan?.serviceAddress);

    void openTab(ArtisanTab t) => ref.read(artisanTabProvider.notifier).state = t;

    return ArtisanTabBody(
      onRefresh: () async => ref.invalidate(artisanJobsProvider(ctx.uid)),
      children: [
        if (artisan != null) _AvailabilityCard(artisan: artisan, radiusKm: radius, area: area),
        if (artisan != null && (!eligible || payoutReady == false)) ...[
          const SizedBox(height: 14),
          _SetupSteps(artisan: artisan, payoutReady: payoutReady ?? false),
        ],
        ProSection('Needs your action', count: queue.length + (payoutReady == false ? 1 : 0)),
        if (jobsAsync.isLoading && jobs.isEmpty)
          const HtLoadingView(label: 'Checking your jobs…')
        else if (jobsAsync.hasError)
          ArtisanState.error(jobsAsync.error, onRetry: () => ref.invalidate(artisanJobsProvider(ctx.uid)))
        else ...[
          for (final a in queue.take(5)) _queueCard(context, a, now),
          if (payoutReady == false)
            ProActionCard(
              tone: HtTone.warning,
              icon: Icons.account_balance_outlined,
              title: 'Add payout details',
              subtitle: 'Released payments need your bank account',
              action: 'Add',
              onTap: () => context.push('/bank-details'),
            ),
          if (queue.isEmpty && payoutReady != false)
            HtCard(
              radius: HtRadius.inner,
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                htIconTile(context, Icons.check_circle_outline_rounded, tone: HtTone.success, size: 38),
                const SizedBox(width: 12),
                Expanded(child: Text('You’re all caught up. New requests and updates appear here.', style: HtType.small(p.textSecondary))),
              ]),
            ),
        ],
        ProSection('Work pipeline', trailing: 'My Jobs', onTrailing: () => openTab(ArtisanTab.myJobs)),
        ProPipeline(
          stages: [for (final s in ArtisanPipeline.values) (ArtisanWorkLogic.pipelineLabel(s), counts[s] ?? 0)],
          onTap: (i) {
            ref.read(myJobsFilterProvider.notifier).state = ArtisanPipeline.values[i];
            openTab(ArtisanTab.myJobs);
          },
        ),
        if (next != null) ...[
          const ProSection('Next appointment'),
          _AppointmentCard(job: next),
        ],
        ProSection('This month', trailing: 'Earnings', onTrailing: () => openTab(ArtisanTab.earnings)),
        Row(children: [
          Expanded(
            child: ProStat(
              icon: Icons.south_west_rounded,
              label: 'Released to you',
              value: HtFormat.naira(summary.releasedThisMonth),
              sub: '${summary.releasedThisMonthJobs} ${summary.releasedThisMonthJobs == 1 ? 'job' : 'jobs'}',
              onTap: () => openTab(ArtisanTab.earnings),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ProStat(
              icon: Icons.lock_outline_rounded,
              label: 'In escrow',
              value: HtFormat.naira(summary.inEscrow + summary.awaitingRelease),
              sub: 'Held until approval',
              onTap: () => openTab(ArtisanTab.earnings),
            ),
          ),
        ]),
        if (artisan != null) ...[
          const SizedBox(height: 10),
          _TrustCard(artisan: artisan),
        ],
      ],
    );
  }

  Widget _queueCard(BuildContext context, ArtisanAction a, DateTime now) {
    final j = a.job;
    final title = workTitle(j);
    final ref = '#${HtFormat.bookingRef(j.id)}';
    void open() => context.push('/job/${j.id}');
    switch (a.kind) {
      case ArtisanActionKind.respondToBooking:
        final left = a.deadline == null ? null : ArtisanWorkLogic.remainingLabel(a.deadline!, now);
        return ProActionCard(
          tone: HtTone.danger,
          icon: Icons.mark_email_unread_outlined,
          title: 'Booking request · $title',
          subtitle: [if (j.areaLabel != null) j.areaLabel!, if (j.agreedAmount != null) HtFormat.naira(j.agreedAmount)].join(' · '),
          deadline: left == null ? 'Response window ended' : 'Respond within $left',
          action: 'Respond',
          onTap: open,
        );
      case ArtisanActionKind.reviewAgreement:
        return ProActionCard(tone: HtTone.warning, icon: Icons.handshake_outlined, title: 'Review the agreement', subtitle: '$title · $ref', action: 'Review', onTap: open);
      case ArtisanActionKind.proposeTimes:
        return ProActionCard(tone: HtTone.accent, icon: Icons.event_available_outlined, title: 'Propose appointment times', subtitle: 'Agreement confirmed · $ref', action: 'Schedule', onTap: open);
      case ArtisanActionKind.startWork:
        return ProActionCard(tone: HtTone.success, icon: Icons.play_circle_outline_rounded, title: 'Escrow funded — start work', subtitle: '$title · $ref', action: 'Start', onTap: open);
      case ArtisanActionKind.respondToRework:
        return ProActionCard(tone: HtTone.warning, icon: Icons.replay_rounded, title: 'Rework requested', subtitle: j.reworkReason == null ? '$title · $ref' : '“${j.reworkReason}”', action: 'Respond', onTap: open);
      case ArtisanActionKind.respondToDispute:
        return ProActionCard(tone: HtTone.danger, icon: Icons.gavel_rounded, title: 'Dispute · $title', subtitle: 'Escrow on hold · $ref', action: 'Open', onTap: open);
    }
  }
}

class _AvailabilityCard extends ConsumerStatefulWidget {
  const _AvailabilityCard({required this.artisan, required this.radiusKm, required this.area});
  final ArtisanModel artisan;
  final double radiusKm;
  final String? area;
  @override
  ConsumerState<_AvailabilityCard> createState() => _AvailabilityCardState();
}

class _AvailabilityCardState extends ConsumerState<_AvailabilityCard> {
  bool _busy = false;

  Future<void> _toggle(bool v) async {
    setState(() => _busy = true);
    try {
      await ref.read(artisanProfileServiceProvider).setAvailability(widget.artisan.uid, v);
    } catch (e) {
      if (mounted) htSnack(context, 'Could not update availability. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final on = widget.artisan.isAvailable;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: p.isDark ? [const Color(0xFF2A3315), p.surface] : [p.accentSoft, p.surface], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(HtRadius.inner),
        border: Border.all(color: p.border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(on ? 'Ready to work' : 'Not accepting jobs', style: HtType.sectionTitle(p.textPrimary)),
            Text(
              on
                  ? 'Matching jobs within ${widget.radiusKm.round()} km${widget.area != null ? ' of ${widget.area}' : ''}'
                  : 'Turn on to appear in matches and quote',
              style: HtType.small(p.textSecondary),
            ),
          ]),
        ),
        if (_busy)
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: proAccent(p)))
        else
          Semantics(
            label: 'Ready to work',
            toggled: on,
            child: Switch(value: on, onChanged: _toggle, activeThumbColor: proOnAccent(p), activeTrackColor: proAccent(p)),
          ),
      ]),
    );
  }
}

class _SetupSteps extends ConsumerWidget {
  const _SetupSteps({required this.artisan, required this.payoutReady});
  final ArtisanModel artisan;
  final bool payoutReady;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final verification = ref.watch(verificationStatusProvider(artisan.uid)).asData?.value;
    final approved = artisan.approvalStatus == 'approved';
    final verified = ArtisanEligibility.isReallyVerified(artisan);
    final submitted = verification != null && verification.governmentIdUrl.isNotEmpty;
    Widget step(String t, String s, int state, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: state == 2 ? p.success : (state == 1 ? p.warningSoft : p.surfaceRaised), shape: BoxShape.circle),
                child: Icon(state == 2 ? Icons.check_rounded : (state == 1 ? Icons.hourglass_top_rounded : Icons.circle_outlined), size: 16, color: state == 2 ? Colors.white : (state == 1 ? p.warning : p.textMuted)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5)), Text(s, style: HtType.small(p.textSecondary))])),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: p.textMuted),
            ]),
          ),
        );
    return HtCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Get ready to quote', style: HtType.cardTitle(p.textPrimary)),
        Text('Finish these steps to appear in matches.', style: HtType.small(p.textSecondary)),
        const SizedBox(height: 10),
        step('Profile review', approved ? 'Approved by HandyTrust' : 'Awaiting HandyTrust approval', approved ? 2 : 1),
        step('Identity verification', verified ? 'Verified' : (submitted ? 'Documents under review' : 'Upload your ID and a selfie'), verified ? 2 : (submitted ? 1 : 0),
            onTap: verified ? null : () => context.push('/verification')),
        step('Payout account', payoutReady ? 'Bank account on file' : 'Add the bank account for payouts', payoutReady ? 2 : 0, onTap: payoutReady ? null : () => context.push('/bank-details')),
        step('Ready to work', artisan.isAvailable ? 'On' : 'Turn on above when you’re available', artisan.isAvailable ? 2 : 0),
      ]),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.job});
  final JobModel job;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final at = job.confirmedAppointment!.toLocal();
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return HtCard(
      radius: HtRadius.inner,
      padding: const EdgeInsets.all(14),
      onTap: () => context.push('/job/${job.id}'),
      child: Row(children: [
        Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: proAccent(p), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(days[at.weekday - 1], style: HtType.caps(proOnAccent(p)).copyWith(fontSize: 10)),
            Text('${at.day}', style: HtType.amount(proOnAccent(p), size: 22)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${HtFormat.clock(at)} · ${workTitle(job)}', style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(job.areaLabel ?? job.category, style: HtType.small(p.textSecondary)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: p.textMuted),
      ]),
    );
  }
}

class _TrustCard extends StatelessWidget {
  const _TrustCard({required this.artisan});
  final ArtisanModel artisan;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final parts = TrustScoreService.breakdown(artisan)..sort((a, b) => (b.score / b.maxScore).compareTo(a.score / a.maxScore));
    final score = artisan.trustScore.clamp(0, 100).toDouble();
    return HtCard(
      radius: HtRadius.inner,
      padding: const EdgeInsets.all(14),
      onTap: () => showTrustBreakdown(context, artisan),
      child: Row(children: [
        ProCountdownRing(fraction: score / 100, big: score.round().toString(), small: 'Trust', size: 70, tone: HtTone.success),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${TrustScoreService.tierLabel(score)} artisan', style: HtType.bodyStrong(p.textPrimary)),
            if (parts.length >= 2) Text('Strongest: ${parts[0].label} · ${parts[1].label}', style: HtType.small(p.textSecondary)),
            const SizedBox(height: 4),
            Text('See breakdown', style: HtType.smallStrong(proAccent(p))),
          ]),
        ),
      ]),
    );
  }
}

/// Trust-score breakdown sheet (OV-15).
Future<void> showTrustBreakdown(BuildContext context, ArtisanModel artisan) {
  final p = context.ht;
  final score = artisan.trustScore.clamp(0, 100).toDouble();
  return htShowSheet<void>(context, builder: (ctx) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('TRUSTSCORE', style: HtType.caps(p.textMuted)),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${score.round()}', style: HtType.amount(p.textPrimary, size: 40)),
        const SizedBox(width: 6),
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('/100 · ${TrustScoreService.tierLabel(score)}', style: HtType.bodyStrong(p.textSecondary))),
      ]),
      const SizedBox(height: 16),
      for (final c in TrustScoreService.breakdown(artisan))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(c.label, style: HtType.smallStrong(p.textPrimary))),
              Text('${(c.maxScore <= 0 ? 0 : c.score / c.maxScore * 100).round()}%', style: HtType.smallStrong(p.textSecondary)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: c.maxScore <= 0 ? 0 : (c.score / c.maxScore).clamp(0, 1), minHeight: 8, color: proChartColors(p).first, backgroundColor: p.surfaceRaised),
            ),
          ]),
        ),
      Text('A higher score leads to more visibility in search results.', style: HtType.small(p.textSecondary)),
    ]);
  });
}
