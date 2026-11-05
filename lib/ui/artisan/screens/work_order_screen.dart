import 'package:clock/clock.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/artisan_work_logic.dart';
import '../../../core/services/workflow_gate_service.dart';
import '../../../models/audit_log_model.dart';
import '../../../models/dispute_model.dart';
import '../../../models/job_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/dispute_provider.dart';
import '../../../providers/escrow_provider.dart';
import '../../../providers/platform_config_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_format.dart';
import '../../components/ht_kit.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';
import 'work_ui.dart';

/// Runs an escrow-notifier action and reports failure (the notifier stores
/// errors in its AsyncValue instead of throwing). Returns true on success.
Future<bool> runWorkAction(BuildContext context, WidgetRef ref, Future<void> Function() action, {required String failure}) async {
  await action();
  if (!context.mounted) return false;
  final s = ref.read(escrowNotifierProvider);
  if (s.hasError) {
    htSnack(context, failure, error: true);
    return false;
  }
  return true;
}

/// Reason picker sheet (decline / withdraw / cancellation request).
Future<String?> pickReason(BuildContext context, {required String title, required String message, required String confirm}) {
  final p = context.ht;
  var selected = ArtisanWorkLogic.artisanReasons.first;
  return htShowSheet<String>(context, builder: (ctx) {
    return StatefulBuilder(builder: (ctx, setState) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: HtType.sectionTitle(p.textPrimary)),
        const SizedBox(height: 6),
        Text(message, style: HtType.small(p.textSecondary)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in ArtisanWorkLogic.artisanReasons) HtChip(label: r, selected: r == selected, onTap: () => setState(() => selected = r)),
        ]),
        const SizedBox(height: 18),
        HtDangerButton(label: confirm, onPressed: () => Navigator.of(ctx).pop(selected)),
        const SizedBox(height: 6),
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Keep job', style: HtType.bodyStrong(p.textSecondary))),
      ]);
    });
  });
}

/// Free-text sheet (agreement change request).
Future<String?> askText(BuildContext context, {required String title, required String label, required String confirm}) {
  final p = context.ht;
  final c = TextEditingController();
  return htShowSheet<String>(context, builder: (ctx) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: HtType.sectionTitle(p.textPrimary)),
      HtTextField(label: label, controller: c, lines: 3, maxLength: 500),
      const SizedBox(height: 16),
      HtPrimaryButton(
        label: confirm,
        onPressed: () {
          final t = c.text.trim();
          if (t.isNotEmpty) Navigator.of(ctx).pop(t);
        },
      ),
    ]);
  }).whenComplete(c.dispose);
}

/// `/job/:jobId` for the job's artisan: the work order.
class WorkOrderScreen extends ConsumerWidget {
  const WorkOrderScreen({super.key, required this.job});
  final JobModel job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ArtisanWorkLogic.stageOf(job);
    return switch (stage) {
      ArtisanStage.request => _BookingRequest(job: job),
      ArtisanStage.disputed => _DisputeView(job: job),
      _ => _WorkOrder(job: job),
    };
  }
}

void _openChat(BuildContext context, JobModel job) => context.push('/chat/${job.id}', extra: {'artisanId': job.customerId, 'artisanName': 'Customer'});

// ─── Booking request ────────────────────────────────────────────────────────

class _BookingRequest extends ConsumerWidget {
  const _BookingRequest({required this.job});
  final JobModel job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final cfg = ref.watch(platformConfigProvider);
    final now = clock.now();
    final deadline = ArtisanWorkLogic.bookingDeadline(job, cfg.bookingConfirmationHours);
    final started = job.bookingRequestedAt ?? job.matchedAt;
    final left = deadline == null ? null : ArtisanWorkLogic.remainingLabel(deadline, now);
    final fraction = deadline == null || started == null ? 0.0 : ArtisanWorkLogic.remainingFraction(started, deadline, now);
    final loading = ref.watch(escrowNotifierProvider).isLoading;

    Future<void> decline() async {
      final reason = await pickReason(context, title: 'Decline booking', message: 'The job reopens so the customer can book another artisan.', confirm: 'Decline booking');
      if (reason == null || !context.mounted) return;
      final ok = await runWorkAction(context, ref, () => ref.read(escrowNotifierProvider.notifier).withdrawFromJob(job.id, reason: reason), failure: 'Could not decline. Please try again.');
      if (ok && context.mounted) context.go('/home');
    }

