import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:intl/intl.dart';
import '../../core/services/job_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/workflow_gate_service.dart';
import '../../models/dispute_model.dart';
import '../../models/job_model.dart';
import '../../models/job_mutation_context.dart';
import '../../models/audit_log_model.dart';
import '../../models/quote_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dispute_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/quote_provider.dart';
import '../../providers/platform_config_provider.dart';
import '../../providers/review_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';
import '../../widgets/web_content_wrapper.dart';
import '../../widgets/workflow_status_card.dart';
import '../../widgets/workflow_timeline.dart';

class JobDetailScreen extends ConsumerWidget {
  final String jobId;

  const JobDetailScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobStreamProvider(jobId));
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Job Details')),
      body: WebContentWrapper(
        child: jobAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (job) {
            if (job == null) {
              return const Center(child: Text('Job not found'));
            }
            final isCustomer = userAsync.value?.isCustomer ?? true;
            return _JobDetailBody(
              job: job,
              isCustomer: isCustomer,
              currentUserId: userAsync.value?.uid,
            );
          },
        ),
      ),
    );
  }
}

class _JobDetailBody extends ConsumerWidget {
  final JobModel job;
  final bool isCustomer;
  final String? currentUserId;

  const _JobDetailBody({
    required this.job,
    required this.isCustomer,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final escrow = ref.watch(escrowNotifierProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkflowTimeline(job: job),
          const SizedBox(height: 20),
          if (job.status == JobStatus.requested &&
              isCustomer &&
              currentUserId != null) ...[
            _QuoteInboxSection(job: job, customerId: currentUserId!),
            const SizedBox(height: 20),
          ],
          if (job.status == JobStatus.submitted) ...[
            _DisputeCountdownBanner(job: job),
            const SizedBox(height: 20),
          ],
          if ((job.status == JobStatus.disputed ||
                  job.status == JobStatus.resolved) &&
              currentUserId != null) ...[
            _DisputeThreadSection(job: job, currentUserId: currentUserId!),
            const SizedBox(height: 20),
          ],
          if (job.reworkCount > 0 &&
              (job.status == JobStatus.inProgress || job.status == JobStatus.submitted) &&
              currentUserId != null) ...[
            _ReworkSection(job: job, currentUserId: currentUserId!),
            const SizedBox(height: 20),
          ],
          _detailSection(context, 'Service Category', job.category),
          const SizedBox(height: 16),
          _detailSection(context, 'Description', job.description),
          _JobLocationSection(job: job, isCustomer: isCustomer),
          if (job.agreedAmount != null) ...[
            const SizedBox(height: 16),
            _detailSection(
              context,
              'Agreed Amount',
              '₦${NumberFormat('#,##0').format(job.agreedAmount!)}',
            ),
          ],
          // ── Agreement confirmation (Negotiation Completed checkpoint) ──
          if (job.status == JobStatus.inChat && currentUserId != null) ...[
            const SizedBox(height: 20),
            _AgreementSection(
              job: job,
              isCustomer: isCustomer,
              currentUserId: currentUserId!,
            ),
          ],
          // ── Appointment scheduling (Feature 2) ───────────────────
          if (job.status == JobStatus.inChat) ...[
            const SizedBox(height: 20),
            _AppointmentSection(job: job, isCustomer: isCustomer,
                currentUserId: currentUserId),
          ],
          if (job.confirmedAppointment != null &&
              job.status != JobStatus.cancelled) ...[
            const SizedBox(height: 16),
            _detailSection(
              context,
              'Confirmed Appointment',
              DateFormat('EEE d MMM yyyy, h:mm a')
                  .format(job.confirmedAppointment!.toLocal()),
            ),
          ],
          // ── Job images ────────────────────────────────────────────
          if (job.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 20),
            _imageSection(context, 'Job Photos (Customer Upload)', job.imageUrls),
          ],
          if (job.beforePhotoUrls.isNotEmpty) ...[
            const SizedBox(height: 20),
            _imageSection(context, 'Arrival Photos (Before Work)', job.beforePhotoUrls),
          ],
          if (job.completionImageUrls.isNotEmpty) ...[
            const SizedBox(height: 20),
            _imageSection(
              context,
              'Completion Photos (After Work)',
              job.completionImageUrls,
            ),
          ],
          if (job.artisanNotes != null) ...[
            const SizedBox(height: 16),
            _detailSection(context, 'Artisan Notes', job.artisanNotes!),
          ],
          if (job.artisanId.isNotEmpty) ...[
            const SizedBox(height: 20),
            _artisanSection(context, ref),
          ],
          const SizedBox(height: 28),
          _actionButtons(context, ref, escrow),
          // ── Hire Again (Feature 4) ────────────────────────────────
          if (job.status == JobStatus.completed &&
              isCustomer &&
              job.artisanId.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/artisan/${job.artisanId}'),
                icon: Icon(Icons.refresh_rounded,
                    size: 17, color: context.colors.primary),
                label: Text(
                  'Hire Again',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                    fontFamily: 'Inter',
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.colors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _detailSection(BuildContext context, String title, String value) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
              height: 1.5,
            ),
          ),
        ],
      );