    Future<void> accept() async {
      final ok = await runWorkAction(context, ref, () => ref.read(escrowNotifierProvider.notifier).confirmBooking(job.id), failure: 'Could not accept the booking. Please try again.');
      if (ok && context.mounted) htSnack(context, 'Booking accepted. The customer will send the agreement.');
    }

    return ArtisanPage(
      title: 'Booking request',
      sub: 'Job #${HtFormat.bookingRef(job.id)}',
      bottomBar: Container(
        padding: EdgeInsets.fromLTRB(HtSpace.gutter, 12, HtSpace.gutter, 12 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
        child: Row(children: [
          Expanded(child: HtSecondaryButton(label: 'Decline', height: 52, onPressed: loading ? null : decline)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: HtPrimaryButton(label: 'Accept booking', loading: loading, onPressed: left == null ? null : accept)),
        ]),
      ),
      children: [
        HtCard(
          child: Row(children: [
            ProCountdownRing(fraction: fraction, big: left ?? '0 h', small: left == null ? 'window ended' : 'to respond', size: 104, tone: HtTone.danger),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('A customer wants to book you', style: HtType.cardTitle(p.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  left == null
                      ? 'The response window has ended. The job is being reopened for other artisans.'
                      : 'Respond within ${cfg.bookingConfirmationHours} hours of the request. If you don’t, the job reopens for other artisans.',
                  style: HtType.small(p.textSecondary),
                ),
              ]),
            ),
          ]),
        ),
        const ProSection('The job'),
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(job.description, style: HtType.bodyStrong(p.textPrimary)),
            const SizedBox(height: 6),
            htKv(context, 'Category', job.category),
            if (job.areaLabel != null) htKv(context, 'Area', job.areaLabel!),
            htKv(context, 'Preferred date', job.urgency == 'asap' || job.scheduledDate == null ? 'As soon as possible' : HtFormat.date(job.scheduledDate!.toLocal())),
            if (job.agreedAmount != null) htKv(context, 'Accepted quote', HtFormat.naira(job.agreedAmount), strong: true),
            if (job.imageUrls.isNotEmpty) ...[const SizedBox(height: 8), HtPhotoGrid(urls: job.imageUrls, tileHeight: 74)],
          ]),
        ),
        const SizedBox(height: 12),
        const HtInfoBanner(icon: Icons.handshake_outlined, text: 'Accepting starts the agreement step. Nothing is charged until the customer funds escrow.'),
      ],
    );
  }
}

// ─── Work order (tabs) ──────────────────────────────────────────────────────

class _WorkOrder extends ConsumerStatefulWidget {
  const _WorkOrder({required this.job});
  final JobModel job;
  @override
  ConsumerState<_WorkOrder> createState() => _WorkOrderState();
}

class _WorkOrderState extends ConsumerState<_WorkOrder> {
  int _tab = 0;

  List<String> get _tabs => ['Overview', 'Agreement', if (widget.job.urgency == 'scheduled') 'Schedule', 'Photos', 'Activity'];

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final stage = ArtisanWorkLogic.stageOf(job);
    final loading = ref.watch(escrowNotifierProvider).isLoading;
    final tab = _tab.clamp(0, _tabs.length - 1);
    final tabName = _tabs[tab];

    Widget? bar;
    switch (stage) {
      case ArtisanStage.readyToStart:
        bar = ProActionBar(
          label: 'Start work',
          loading: loading,
          onChat: () => _openChat(context, job),
          onPressed: () async {
            final ok = await runWorkAction(context, ref, () => ref.read(escrowNotifierProvider.notifier).startWork(job.id), failure: 'Could not start the job. Please try again.');
            if (ok && context.mounted) htSnack(context, 'Work started.');
          },
        );
      case ArtisanStage.working:
      case ArtisanStage.rework:
        bar = ProActionBar(label: stage == ArtisanStage.rework ? 'Resubmit work' : 'Submit work', onChat: () => _openChat(context, job), onPressed: () => context.push('/job/${job.id}/submit'));
      case ArtisanStage.agreement when job.agreementStatus == AgreementStatus.pendingArtisanConfirmation:
        bar = ProActionBar(label: 'Review agreement', onChat: () => _openChat(context, job), onPressed: () => setState(() => _tab = 1));
      default:
        bar = job.status == JobStatus.matched || stage == ArtisanStage.completed || stage == ArtisanStage.closed
            ? null
            : ProActionBar(label: 'Open chat', onPressed: () => _openChat(context, job));
    }

    return ArtisanPage(
      title: 'Work order',
      sub: '${ArtisanWorkLogic.stageLabel(job)} · #${HtFormat.bookingRef(job.id)}',
      onChat: job.status == JobStatus.matched ? null : () => _openChat(context, job),
      bottomBar: bar,
      children: [
        _WorkOrderTop(job: job),
        const SizedBox(height: 10),
        ProTabs(labels: _tabs, selected: tab, onSelected: (i) => setState(() => _tab = i)),
        const SizedBox(height: 4),
        switch (tabName) {
          'Agreement' => _AgreementTab(job: job),
          'Schedule' => _ScheduleTab(job: job),
          'Photos' => _PhotosTab(job: job),
          'Activity' => _ActivityTab(job: job),
          _ => _OverviewTab(job: job),
        },
      ],
    );
  }
}

class _WorkOrderTop extends StatelessWidget {
  const _WorkOrderTop({required this.job});
  final JobModel job;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    // These states are only reachable once escrow is funded (server state
    // machine); escrowLockedAt is the server's own record of it.
    const fundedStates = {JobStatus.escrowLocked, JobStatus.inProgress, JobStatus.submitted, JobStatus.disputed};
    final funded = fundedStates.contains(job.status) || (job.escrowLockedAt != null && job.status != JobStatus.cancelled);
    final (pill, tone) = switch (job.status) {
      JobStatus.completed || JobStatus.resolved => ('Released', HtTone.success),
      _ when funded => ('In escrow', HtTone.warning),
      _ => ('Not funded yet', HtTone.neutral),
    };
    return HtCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('WORK ORDER · #${HtFormat.bookingRef(job.id)}', style: HtType.caps(p.textMuted).copyWith(fontSize: 10.5))),
          HtStatusPill(label: pill, tone: tone, icon: Icons.lock_outline_rounded),
        ]),
        const SizedBox(height: 6),
        Text(workTitle(job), style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 22)),
        Text('${job.category}${job.areaLabel != null ? ' · ${job.areaLabel}' : ''}', style: HtType.small(p.textSecondary)),
        if (job.agreedAmount != null) ...[
          const SizedBox(height: 8),
          Row(children: [Text(HtFormat.naira(job.agreedAmount), style: HtType.amount(p.textPrimary, size: 20)), const SizedBox(width: 8), Flexible(child: Text('agreed · paid to you in full', style: HtType.small(p.textMuted)))]),
        ],
        const SizedBox(height: 14),
        ProWorkStepper(current: ArtisanWorkLogic.workStep(job), labels: ArtisanWorkLogic.workStepLabels),
      ]),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.job});
  final JobModel job;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final stage = ArtisanWorkLogic.stageOf(job);
    final step = WorkflowGateService.describeStep(job, viewerIsCustomer: false);
    final loading = ref.watch(escrowNotifierProvider).isLoading;
    final privateLoc = ref.watch(jobPrivateLocationProvider(job.id)).asData?.value;
    final address = (privateLoc?['customerAddress'] as String?) ?? job.customerAddress;
    final now = clock.now();

    final children = <Widget>[
      if (step.description.isNotEmpty) ...[
        const ProSection('Now'),
        HtCard(radius: HtRadius.inner, padding: const EdgeInsets.all(14), child: Text(step.description, style: HtType.body(p.textPrimary).copyWith(fontSize: 13.5))),
      ],
    ];

    if (stage == ArtisanStage.rework) children.add(_ReworkCard(job: job));

    if (stage == ArtisanStage.working || stage == ArtisanStage.rework) {
      final current = job.progressStage;
      final next = ArtisanWorkLogic.nextProgress(current);
      final idx = current == null ? -1 : JobProgressStage.values.indexOf(current);
      children.addAll([
        const ProSection('Progress'),
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ProProgressMeter(index: idx, labels: [for (final s in JobProgressStage.values) s.label]),
            const SizedBox(height: 14),
            if (next != null)
              HtSecondaryButton(
                label: 'Mark: ${next.label}',
                icon: Icons.trending_up_rounded,
                onPressed: loading
                    ? null
                    : () => runWorkAction(context, ref, () => ref.read(escrowNotifierProvider.notifier).updateProgress(job.id, next), failure: 'Could not update progress. Please try again.'),
              )
            else
              Text('All stages done. Submit the work when ready.', style: HtType.small(p.textSecondary)),
          ]),
        ),
      ]);
    }

    if (stage == ArtisanStage.inReview) {
      final end = job.autoReleaseAt;
      final start = job.submittedAt;
      final left = end == null ? null : ArtisanWorkLogic.remainingLabel(end, now);
      children.addAll([
        const ProSection('Customer review'),
        HtCard(
          child: Row(children: [
            ProCountdownRing(
              fraction: end == null || start == null ? 0 : ArtisanWorkLogic.remainingFraction(start, end, now),
              big: left ?? '—',
              small: 'left',
              size: 104,
              tone: HtTone.accent,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(end == null ? 'Waiting for the customer' : 'Payment releases on ${HtFormat.date(end.toLocal())}', style: HtType.cardTitle(p.textPrimary)),
                const SizedBox(height: 4),
                Text('Or sooner if the customer approves. Before then they can ask for one rework or raise a dispute.', style: HtType.small(p.textSecondary)),
              ]),
            ),
          ]),
        ),
      ]);
    }

    if (stage == ArtisanStage.completed) {
      children.addAll([
        const ProSection('Payout'),
        HtCard(
          radius: HtRadius.inner,
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            if (job.agreedAmount != null) htKv(context, 'Agreed price', HtFormat.naira(job.agreedAmount), strong: true),
            htKv(context, 'Payout status', switch (job.payoutStatus) { 'paid' => 'Paid', 'processing' => 'Processing', 'delayed' => 'Delayed', 'on_hold' => 'On hold', _ => 'Released' }),
            if (job.completedAt != null) htKv(context, 'Completed', HtFormat.date(job.completedAt!.toLocal())),
          ]),
        ),
      ]);
    }

    if (job.confirmedAppointment != null) {
      children.addAll([
        const ProSection('Appointment'),
        HtCard(radius: HtRadius.inner, padding: const EdgeInsets.all(14), child: htKv(context, 'Confirmed', HtFormat.dateTime(job.confirmedAppointment!.toLocal()), strong: true)),
      ]);
    }

    final revealed = job.status != JobStatus.matched && job.status != JobStatus.requested && job.status != JobStatus.cancelled && job.status != JobStatus.expired;
    children.addAll([
      const ProSection('Location'),
      HtCard(
        radius: HtRadius.inner,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(Icons.place_outlined, color: proAccent(p)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              revealed && address != null ? address : '${job.areaLabel ?? job.category} (the exact address is shared once the booking is confirmed)',
              style: HtType.small(p.textPrimary).copyWith(fontSize: 13),
            ),
          ),
        ]),
      ),
    ]);

    if (job.hasPendingCancellationRequest) {
      children.addAll([const SizedBox(height: 14), const HtInfoBanner(icon: Icons.hourglass_top_rounded, tone: HtTone.neutral, text: 'Cancellation requested — HandyTrust is reviewing it. The payment stays in escrow until a decision is made.')]);
    } else if (ArtisanWorkLogic.canWithdraw(job) && job.status != JobStatus.matched) {
      children.addAll([
        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: loading
                ? null
                : () async {
                    final reason = await pickReason(context,
                        title: 'Withdraw from job',
                        message: 'The job reopens so the customer can book another artisan. Withdrawing from a confirmed booking counts towards your cancellation rate.',
                        confirm: 'Withdraw');
                    if (reason == null || !context.mounted) return;
                    final ok = await runWorkAction(context, ref, () => ref.read(escrowNotifierProvider.notifier).withdrawFromJob(job.id, reason: reason), failure: 'Could not withdraw. Please try again.');
                    if (ok && context.mounted) context.go('/home');
                  },
            child: Text('Withdraw from job', style: HtType.smallStrong(p.danger)),
          ),
        ),
      ]);
    } else if (ArtisanWorkLogic.canRequestPaidCancellation(job)) {
      children.addAll([
        const SizedBox(height: 18),
        Center(
          child: TextButton(
            onPressed: loading
                ? null
                : () async {
                    final reason = await pickReason(context,
                        title: 'Request cancellation',
                        message: 'This job is already paid. HandyTrust will review your request — the payment stays protected in escrow until a decision is made.',
                        confirm: 'Send request');
                    if (reason == null || !context.mounted) return;
                    final ok = await runWorkAction(context, ref,
                        () => ref.read(escrowNotifierProvider.notifier).requestPaidCancellation(job.id, callerRole: ActorRole.artisan, reason: reason),
                        failure: 'Could not send the request. Please try again.');
                    if (ok && context.mounted) htSnack(context, 'Cancellation request sent to HandyTrust.');
                  },
            child: Text('Request cancellation', style: HtType.smallStrong(p.danger)),
          ),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _ReworkCard extends ConsumerStatefulWidget {
  const _ReworkCard({required this.job});
  final JobModel job;
  @override
  ConsumerState<_ReworkCard> createState() => _ReworkCardState();
}

class _ReworkCardState extends ConsumerState<_ReworkCard> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final job = widget.job;
    final loading = ref.watch(escrowNotifierProvider).isLoading;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ProSection('Rework requested'),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: p.warningSoft, borderRadius: BorderRadius.circular(HtRadius.inner), border: Border.all(color: p.warning.withValues(alpha: 0.35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.replay_rounded, color: p.warning), const SizedBox(width: 8), Expanded(child: Text('The customer asked for changes', style: HtType.bodyStrong(p.textPrimary)))]),
          if (job.reworkReason != null) ...[const SizedBox(height: 8), Text('“${job.reworkReason}”', style: HtType.body(p.textPrimary))],
          const SizedBox(height: 6),
          Text([if (job.reworkRequestedAt != null) 'Requested ${HtFormat.date(job.reworkRequestedAt!.toLocal())}', 'this job’s one rework request'].join(' · '), style: HtType.small(p.textSecondary)),
        ]),
      ),
      if (job.reworkResponse != null) ...[
        const SizedBox(height: 10),
        HtCard(radius: HtRadius.inner, padding: const EdgeInsets.all(14), child: htKv(context, 'Your response', job.reworkResponse!)),
      ] else ...[
        HtTextField(label: 'Your response', controller: _c, hint: 'Tell the customer how you’ll fix it', lines: 3, maxLength: 500),
        const SizedBox(height: 10),
        HtSecondaryButton(
          label: 'Send response',
          icon: Icons.send_rounded,
          onPressed: loading
              ? null
              : () async {
                  final t = _c.text.trim();
                  if (t.isEmpty) {
                    htSnack(context, 'Write a short response first.', error: true);
                    return;
                  }
                  final ok = await runWorkAction(context, ref, () => ref.read(escrowNotifierProvider.notifier).respondToRework(job.id, response: t), failure: 'Could not send your response. Please try again.');
                  if (ok && context.mounted) htSnack(context, 'Response sent.');
                },
        ),
      ],
      const SizedBox(height: 10),
      const HtInfoBanner(icon: Icons.schedule_rounded, text: 'After you fix and resubmit the work, a new 14-day review period starts.'),
    ]);
  }
}