  Widget _imageSection(BuildContext context, String title, List<String> urls) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: urls.length,
              separatorBuilder: (_, index) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  urls[i],
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, err, stack) => Container(
                    width: 120,
                    height: 120,
                    color: context.colors.surfaceVariant,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: context.colors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _artisanSection(BuildContext context, WidgetRef ref) {
    final artisanAsync = ref.watch(artisanProfileProvider(job.artisanId));

    return artisanAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, stack) => const SizedBox.shrink(),
      data: (artisan) {
        if (artisan == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => context.push('/artisan/${artisan.uid}'),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.borderLight),
            ),
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
                          artisan.displayName.isNotEmpty
                              ? artisan.displayName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.colors.primary,
                            fontFamily: 'Inter',
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artisan.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        artisan.category ?? 'Artisan',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.colors.textTertiary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Executes whatever [WorkflowGateService.describeStep] decided the
  /// primary action is. Decision logic (should this action be available,
  /// what should it be called) lives in WorkflowGateService; this is only
  /// the execution half (navigation, provider calls) — same split already
  /// used for chat_screen.dart's payment gate, so the two surfaces read
  /// the same decision instead of each re-deriving it.
  void _executeAction(
    BuildContext context,
    WidgetRef ref,
    WorkflowAction action,
  ) {
    switch (action) {
      case WorkflowAction.browseOpenJobs:
        context.push('/open-jobs', extra: {'category': job.category});
      case WorkflowAction.continueNegotiation:
        () async {
          await ref.read(escrowNotifierProvider.notifier).openChat(job.id);
          if (context.mounted) {
            context.push('/chat/${job.id}', extra: {'artisanId': job.artisanId});
          }
        }();
      case WorkflowAction.payIntoEscrow:
        context.push('/payment/${job.id}');
      case WorkflowAction.startJob:
        ref.read(escrowNotifierProvider.notifier).startWork(job.id);
      case WorkflowAction.submitCompletion:
        context.push('/job/${job.id}/submit');
      case WorkflowAction.confirmBooking:
        ref.read(escrowNotifierProvider.notifier).confirmBooking(job.id);
      case WorkflowAction.none:
        break;
    }
  }

  String? _actorLabel(WorkflowActor? actor) => switch (actor) {
        WorkflowActor.customer => 'the customer',
        WorkflowActor.artisan => 'the artisan',
        WorkflowActor.system => 'HandyTrust',
        null => null,
      };

  Widget _actionButtons(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<void> escrow,
  ) {
    final loading = escrow.isLoading;
    const fundedStatuses = {JobStatus.escrowLocked, JobStatus.inProgress, JobStatus.submitted};

    // Stage 5 (D9): fraud / safety / security (or unclassified) suspension —
    // the job stays visible, disputes and exits stay available, but nothing
    // that progresses the job or moves money is offered. The server refuses
    // those writes regardless (firestore.rules isFreezingSuspended).
    final viewerProfile = ref.watch(currentUserProfileProvider).asData?.value;
    if ((viewerProfile?.hasFreezingSuspension ?? false) && !job.status.isTerminal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WorkflowStatusCard(
            phase: 'Account Under Review',
            description:
                'Your account is suspended pending review, so this job is paused for you. '
                'Any payment stays protected in escrow. You can still raise or respond to a dispute.',
          ),
          if (job.status == JobStatus.disputed || fundedStatuses.contains(job.status)) ...[
            const SizedBox(height: 12),
            if (job.status != JobStatus.disputed) _RaiseDisputeButton(job: job, loading: loading),
          ],
          if (isCustomer && !fundedStatuses.contains(job.status) && job.status != JobStatus.disputed) ...[
            const SizedBox(height: 12),
            _CancelButton(job: job, isCustomer: isCustomer, loading: loading),
          ],
        ],
      );
    }

    // requested / matched / inChat / paymentPending / escrowLocked /
    // inProgress all route through one shared decision (WorkflowGateService)
    // instead of each re-deriving its own phase/description/gating —
    // previously agreementStatus/schedulingSatisfied checks for the inChat
    // case were duplicated here AND in chat_screen.dart independently.
    if (job.status == JobStatus.requested ||
        job.status == JobStatus.matched ||
        job.status == JobStatus.inChat ||
        job.status == JobStatus.paymentPending ||
        job.status == JobStatus.escrowLocked ||
        job.status == JobStatus.inProgress) {
      final step = WorkflowGateService.describeStep(job, viewerIsCustomer: isCustomer);
      final hasCard = step.description.isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasCard) ...[
            WorkflowStatusCard(
              phase: step.phase,
              description: step.description,
              waitingOn: _actorLabel(step.waitingOn),
              primaryLabel: step.primaryLabel,
              primaryLoading: loading,
              onPrimary: step.primaryAction == WorkflowAction.none
                  ? null
                  : () => _executeAction(context, ref, step.primaryAction),
            ),
            const SizedBox(height: 12),
          ],
          // Stage 5 (D3, HT-011): either party can report a problem on a
          // funded job — previously only the customer, and only once the
          // work was submitted, so an abandoned job had no exit.
          if (fundedStatuses.contains(job.status)) ...[
            _RaiseDisputeButton(job: job, loading: loading),
            const SizedBox(height: 12),
          ],
          _CancelButton(job: job, isCustomer: isCustomer, loading: loading),
        ],
      );
    }

    return switch (job.status) {
      JobStatus.submitted => isCustomer
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const WorkflowStatusCard(
                  phase: 'Work Submitted',
                  description:
                      'The artisan says the job is done. Review their photos and confirm to release payment — or raise a dispute if something is wrong.',
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          await ref
                              .read(escrowNotifierProvider.notifier)
                              .confirmComplete(job.id);
                          if (context.mounted) {
                            context.push('/review/${job.id}');
                          }
                        },
                  child: const Text('Confirm & Release Payment'),
                ),
                // Stage 5 (D4): one rework request per job.
                if (job.canRequestRework) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: loading ? null : () => _requestRework(context, ref),
                    child: const Text('Request Changes (once)'),
                  ),
                ],
                const SizedBox(height: 12),
                _RaiseDisputeButton(job: job, loading: loading),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const WorkflowStatusCard(
                  phase: 'Submitted',
                  description:
                      "Waiting for the customer to confirm your work. If they don't respond, payment releases automatically 14 days after you submitted.",
                  waitingOn: 'the customer',
                ),
                const SizedBox(height: 12),
                _RaiseDisputeButton(job: job, loading: loading),
              ],
            ),
      // Same inline-WorkflowStatusCard pattern the submitted case above
      // uses, not WorkflowGateService.describeStep — completed/disputed/
      // resolved/cancelled all collapse to a generic 'Closed' phase there,
      // which was never meant to be the last thing either party sees.
      // Previously the artisan got nothing at all on this screen once a
      // job completed — no confirmation payment had actually reached them.
      JobStatus.completed => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Stage 6 (HT-024): the copy follows the server-mirrored payout
            // status — never "released" before Paystack confirms the transfer.
            WorkflowStatusCard(
              phase: switch (job.payoutStatus) {
                'paid' => 'Payment Released',
                'on_hold' => 'Payout On Hold',
                'delayed' => 'Payout Delayed',
                _ => 'Payout Processing',
              },
              description: switch ((job.payoutStatus, isCustomer)) {
                ('paid', true) => 'Payment has been sent to the artisan. Thanks for using HandyTrust!',
                ('paid', false) => 'Your payout has been sent to your bank account.',
                ('on_hold', true) || ('delayed', true) =>
                  'You confirmed the job. The payout to the artisan is being handled by HandyTrust.',
                ('on_hold', false) => 'Your payout is on hold while HandyTrust reviews your account. The funds remain protected.',
                ('delayed', false) => 'Your payout is delayed — please check your bank details. HandyTrust will retry it.',
                (_, true) => 'You confirmed the job. The payout to the artisan is being processed.',
                (_, false) => 'The customer confirmed the job. Your payout is being processed — we will notify you when it is sent.',
              },
            ),
            if (isCustomer) ...[
              const SizedBox(height: 12),
              Consumer(
                builder: (context, ref, _) {
                  final reviewAsync = ref.watch(jobReviewProvider(job.id));
                  final alreadyReviewed = reviewAsync.asData?.value != null;
                  return OutlinedButton(
                    onPressed: () => context.push('/review/${job.id}'),
                    child: Text(
                      alreadyReviewed ? 'View My Review' : 'Leave a Review',
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      JobStatus.cancelled => _CancellationInfoBox(job: job),
      JobStatus.expired => WorkflowStatusCard(
          phase: 'Job Expired',
          description: isCustomer
              ? 'This job received no confirmed booking within the open period and has closed. You can post it again any time.'
              : 'This job closed without a booking.',
        ),
      _ => const SizedBox.shrink(),
    };
  }

  /// Stage 5 (D4): customer asks for changes once, with a reason. The
  /// server clears the current review window; the artisan's resubmission
  /// starts a new 14-day one.
  Future<void> _requestRework(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Request Changes', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'You can request changes once. Describe what needs fixing — the artisan will '
              'resubmit, and a new 14-day review period starts then.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(labelText: 'What needs to change?')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Send Request')),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    if (reason.length < 10) {
      showErrorSnackbar(context, 'Please describe the changes (at least 10 characters).');
      return;
    }
    await ref.read(escrowNotifierProvider.notifier).requestRework(job.id, reason: reason);
    if (context.mounted && ref.read(escrowNotifierProvider).hasError) {
      showErrorSnackbar(context, 'Could not request changes. Please try again.');
    }
  }
}