// ─── Agreement (artisan reviews the customer's draft) ───────────────────────

class _AgreementTab extends ConsumerWidget {
  const _AgreementTab({required this.job});
  final JobModel job;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final status = job.agreementStatus ?? AgreementStatus.negotiating;
    final loading = ref.watch(escrowNotifierProvider).isLoading;
    final summary = HtCard(
      radius: HtRadius.inner,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SCOPE OF WORK', style: HtType.caps(p.textMuted)),
        const SizedBox(height: 4),
        Text(job.agreementScope?.trim().isNotEmpty == true ? job.agreementScope! : 'Not written yet', style: HtType.body(p.textPrimary).copyWith(fontSize: 13.5)),
        const SizedBox(height: 10),
        htKv(context, status == AgreementStatus.confirmed ? 'Locked price' : 'Agreed price', job.agreedAmount == null ? '—' : HtFormat.naira(job.agreedAmount), strong: true),
        if (job.confirmedAppointment != null) htKv(context, 'Schedule', HtFormat.dateTime(job.confirmedAppointment!.toLocal())),
      ]),
    );
    Widget party(String who, bool ok) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.tile + 2), border: Border.all(color: p.border)),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: ok ? p.success : p.textMuted, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(who, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5)), Text(ok ? 'Confirmed' : 'Not confirmed', style: HtType.small(p.textSecondary))])),
          ]),
        );
    final parties = Row(children: [Expanded(child: party('Customer', job.agreementConfirmedByCustomer)), const SizedBox(width: 10), Expanded(child: party('You', job.agreementConfirmedByArtisan))]);

    final List<Widget> body = switch (status) {
      AgreementStatus.confirmed => [summary, const SizedBox(height: 10), parties, const SizedBox(height: 10), Text('The price is locked. The customer funds escrow next.', style: HtType.small(p.textSecondary))],
      AgreementStatus.pendingArtisanConfirmation => [
          const HtInfoBanner(icon: Icons.fact_check_outlined, tone: HtTone.warning, title: 'Review the customer’s agreement', text: 'Accept it, or ask for changes if anything is wrong.'),
          const SizedBox(height: 10),
          summary,
          const SizedBox(height: 10),
          parties,
          const SizedBox(height: 14),
          HtPrimaryButton(
            label: 'Accept agreement',
            loading: loading,
            onPressed: () async {
              final ok = await runWorkAction(context, ref, () => ref.read(escrowNotifierProvider.notifier).acceptAgreement(job.id), failure: 'Could not accept the agreement. Please try again.');
              if (ok && context.mounted) htSnack(context, 'Agreement accepted.');
            },
          ),
          const SizedBox(height: 10),
          HtSecondaryButton(
            label: 'Request changes',
            onPressed: loading
                ? null
                : () async {
                    final reason = await askText(context, title: 'Request changes', label: 'What would you like to change?', confirm: 'Send');
                    if (reason == null || !context.mounted) return;
                    final ok = await runWorkAction(context, ref, () => ref.read(escrowNotifierProvider.notifier).requestAgreementChanges(job.id, reason: reason), failure: 'Could not send the changes request. Please try again.');
                    if (ok && context.mounted) htSnack(context, 'Changes requested.');
                  },
          ),
        ],
      AgreementStatus.changesRequested => [
          HtInfoBanner(icon: Icons.chat_outlined, tone: HtTone.neutral, title: 'You asked for changes', text: job.agreementChangesRequestedReason == null ? 'Waiting for the customer to update the agreement.' : '“${job.agreementChangesRequestedReason}” — waiting for the customer to update it.'),
          const SizedBox(height: 10),
          summary,
        ],
      AgreementStatus.negotiating => [
          HtInfoBanner(
            icon: Icons.edit_note_rounded,
            tone: HtTone.neutral,
            text: job.status == JobStatus.matched ? 'Booking confirmed. The customer opens the conversation and drafts the agreement.' : 'The customer is drafting the agreement. Agree the details in chat.',
          ),
        ],
    };
    return Padding(padding: const EdgeInsets.only(top: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body));
  }
}

// ─── Schedule (artisan proposes up to 3 times) ──────────────────────────────

class _ScheduleTab extends ConsumerStatefulWidget {
  const _ScheduleTab({required this.job});
  final JobModel job;
  @override
  ConsumerState<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<_ScheduleTab> {
  final List<DateTime> _slots = [];

  Future<void> _add() async {
    final now = clock.now();
    final date = await showDatePicker(context: context, initialDate: now.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 90)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (time == null || !mounted) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (at.isBefore(now)) {
      htSnack(context, 'Pick a time in the future.', error: true);
      return;
    }
    setState(() => _slots.add(at));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final job = widget.job;
    final stage = ArtisanWorkLogic.stageOf(job);
    final loading = ref.watch(escrowNotifierProvider).isLoading;
    Widget slot(DateTime at, {VoidCallback? onRemove, bool chosen = false}) {
      final l = at.toLocal();
      const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.tile + 2), border: Border.all(color: chosen ? proAccent(p) : p.border, width: chosen ? 1.6 : 1)),
        child: Row(children: [
          Container(width: 46, padding: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(10)), child: Column(children: [Text(days[l.weekday - 1], style: HtType.caps(p.textMuted).copyWith(fontSize: 9)), Text('${l.day}', style: HtType.amount(p.textPrimary, size: 18))])),
          const SizedBox(width: 12),
          Expanded(child: Text('${proMonth(l)} · ${HtFormat.clock(l)}', style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14))),
          if (onRemove != null) IconButton(tooltip: 'Remove time', onPressed: onRemove, icon: Icon(Icons.close_rounded, color: p.textMuted, size: 18)),
          if (chosen) HtStatusPill(label: 'Confirmed', tone: HtTone.success),
        ]),
      );
    }

    final List<Widget> body;
    if (job.confirmedAppointment != null) {
      body = [const ProSection('Confirmed time'), slot(job.confirmedAppointment!, chosen: true)];
    } else if (job.appointmentSlots.isNotEmpty) {
      body = [const ProSection('Times you proposed'), for (final s in job.appointmentSlots) slot(s), Text('Waiting for the customer to pick one.', style: HtType.small(p.textSecondary))];
    } else if (stage == ArtisanStage.schedule) {
      body = [
        const ProSection('Propose up to 3 times'),
        for (var i = 0; i < _slots.length; i++) slot(_slots[i], onRemove: () => setState(() => _slots.removeAt(i))),
        if (_slots.length < 3) HtSecondaryButton(label: _slots.isEmpty ? 'Add a time' : 'Add another time', icon: Icons.add_rounded, onPressed: _add),
        const SizedBox(height: 12),
        HtPrimaryButton(
          label: 'Send times to customer',
          loading: loading,
          onPressed: _slots.isEmpty
              ? null
              : () async {
                  final ok = await runWorkAction(context, ref, () => ref.read(escrowNotifierProvider.notifier).proposeAppointmentSlots(job.id, List.of(_slots)), failure: 'Could not send the times. Please try again.');
                  if (ok && context.mounted) {
                    setState(_slots.clear);
                    htSnack(context, 'Times sent to the customer.');
                  }
                },
        ),
        const SizedBox(height: 8),
        Text('The customer picks one before paying into escrow.', style: HtType.small(p.textSecondary)),
      ];
    } else {
      body = [const SizedBox(height: 14), HtInfoBanner(icon: Icons.event_outlined, tone: HtTone.neutral, text: job.agreementStatus == AgreementStatus.confirmed ? 'No appointment needed for this job.' : 'You can propose times once the agreement is confirmed.')];
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body);
  }
}