/// Stage 5 (D3): either party opens a dispute on a funded job.
class _RaiseDisputeButton extends StatelessWidget {
  final JobModel job;
  final bool loading;
  const _RaiseDisputeButton({required this.job, required this.loading});

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: loading ? null : () => context.push('/dispute/${job.id}'),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.error,
          side: BorderSide(color: context.colors.error),
        ),
        child: Text(job.status == JobStatus.submitted ? 'Raise Dispute' : 'Report a Problem'),
      );
}

/// Stage 5 (D4): shows the customer's rework reason; the artisan may answer once.
class _ReworkSection extends ConsumerStatefulWidget {
  final JobModel job;
  final String currentUserId;
  const _ReworkSection({required this.job, required this.currentUserId});

  @override
  ConsumerState<_ReworkSection> createState() => _ReworkSectionState();
}

class _ReworkSectionState extends ConsumerState<_ReworkSection> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final canRespond = JobService.canRespondToRework(job, widget.currentUserId);
    final style = TextStyle(fontSize: 13, color: context.colors.textSecondary, fontFamily: 'Inter');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Changes requested', style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.textPrimary, fontFamily: 'Inter')),
          const SizedBox(height: 6),
          Text(job.reworkReason ?? '', style: style),
          if (job.reworkResponse != null) ...[
            const SizedBox(height: 10),
            Text("Artisan's response", style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.textPrimary, fontFamily: 'Inter')),
            const SizedBox(height: 4),
            Text(job.reworkResponse!, style: style),
          ] else if (canRespond) ...[
            const SizedBox(height: 10),
            TextField(controller: _ctrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Reply to the customer (optional, once)')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final text = _ctrl.text.trim();
                if (text.isEmpty) return;
                await ref.read(escrowNotifierProvider.notifier).respondToRework(job.id, response: text);
                if (context.mounted && ref.read(escrowNotifierProvider).hasError) {
                  showErrorSnackbar(context, 'Could not send your response.');
                }
              },
              child: const Text('Send Response'),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Cancellation UI ──────────────────────────────────────────────────────────

class _CancelButton extends ConsumerWidget {
  final JobModel job;
  final bool isCustomer;
  final bool loading;

  const _CancelButton({
    required this.job,
    required this.isCustomer,
    required this.loading,
  });

  static const _customerReasons = [
    'Found another artisan',
    'Too expensive',
    'No longer needed',
    'Other',
  ];

  static const _artisanReasons = [
    'Unavailable on requested date',
    'Too far from location',
    'Outside my expertise',
    'Other',
  ];

  /// Policy D2: once escrow is funded neither party can cancel directly —
  /// the button files a request for HandyTrust to review instead (the
  /// firestore.rules cancel clause no longer covers these statuses).
  bool get _isFunded =>
      job.status == JobStatus.escrowLocked || job.status == JobStatus.inProgress;

  /// Stage 5 (D6/D7): an artisan never cancels (kills) a job — before
  /// payment they decline the booking or withdraw, and the server reopens
  /// the job for other artisans.
  bool get _artisanWithdrawal => !isCustomer && !_isFunded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An artisan just browsing an open job has nothing to cancel.
    if (!isCustomer && job.status == JobStatus.requested) return const SizedBox.shrink();
    if (_artisanWithdrawal) {
      final declining = job.awaitingArtisanConfirmation;
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: loading ? null : () => _withdraw(context, ref, declining: declining),
          icon: Icon(Icons.undo_rounded, size: 17, color: context.colors.error),
          label: Text(
            declining ? 'Decline Booking' : 'Withdraw from Job',
            style: TextStyle(color: context.colors.error, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: context.colors.error),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }
    if (_isFunded && job.hasPendingCancellationRequest) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.hourglass_top_rounded, size: 17),
          label: const Text(
            'Cancellation requested — under review',
            style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Inter'),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: loading ? null : () => _showCancelDialog(context, ref),
        icon: Icon(Icons.cancel_outlined,
            size: 17, color: context.colors.error),
        label: Text(
          _isFunded ? 'Request Cancellation' : 'Cancel Job',
          style: TextStyle(
            color: context.colors.error,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: context.colors.error),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref, {required bool declining}) async {
    String selected = _artisanReasons.first;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(declining ? 'Decline Booking' : 'Withdraw from Job',
              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                declining
                    ? 'The job reopens so the customer can book another artisan.'
                    : 'The job reopens so the customer can book another artisan. Withdrawing from a confirmed booking counts towards your cancellation rate.',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _artisanReasons
                    .map((r) => ChoiceChip(
                          label: Text(r, style: const TextStyle(fontFamily: 'Inter', fontSize: 12)),
                          selected: selected == r,
                          onSelected: (_) => setState(() => selected = r),
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Keep Job')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.colors.error),
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: Text(declining ? 'Decline' : 'Withdraw'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || !context.mounted) return;
    await ref.read(escrowNotifierProvider.notifier).withdrawFromJob(job.id, reason: reason);
    if (!context.mounted) return;
    if (ref.read(escrowNotifierProvider).hasError) {
      showErrorSnackbar(context, 'Could not complete this. Please try again.');
    } else {
      context.go('/home');
    }
  }

  Future<void> _showCancelDialog(BuildContext context, WidgetRef ref) async {
    final reasons = isCustomer ? _customerReasons : _artisanReasons;
    String? selected = reasons.first;

    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            _isFunded ? 'Request Cancellation' : 'Cancel Job',
            style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isFunded) ...[
                const Text(
                  'This job is already paid. HandyTrust will review your request — '
                  'the payment stays protected in escrow until a decision is made.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 13),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Select a reason:',
                style: TextStyle(fontFamily: 'Inter', fontSize: 14),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: reasons
                    .map(
                      (r) => ChoiceChip(
                        label: Text(r,
                            style: const TextStyle(
                                fontFamily: 'Inter', fontSize: 12)),
                        selected: selected == r,
                        onSelected: (_) => setState(() => selected = r),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Keep Job'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.colors.error),
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: Text(_isFunded ? 'Send Request' : 'Confirm Cancel'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == null || !context.mounted) return;
    if (_isFunded) {
      await ref.read(escrowNotifierProvider.notifier).requestPaidCancellation(
            job.id,
            callerRole: isCustomer ? ActorRole.customer : ActorRole.artisan,
            reason: confirmed,
          );
      return;
    }
    await ref.read(escrowNotifierProvider.notifier).cancelJob(
          job.id,
          callerRole:
              isCustomer ? ActorRole.customer : ActorRole.artisan,
          cancellationReason: confirmed,
        );
  }
}

class _CancellationInfoBox extends StatelessWidget {
  final JobModel job;
  const _CancellationInfoBox({required this.job});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: context.colors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cancel_outlined,
                  size: 16, color: context.colors.error),
              const SizedBox(width: 6),
              Text(
                'Job Cancelled',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.colors.error,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          if (job.cancellationReason != null) ...[
            const SizedBox(height: 6),
            Text(
              'Reason: ${job.cancellationReason}',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
          // Stage 4: the refund's real, Paystack-reported state — never
          // "refunded" until Paystack says processed.
          if (job.refundStatus != null) ...[
            const SizedBox(height: 6),
            Text(
              switch (job.refundStatus) {
                'processed' => 'Refund processed — it can take up to 10 business days to reach your account.',
                'failed' || 'needs_attention' => 'Refund delayed — HandyTrust is resolving it with our payment provider.',
                _ => 'Refund in progress with our payment provider.',
              },
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
  }
}

/// Customer-side Quote Inbox — shown while the job is still 'requested'.
/// Lists every quote with price/duration/rating/trust tier/verification
/// badge; accepting routes through QuoteService.acceptQuote, which
/// delegates the job mutation to JobService (single write layer).
class _QuoteInboxSection extends ConsumerStatefulWidget {
  final JobModel job;
  final String customerId;

  const _QuoteInboxSection({required this.job, required this.customerId});

  @override
  ConsumerState<_QuoteInboxSection> createState() => _QuoteInboxSectionState();
}

class _QuoteInboxSectionState extends ConsumerState<_QuoteInboxSection> {
  String? _actingOnArtisanId;
  // 'price' sorts low-to-high; 'trust' sorts high-to-high
  String _sortBy = 'price';

  Future<void> _accept(QuoteModel quote) async {
    // Policy D1: a quote below the minimum job value could never be paid
    // online — stop here instead of at the payment screen.
    final config = ref.read(platformConfigProvider);
    if (!config.meetsMinimum(quote.amount)) {
      showErrorSnackbar(context,
          'This quote is below the minimum job value of ${config.minJobValueLabel}. Ask the artisan to revise it.');
      return;
    }
    // Stage 5 (D5): acceptance only within the quote's validity (the rules
    // enforce this from server time; this just explains it up front).
    if (!config.quoteIsValid(quote.updatedAt ?? quote.createdAt)) {
      showErrorSnackbar(context,
          'This quote has expired (quotes are valid for ${config.quoteValidityHours} hours). Ask the artisan to resubmit it.');
      return;
    }
    setState(() => _actingOnArtisanId = quote.artisanId);
    try {
      final ctx = JobMutationContext.customer(
        uid: widget.customerId,
        actionType: JobActionType.quoteAccepted,
        reason: 'Accepted quote from ${quote.artisanName}',
      );
      await ref
          .read(quoteServiceProvider)
          .acceptQuote(ctx, jobId: widget.job.id, artisanId: quote.artisanId);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not accept quote: $e');
    } finally {
      if (mounted) setState(() => _actingOnArtisanId = null);
    }
  }

  Future<void> _reject(QuoteModel quote) async {
    setState(() => _actingOnArtisanId = quote.artisanId);
    try {
      await ref
          .read(quoteServiceProvider)
          .rejectQuote(jobId: widget.job.id, artisanId: quote.artisanId);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not reject quote: $e');
    } finally {
      if (mounted) setState(() => _actingOnArtisanId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quotesAsync = ref.watch(jobQuotesProvider(widget.job.id));

    return quotesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 16, color: context.colors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Couldn't load quotes: $e",
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.error,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(jobQuotesProvider(widget.job.id)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (quotes) {
        final pending =
            quotes.where((q) => q.status == QuoteStatus.pending).toList();
        if (_sortBy == 'trust') {
          pending.sort(
              (a, b) => b.artisanTrustScore.compareTo(a.artisanTrustScore));
        } else {
          pending.sort((a, b) => a.amount.compareTo(b.amount));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Quotes Received (${pending.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                if (pending.length > 1) ...[
                  _SortChip(
                    label: 'Price',
                    selected: _sortBy == 'price',
                    onTap: () => setState(() => _sortBy = 'price'),
                  ),
                  const SizedBox(width: 6),
                  _SortChip(
                    label: 'Trust',
                    selected: _sortBy == 'trust',
                    onTap: () => setState(() => _sortBy = 'trust'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            if (pending.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Waiting for artisans to submit quotes for this job.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 8),
              ...pending.map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _QuoteCard(
                    quote: q,
                    busy: _actingOnArtisanId == q.artisanId,
                    onAccept: () => _accept(q),
                    onReject: () => _reject(q),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Shown while a job is 'submitted' — counts down the 14-day window during
/// which the customer may raise a dispute before the job would otherwise
/// auto-complete. Purely informational; the actual auto-completion and
/// dispute-window enforcement live server-side (JobService writes
/// disputeWindowEndsAt when the job is submitted).
class _DisputeCountdownBanner extends StatefulWidget {
  final JobModel job;

  const _DisputeCountdownBanner({required this.job});

  @override
  State<_DisputeCountdownBanner> createState() =>
      _DisputeCountdownBannerState();
}

class _DisputeCountdownBannerState extends State<_DisputeCountdownBanner> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  void _tick() {
    final endsAt = widget.job.disputeWindowEndsAt;
    final remaining = endsAt == null
        ? Duration.zero
        : endsAt.difference(DateTime.now());
    if (mounted) {
      setState(
        () => _remaining = remaining.isNegative ? Duration.zero : remaining,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.job.disputeWindowEndsAt == null) return const SizedBox.shrink();
    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.warningSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.colors.warning.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: context.colors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _remaining == Duration.zero
                  ? 'Dispute window has closed.'
                  : 'You have $days day${days == 1 ? '' : 's'} $hours hr${hours == 1 ? '' : 's'} left to raise a dispute before this job auto-completes.',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dispute Thread — shown once a job is 'disputed' or 'resolved'. Displays
/// the customer's original complaint + evidence, the artisan's response
/// (if any), an inline response form for the artisan while still open, and
/// the admin's resolution once the dispute is closed. Reads via
/// [disputeForJobProvider]; the artisan response write goes straight through
/// DisputeService.respondToDispute (status-transition writes still go
/// through JobService — see Section 4 dispute_service.dart).
class _DisputeThreadSection extends ConsumerStatefulWidget {
  final JobModel job;
  final String currentUserId;

  const _DisputeThreadSection({required this.job, required this.currentUserId});

  @override
  ConsumerState<_DisputeThreadSection> createState() =>
      _DisputeThreadSectionState();
}

class _DisputeThreadSectionState extends ConsumerState<_DisputeThreadSection> {
  final _responseController = TextEditingController();
  final List<Uint8List> _evidenceImages = [];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final raw = await picked.readAsBytes();
    Uint8List bytes = raw;
    if (raw.lengthInBytes > 500 * 1024) {
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        quality: 70,
      );
      bytes = Uint8List.fromList(compressed);
    }
    setState(() => _evidenceImages.add(bytes));
  }

  Future<void> _respond(DisputeModel dispute) async {
    if (_responseController.text.trim().isEmpty) {
      setState(() => _error = 'Please describe your side of the dispute.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final storage = StorageService();
      final evidenceUrls = <String>[];
      for (int i = 0; i < _evidenceImages.length; i++) {
        final url = await storage.uploadDisputeEvidence(
          disputeId: dispute.id,
          userId: widget.currentUserId,
          index: i,
          bytes: _evidenceImages[i],
        );
        evidenceUrls.add(url);
      }
      await ref
          .read(disputeServiceProvider)
          .respondToDispute(
            disputeId: dispute.id,
            responseText: _responseController.text.trim(),
            evidenceImageUrls: evidenceUrls,
          );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disputeAsync = ref.watch(disputeForJobProvider(widget.job.id));

    return disputeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('$e'),
      data: (dispute) {
        if (dispute == null) return const SizedBox.shrink();
        final isAgainstParty = dispute.againstUserId == widget.currentUserId;
        final canRespond =
            isAgainstParty &&
            dispute.artisanRespondedAt == null &&
            dispute.status == DisputeStatus.open;

        return Container(
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
                  Icon(
                    Icons.gavel_rounded,
                    color: context.colors.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Dispute',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          dispute.status == DisputeStatus.resolved ||
                              dispute.status == DisputeStatus.dismissed
                          ? context.colors.accentSurface
                          : context.colors.errorSurface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      dispute.status.name,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Inter',
                        color:
                            dispute.status == DisputeStatus.resolved ||
                                dispute.status == DisputeStatus.dismissed
                            ? context.colors.accent
                            : context.colors.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _threadEntry(
                'Customer',
                dispute.reason,
                dispute.evidenceImageUrls,
              ),
              if (dispute.artisanRespondedAt != null) ...[
                const SizedBox(height: 12),
                _threadEntry(
                  'Artisan Response',
                  dispute.artisanResponseText ?? '',
                  dispute.artisanEvidenceUrls,
                ),
              ],
              if (widget.job.status == JobStatus.resolved &&
                  dispute.resolution != null) ...[
                const SizedBox(height: 12),
                _threadEntry('Admin Resolution', dispute.resolution!, const []),
              ],
              if (canRespond) ...[
                const SizedBox(height: 16),
                Text(
                  'Respond to this dispute',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _responseController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Describe your side of the dispute...',
                  ),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _evidenceImages.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == _evidenceImages.length) {
                      return GestureDetector(
                        onTap: _pickEvidence,
                        child: Container(
                          decoration: BoxDecoration(
                            color: context.colors.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.colors.border),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.add_photo_alternate_outlined,
                              color: context.colors.textTertiary,
                              size: 22,
                            ),
                          ),
                        ),
                      );
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _evidenceImages[i],
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: context.colors.error,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _submitting ? null : () => _respond(dispute),
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit Response'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _threadEntry(String label, String text, List<String> imageUrls) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
              height: 1.4,
            ),
          ),
          if (imageUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: imageUrls.length,
                separatorBuilder: (_, index) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrls[i],
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
}

class _QuoteCard extends StatelessWidget {
  final QuoteModel quote;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _QuoteCard({
    required this.quote,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Full numeric trust score + breakdown already exists on the
          // artisan's own profile (TrustScoreCard) — reuse it instead of
          // denormalizing the score onto the quote doc.
          GestureDetector(
            onTap: () => context.push('/artisan/${quote.artisanId}'),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: context.colors.primarySurface,
                  backgroundImage: quote.artisanProfileImageUrl != null
                      ? NetworkImage(quote.artisanProfileImageUrl!)
                      : null,
                  child: quote.artisanProfileImageUrl == null
                      ? Text(
                          quote.artisanName.isNotEmpty
                              ? quote.artisanName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.colors.primary,
                            fontFamily: 'Inter',
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              quote.artisanName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Inter',
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ),
                          if (quote.artisanVerified) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: context.colors.accent,
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: context.colors.ratingGold,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            quote.artisanRating == 0
                                ? 'New'
                                : quote.artisanRating.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.textSecondary,
                              fontFamily: 'Inter',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.primarySurface,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              quote.artisanTrustTier,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: context.colors.primary,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₦${NumberFormat('#,##0').format(quote.amount)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.colors.primary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    if (quote.materialsCost > 0)
                      Text(
                        'L: ₦${NumberFormat('#,##0').format(quote.laborCost)}  M: ₦${NumberFormat('#,##0').format(quote.materialsCost)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: context.colors.textTertiary,
                          fontFamily: 'Inter',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (quote.artisanTrustScore > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 13, color: context.colors.primary),
                const SizedBox(width: 4),
                Text(
                  'Trust score: ${quote.artisanTrustScore.toStringAsFixed(0)}/100',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${quote.durationDays} day${quote.durationDays == 1 ? '' : 's'} estimated',
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          if (quote.notes != null && quote.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              quote.notes!,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push(
                '/chat/${quote.jobId}',
                extra: {
                  'artisanId': quote.artisanId,
                  'artisanName': quote.artisanName,
                },
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
              label: const Text('Chat'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.error,
                    side: BorderSide(color: context.colors.error),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: context.colors.textInverse,
                  ),
                  child: busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Agreement confirmation section — the "Negotiation Completed /
/// Agreement Confirmation" checkpoint. Shown while job is inChat, above
/// [_AppointmentSection]. Renders one of five states depending on
/// [JobModel.agreementStatus] and which party is viewing:
///   customer, not yet confirmed  → summary form + "Confirm Agreement"
///   customer, pending artisan    → "Waiting for artisan confirmation"
///   artisan,  pending their turn → review card + Accept / Request Changes
///   either party, confirmed      → locked read-only summary
///   artisan, not yet pending     → nothing (they act via chat until the
///                                   customer confirms)
class _AgreementSection extends ConsumerStatefulWidget {
  final JobModel job;
  final bool isCustomer;
  final String currentUserId;

  const _AgreementSection({
    required this.job,
    required this.isCustomer,
    required this.currentUserId,
  });

  @override
  ConsumerState<_AgreementSection> createState() => _AgreementSectionState();
}

class _AgreementSectionState extends ConsumerState<_AgreementSection> {
  late final TextEditingController _scopeCtrl;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _scopeCtrl = TextEditingController(
      text: widget.job.agreementScope ?? widget.job.description,
    );
    _priceCtrl = TextEditingController(
      text: widget.job.agreedAmount != null
          ? widget.job.agreedAmount!.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _scopeCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_scopeCtrl.text.trim().isEmpty) {
      showErrorSnackbar(context, 'Describe the agreed scope of work first.');
      return;
    }
    final price = double.tryParse(_priceCtrl.text.trim());
    final config = ref.read(platformConfigProvider);
    if (!config.meetsMinimum(price ?? widget.job.agreedAmount)) {
      showErrorSnackbar(context,
          'The agreed price must be at least ${config.minJobValueLabel} (the minimum job value for secure payment).');
      return;
    }
    await ref.read(escrowNotifierProvider.notifier).confirmAgreement(
          widget.job.id,
          scope: _scopeCtrl.text.trim(),
          price: price,
        );
    if (!mounted) return;
    if (ref.read(escrowNotifierProvider).hasError) {
      showErrorSnackbar(context, 'Could not confirm the agreement. Please try again.');
    }
  }

  Future<void> _accept() async {
    await ref.read(escrowNotifierProvider.notifier).acceptAgreement(widget.job.id);
    if (!mounted) return;
    if (ref.read(escrowNotifierProvider).hasError) {
      showErrorSnackbar(context, 'Could not accept the agreement. Please try again.');
    }
  }

  Future<void> _requestChanges() async {
    final reason = await _showRequestAgreementChangesDialog(context);
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    await ref.read(escrowNotifierProvider.notifier).requestAgreementChanges(
          widget.job.id,
          reason: reason.trim(),
        );
    if (!mounted) return;
    if (ref.read(escrowNotifierProvider).hasError) {
      showErrorSnackbar(context, 'Could not send the changes request. Please try again.');
    }
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      );

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.colors.textSecondary,
          fontFamily: 'Inter',
          letterSpacing: 0.5,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final escrow = ref.watch(escrowNotifierProvider);
    final loading = escrow.isLoading;
    final agreementStatus = job.agreementStatus ?? AgreementStatus.negotiating;

    if (agreementStatus == AgreementStatus.confirmed) {
      return _buildConfirmedSummary(job);
    }

    if (widget.isCustomer) {
      if (agreementStatus == AgreementStatus.pendingArtisanConfirmation) {
        return _buildWaitingState();
      }
      return _buildCustomerConfirmForm(job, loading, agreementStatus);
    }

    // Artisan view.
    if (agreementStatus == AgreementStatus.pendingArtisanConfirmation) {
      return _buildArtisanReviewCard(job, loading);
    }
    // Still negotiating and it isn't the artisan's turn to act here yet.
    return const SizedBox.shrink();
  }

  Widget _buildCustomerConfirmForm(
    JobModel job,
    bool loading,
    AgreementStatus agreementStatus,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('AGREEMENT SUMMARY'),
          const SizedBox(height: 12),
          if (agreementStatus == AgreementStatus.changesRequested &&
              job.agreementChangesRequestedReason != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.warningSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: context.colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Artisan requested changes: ${job.agreementChangesRequestedReason}',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textPrimary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _scopeCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Scope of work'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Agreed price (₦)',
              helperText: 'Minimum ${ref.watch(platformConfigProvider).minJobValueLabel}',
            ),
          ),
          if (job.confirmedAppointment != null) ...[
            const SizedBox(height: 12),
            Text(
              'Schedule: ${DateFormat('EEE d MMM yyyy, h:mm a').format(job.confirmedAppointment!.toLocal())}',
              style: TextStyle(fontSize: 13, color: context.colors.textSecondary, fontFamily: 'Inter'),
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: loading ? null : _confirm,
            child: loading
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Confirm Agreement'),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Row(
        children: [
          SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Waiting for the artisan to confirm the agreement.',
              style: TextStyle(fontSize: 14, color: context.colors.textPrimary, fontFamily: 'Inter'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtisanReviewCard(JobModel job, bool loading) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 18, color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Customer has confirmed the agreement',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _reviewRow('Service', job.category),
          _reviewRow('Description', job.agreementScope ?? job.description),
          if (job.agreedAmount != null)
            _reviewRow('Agreed price', '₦${NumberFormat('#,##0').format(job.agreedAmount!)}'),
          if (job.confirmedAppointment != null)
            _reviewRow('Schedule',
                DateFormat('EEE d MMM yyyy, h:mm a').format(job.confirmedAppointment!.toLocal())),
          if (job.customerAddress != null) _reviewRow('Location', job.customerAddress!),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: loading ? null : _accept,
            child: loading
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Accept Agreement'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: loading ? null : _requestChanges,
            child: const Text('Request Changes'),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
                letterSpacing: 0.5,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      );

  Widget _buildConfirmedSummary(JobModel job) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, size: 18, color: context.colors.primary),
              const SizedBox(width: 8),
              Text(
                'Agreement Confirmed',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.primary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _reviewRow('Scope', job.agreementScope ?? job.description),
          if (job.agreedAmount != null)
            _reviewRow('Locked price', '₦${NumberFormat('#,##0').format(job.agreedAmount!)}'),
          if (job.confirmedAppointment != null)
            _reviewRow('Schedule',
                DateFormat('EEE d MMM yyyy, h:mm a').format(job.confirmedAppointment!.toLocal())),
        ],
      ),
    );
  }
}

/// Free-text reason dialog for "Request Changes" — same rounded-AlertDialog
/// visual pattern as showCancellationReasonDialog (cancellation_reason_dialog.dart),
/// not reused directly since that one is semantically specific to
/// cancellation (title/buttons/preset reason list don't fit this action).
Future<String?> _showRequestAgreementChangesDialog(BuildContext context) {
  final reasonCtrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Request Changes',
        style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: reasonCtrl,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: 'What would you like to change?',
          hintStyle: TextStyle(color: ctx.colors.textTertiary, fontFamily: 'Inter'),
          filled: true,
          fillColor: ctx.colors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: ctx.colors.borderLight),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(reasonCtrl.text.trim()),
          child: const Text('Send', style: TextStyle(fontFamily: 'Inter')),
        ),
      ],
    ),
  );
}

/// Appointment scheduling section shown while job is inChat.
/// Artisan proposes up to 3 date/time slots; customer picks one.
class _AppointmentSection extends ConsumerStatefulWidget {
  final JobModel job;
  final bool isCustomer;
  final String? currentUserId;

  const _AppointmentSection({
    required this.job,
    required this.isCustomer,
    required this.currentUserId,
  });

  @override
  ConsumerState<_AppointmentSection> createState() =>
      _AppointmentSectionState();
}

class _AppointmentSectionState extends ConsumerState<_AppointmentSection> {
  final List<DateTime> _slots = [];
  bool _submitting = false;

  Future<void> _pickSlot() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _slots.add(dt));
  }

  Future<void> _submitSlots() async {
    if (_slots.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(escrowNotifierProvider.notifier)
          .proposeAppointmentSlots(widget.job.id, _slots);
      if (mounted) setState(() => _slots.clear());
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not propose slots: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmSlot(DateTime slot) async {
    setState(() => _submitting = true);
    try {
      await ref
          .read(escrowNotifierProvider.notifier)
          .confirmAppointmentSlot(widget.job.id, slot);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not confirm slot: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSlots = widget.job.appointmentSlots.isNotEmpty;
    final isConfirmed = widget.job.confirmedAppointment != null;

    if (isConfirmed) return const SizedBox.shrink();

    return Container(
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
              Icon(Icons.calendar_month_outlined,
                  size: 18, color: context.colors.primary),
              const SizedBox(width: 8),
              Text(
                'Appointment',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                  color: context.colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!widget.isCustomer) ...[
            // Artisan view — propose slots
            if (hasSlots) ...[
              Text(
                'You proposed ${widget.job.appointmentSlots.length} slot${widget.job.appointmentSlots.length == 1 ? '' : 's'}. Waiting for customer to confirm.',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 8),
              ...widget.job.appointmentSlots.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${DateFormat('EEE d MMM, h:mm a').format(s.toLocal())}',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textPrimary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  )),
            ] else ...[
              Text(
                'Propose up to 3 available appointment times for this job.',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 10),
              if (_slots.isNotEmpty) ...[
                ..._slots.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 14, color: context.colors.accent),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('EEE d MMM, h:mm a').format(s),
                            style: TextStyle(
                              fontSize: 13,
                              color: context.colors.textPrimary,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  if (_slots.length < 3)
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickSlot,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(_slots.isEmpty ? 'Add Time' : 'Add Another'),
                    ),
                  if (_slots.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submitSlots,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Send to Customer'),
                    ),
                  ],
                ],
              ),
            ],
          ] else ...[
            // Customer view — pick a slot
            if (!hasSlots)
              Text(
                'Waiting for the artisan to propose appointment times.',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              )
            else ...[
              Text(
                'The artisan has proposed these times. Select one to confirm:',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 10),
              ...widget.job.appointmentSlots.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _submitting ? null : () => _confirmSlot(s),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.colors.primary,
                          side: BorderSide(color: context.colors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          DateFormat('EEEE, d MMMM yyyy  •  h:mm a')
                              .format(s.toLocal()),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  )),
            ],
          ],
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.primary
              : context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? context.colors.primary : context.colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : context.colors.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

/// Stage 6 (P-K, policy D9): the exact address is shown to the customer and,
/// once the booking is confirmed, to the assigned artisan. Everyone else —
/// including an artisan still deciding on a booking request — sees only the
/// coarse area. Firestore rules enforce this; the UI just follows them.
class _JobLocationSection extends ConsumerWidget {
  final JobModel job;
  final bool isCustomer;
  const _JobLocationSection({required this.job, required this.isCustomer});

  static const _revealedStatuses = {
    JobStatus.inChat, JobStatus.paymentPending, JobStatus.escrowLocked, JobStatus.inProgress,
    JobStatus.submitted, JobStatus.completed, JobStatus.disputed, JobStatus.resolved,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSeeExact = isCustomer || _revealedStatuses.contains(job.status);
    String? text;
    if (canSeeExact) {
      final private = ref.watch(jobPrivateLocationProvider(job.id)).asData?.value;
      text = (private?['customerAddress'] as String?) ?? job.customerAddress;
    }
    text ??= job.areaLabel != null
        ? '${job.areaLabel} (exact address shared once the booking is confirmed)'
        : null;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Location',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textSecondary, fontFamily: 'Inter')),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(fontSize: 15, color: context.colors.textPrimary, fontFamily: 'Inter')),
        ],
      ),
    );
  }
}