class _PhotosTab extends StatelessWidget {
  const _PhotosTab({required this.job});
  final JobModel job;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    Widget group(String label, List<String> urls) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ProSection(label, count: urls.length),
          urls.isEmpty ? Text('None yet', style: HtType.small(p.textMuted)) : HtPhotoGrid(urls: urls, tileHeight: 96),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      group('Customer photos', job.imageUrls),
      group('Before photos', job.beforePhotoUrls),
      group('After photos', job.completionImageUrls),
    ]);
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.job});
  final JobModel job;
  @override
  Widget build(BuildContext context) {
    String when(DateTime? d) => d == null ? 'Pending' : HtFormat.dateTime(d.toLocal());
    final entries = <(String, String, bool)>[
      ('Job posted', when(job.createdAt), true),
      ('Booking request', when(job.bookingRequestedAt ?? job.matchedAt), (job.bookingRequestedAt ?? job.matchedAt) != null),
      ('Booking accepted', when(job.bookingConfirmedAt), job.bookingConfirmedAt != null),
      ('Agreement confirmed', when(job.agreementArtisanConfirmedAt ?? job.agreementCustomerConfirmedAt), job.agreementStatus == AgreementStatus.confirmed),
      ('Escrow funded', when(job.escrowLockedAt), job.escrowLockedAt != null),
      ('Work started', when(job.startedAt), job.startedAt != null),
      ('Work submitted', when(job.submittedAt), job.submittedAt != null),
      ('Completed', when(job.completedAt), job.completedAt != null),
    ];
    return Padding(padding: const EdgeInsets.only(top: 18), child: HtTimeline(entries: entries));
  }
}

// ─── Dispute ────────────────────────────────────────────────────────────────

class _DisputeView extends ConsumerWidget {
  const _DisputeView({required this.job});
  final JobModel job;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputeAsync = ref.watch(disputeForJobProvider(job.id));
    return ArtisanPage(
      title: 'Dispute',
      sub: '${workTitle(job)} · #${HtFormat.bookingRef(job.id)}',
      onChat: () => _openChat(context, job),
      children: [
        disputeAsync.when(
          loading: () => const HtLoadingView(label: 'Loading the dispute…'),
          error: (e, _) => ArtisanState.error(e, onRetry: () => ref.invalidate(disputeForJobProvider(job.id))),
          data: (d) => d == null
              ? const HtCard(child: HtEmptyView(icon: Icons.gavel_rounded, title: 'Dispute details unavailable', message: 'HandyTrust is reviewing this job.'))
              : _DisputeBody(job: job, dispute: d),
        ),
      ],
    );
  }
}

class _DisputeBody extends ConsumerStatefulWidget {
  const _DisputeBody({required this.job, required this.dispute});
  final JobModel job;
  final DisputeModel dispute;
  @override
  ConsumerState<_DisputeBody> createState() => _DisputeBodyState();
}

class _DisputeBodyState extends ConsumerState<_DisputeBody> {
  final _c = TextEditingController();
  final List<Uint8List> _evidence = [];
  bool _sending = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _c.text.trim();
    if (text.isEmpty) {
      htSnack(context, 'Explain what happened first.', error: true);
      return;
    }
    final uid = ref.read(authStateChangesProvider).asData?.value?.uid ?? '';
    if (uid.isEmpty) return;
    setState(() => _sending = true);
    try {
      final storage = ref.read(storageServiceProvider);
      final urls = <String>[];
      for (var i = 0; i < _evidence.length; i++) {
        urls.add(await storage.uploadDisputeEvidence(disputeId: widget.dispute.id, userId: uid, index: i, bytes: _evidence[i]));
      }
      await ref.read(disputeServiceProvider).respondToDispute(disputeId: widget.dispute.id, responseText: text, evidenceImageUrls: urls);
      if (mounted) htSnack(context, 'Response sent to HandyTrust.');
    } catch (_) {
      if (mounted) htSnack(context, 'Could not send your response. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final d = widget.dispute;
    final resolved = d.resolution != null || widget.job.status == JobStatus.resolved;
    final mine = d.raisedBy == widget.job.artisanId;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        HtStatusPill(label: resolved ? 'Resolved' : 'Open · with HandyTrust', tone: resolved ? HtTone.success : HtTone.danger, dot: true),
        const Spacer(),
        if (!resolved) Text('Escrow on hold', style: HtType.smallStrong(p.warning)),
      ]),
      ProSection(mine ? 'Your claim' : 'Customer’s claim'),
      HtCard(
        radius: HtRadius.inner,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d.reason, style: HtType.body(p.textPrimary).copyWith(fontSize: 13.5)),
          if (d.evidenceImageUrls.isNotEmpty) ...[const SizedBox(height: 10), HtPhotoGrid(urls: d.evidenceImageUrls, tileHeight: 74)],
        ]),
      ),
      if (resolved && d.resolution != null) ...[const ProSection('Decision'), HtCard(radius: HtRadius.inner, padding: const EdgeInsets.all(14), child: Text(d.resolution!, style: HtType.body(p.textPrimary).copyWith(fontSize: 13.5)))],
      if (!mine) ...[
        const ProSection('Your response'),
        if (d.artisanResponseText != null)
          HtCard(
            radius: HtRadius.inner,
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.artisanResponseText!, style: HtType.body(p.textPrimary).copyWith(fontSize: 13.5)),
              if (d.artisanEvidenceUrls.isNotEmpty) ...[const SizedBox(height: 10), HtPhotoGrid(urls: d.artisanEvidenceUrls, tileHeight: 74)],
            ]),
          )
        else if (!resolved) ...[
          HtTextField(label: 'Explain what happened', controller: _c, hint: 'Describe the work and anything the reviewer should know…', lines: 4, maxLength: 1000),
          const SizedBox(height: 10),
          HtPhotoGrid(
            bytes: _evidence,
            max: 5,
            tileHeight: 74,
            onRemoveBytes: (i) => setState(() => _evidence.removeAt(i)),
            onAdd: () async {
              final b = await pickWorkPhoto();
              if (b != null && mounted) setState(() => _evidence.add(b));
            },
          ),
          const SizedBox(height: 12),
          HtPrimaryButton(label: 'Send response', loading: _sending, onPressed: _send),
        ],
      ],
      const SizedBox(height: 12),
      Text('An administrator reviews both sides and decides: release, refund or split.', style: HtType.small(p.textSecondary)),
    ]);
  }
}
