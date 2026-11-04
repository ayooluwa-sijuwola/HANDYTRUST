import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/job_model.dart';
import '../providers/escrow_provider.dart';
import '../theme/app_design_system.dart';
import '../theme/app_theme.dart';
import 'error_snackbar.dart';

/// Single, unified job-lifecycle timeline. Replaces three previously
/// overlapping widgets that each rendered a version of the same
/// JobStatus-level progress (JobProgressTracker's compact horizontal
/// stepper, JobTimelineWidget's detailed vertical+timestamp view) plus one
/// genuinely distinct one (JobProgressTimeline's fine-grained inProgress
/// sub-stages, now folded in as a nested detail under the "Work In
/// Progress" step instead of a separate always-visible widget).
///
/// Represents every real lifecycle stage, including the sub-states added
/// after the original three widgets were written (AgreementStatus,
/// SchedulingStatus) — those widgets predated both and had no way to show
/// them, which is exactly the kind of drift consolidating into one place
/// is meant to prevent.
class WorkflowTimeline extends ConsumerWidget {
  final JobModel job;

  /// True: current-phase-only pill (job list rows / dashboards).
  /// False (default): full vertical stepper with timestamps.
  final bool compact;

  const WorkflowTimeline({super.key, required this.job, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCancelled = job.status == JobStatus.cancelled;
    final isDisputeBranch =
        job.status == JobStatus.disputed || job.status == JobStatus.resolved;
    final steps = _buildSteps(job);

    if (compact) {
      return _CompactChip(
        label: isCancelled
            ? 'Cancelled'
            : isDisputeBranch
                ? (job.status == JobStatus.resolved ? 'Resolved' : 'Disputed')
                : _activeLabel(steps),
        icon: isCancelled
            ? Icons.cancel_rounded
            : isDisputeBranch
                ? Icons.gavel_rounded
                : _activeIcon(steps),
        isError: isCancelled || isDisputeBranch,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: appCardDecoration(context, elevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'JOB PROGRESS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textSecondary,
                  letterSpacing: 0.8,
                  fontFamily: 'Inter',
                ),
              ),
              const Spacer(),
              if (!isCancelled && !isDisputeBranch)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.colors.primarySurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _activeLabel(steps),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.colors.primary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(steps.length, (i) {
            final step = steps[i];
            final isLast = i == steps.length - 1;
            final drawConnector = !isLast || isCancelled || isDisputeBranch;
            return _StepRow(
              step: step,
              drawConnector: drawConnector,
              nested: step.isActive && step.key == _StepKey.inProgress
                  ? _InProgressDetail(job: job)
                  : null,
            );
          }),
          if (isDisputeBranch) ...[
            _StepRow(
              step: _TimelineStep(
                key: _StepKey.disputed,
                label: 'Dispute Raised',
                icon: Icons.gavel_outlined,
                status: WorkflowStepStatus.active,
                color: context.colors.error,
              ),
              drawConnector: job.status == JobStatus.resolved,
            ),
            if (job.status == JobStatus.resolved)
              _StepRow(
                step: _TimelineStep(
                  key: _StepKey.resolved,
                  label: 'Dispute Resolved',
                  icon: Icons.balance_outlined,
                  status: WorkflowStepStatus.done,
                  color: context.colors.accent,
                ),
                drawConnector: false,
              ),
          ],
          if (isCancelled) ...[
            _StepRow(
              step: _TimelineStep(
                key: _StepKey.cancelled,
                label: 'Job Cancelled',
                icon: Icons.cancel_outlined,
                status: WorkflowStepStatus.active,
                color: context.colors.error,
              ),
              drawConnector: false,
            ),
            if (job.cancellationReason != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 40, bottom: 10),
                child: Text(
                  'Reason: ${job.cancellationReason}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.error,
                    fontFamily: 'Inter',
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _activeLabel(List<_TimelineStep> steps) =>
      steps.firstWhere((s) => s.isActive, orElse: () => steps.last).label;
  IconData _activeIcon(List<_TimelineStep> steps) =>
      steps.firstWhere((s) => s.isActive, orElse: () => steps.last).icon;

  /// One list, one place every lifecycle stage is defined — including the
  /// two sub-states (agreement, scheduling) the three predecessor widgets
  /// didn't exist to know about. "Scheduled" is only included for jobs
  /// that actually need one (urgency == 'scheduled') — an 'asap' job has
  /// nothing to schedule, so showing an "Awaiting Schedule" step for it
  /// would be actively misleading, not just unnecessary.
  static List<_TimelineStep> _buildSteps(JobModel job) {
    final needsScheduling = job.urgency == 'scheduled';
    final agreementStatus = job.agreementStatus ?? AgreementStatus.negotiating;
    final schedulingStatus =
        job.schedulingStatus ?? SchedulingStatus.awaitingSchedule;

    // Ordinal describing how far along the main path this job has gotten,
    // resolved from real state (not just current status) so a job that's
    // moved past a phase still shows it as done even if we're now on a
    // dispute/cancel branch — same technique the old JobTimelineWidget
    // used, extended to cover the two new sub-stages.
    int reached;
    if (job.completedAt != null) {
      reached = 8;
    } else if (job.submittedAt != null) {
      reached = 7;
    } else if (job.startedAt != null) {
      reached = 6;
    } else if (job.escrowLockedAt != null || job.status == JobStatus.paymentPending) {
      reached = 5;
    } else if (agreementStatus == AgreementStatus.confirmed &&
        (!needsScheduling || schedulingStatus == SchedulingStatus.scheduled)) {
      reached = 4; // agreement + scheduling both satisfied -> ready for payment
    } else if (agreementStatus == AgreementStatus.confirmed) {
      reached = 3; // confirmed, still awaiting schedule
    } else if (job.matchedAt != null) {
      reached = 2; // matched, negotiating
    } else if (job.matchedAt == null && job.status != JobStatus.requested) {
      reached = 1;
    } else {
      reached = 0;
    }

    final isOnMainPath = !job.status.isTerminal &&
        job.status != JobStatus.disputed &&
        job.status != JobStatus.resolved;

    WorkflowStepStatus statusFor(int ordinal) {
      if (ordinal < reached) return WorkflowStepStatus.done;
      if (ordinal == reached) {
        return isOnMainPath ? WorkflowStepStatus.active : WorkflowStepStatus.done;
      }
      return WorkflowStepStatus.pending;
    }

    final steps = <_TimelineStep>[
      _TimelineStep(
        key: _StepKey.requested,
        label: 'Job Posted',
        icon: Icons.post_add_rounded,
        status: statusFor(0),
        timestamp: job.createdAt,
      ),
      _TimelineStep(
        key: _StepKey.matched,
        label: 'Artisan Matched',
        icon: Icons.handshake_outlined,
        status: statusFor(1),
        timestamp: job.matchedAt,
      ),
      _TimelineStep(
        key: _StepKey.negotiating,
        label: 'Negotiating',
        icon: Icons.chat_bubble_outline_rounded,
        status: statusFor(2),
      ),
      _TimelineStep(
        key: _StepKey.agreementConfirmed,
        label: 'Agreement Confirmed',
        icon: Icons.fact_check_outlined,
        status: statusFor(3),
        timestamp: job.agreementArtisanConfirmedAt,
      ),
    ];

    if (needsScheduling) {
      steps.add(_TimelineStep(
        key: _StepKey.scheduled,
        label: 'Scheduled',
        icon: Icons.event_available_outlined,
        status: statusFor(4),
        timestamp: job.schedulingUpdatedAt,
      ));
    }

    steps.addAll([
      _TimelineStep(
        key: _StepKey.escrow,
        label: job.status == JobStatus.paymentPending
            ? 'Confirming Payment'
            : 'Payment Secured',
        icon: Icons.lock_outline_rounded,
        status: statusFor(5),
        timestamp: job.escrowLockedAt,
      ),
      _TimelineStep(
        key: _StepKey.inProgress,
        label: 'Work In Progress',
        icon: Icons.construction_outlined,
        status: statusFor(6),
        timestamp: job.startedAt,
      ),
      _TimelineStep(
        key: _StepKey.submitted,
        label: 'Work Submitted',
        icon: Icons.assignment_turned_in_outlined,
        status: statusFor(7),
        timestamp: job.submittedAt,
        suffix: job.status == JobStatus.submitted && job.autoReleaseAt != null
            ? _AutoReleaseChip(releaseAt: job.autoReleaseAt!)
            : null,
      ),
      _TimelineStep(
        key: _StepKey.completed,
        label: 'Completed',
        icon: Icons.verified_rounded,
        status: statusFor(8),
        timestamp: job.completedAt,
      ),
    ]);

    return steps;
  }
}

enum WorkflowStepStatus { done, active, pending }

enum _StepKey {
  requested,
  matched,
  negotiating,
  agreementConfirmed,
  scheduled,
  escrow,
  inProgress,
  submitted,
  completed,
  disputed,
  resolved,
  cancelled,
}

class _TimelineStep {
  final _StepKey key;
  final String label;
  final IconData icon;
  final WorkflowStepStatus status;
  final DateTime? timestamp;
  final Widget? suffix;
  final Color? color;

  const _TimelineStep({
    required this.key,
    required this.label,
    required this.icon,
    required this.status,
    this.timestamp,
    this.suffix,
    this.color,
  });

  bool get isActive => status == WorkflowStepStatus.active;
}

class _StepRow extends StatelessWidget {
  final _TimelineStep step;
  final bool drawConnector;
  final Widget? nested;

  const _StepRow({required this.step, required this.drawConnector, this.nested});

  @override
  Widget build(BuildContext context) {
    final effectiveColor = step.color ??
        switch (step.status) {
          WorkflowStepStatus.done => context.colors.accent,
          WorkflowStepStatus.active => context.colors.primary,
          WorkflowStepStatus.pending => context.colors.textTertiary,
        };
    final bgColor = switch (step.status) {
      WorkflowStepStatus.done => context.colors.accent,
      WorkflowStepStatus.active => context.colors.primary,
      WorkflowStepStatus.pending => context.colors.surfaceVariant,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: step.color ?? bgColor,
                    shape: BoxShape.circle,
                    border: step.status == WorkflowStepStatus.pending
                        ? Border.all(color: context.colors.border)
                        : null,
                    boxShadow: step.status == WorkflowStepStatus.active
                        ? [
                            BoxShadow(
                              color: effectiveColor.withValues(alpha: 0.3),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    step.status == WorkflowStepStatus.done
                        ? Icons.check_rounded
                        : step.icon,
                    size: 14,
                    color: step.status == WorkflowStepStatus.pending
                        ? context.colors.textTertiary
                        : Colors.white,
                  ),
                ),
                if (drawConnector)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: step.status == WorkflowStepStatus.done
                          ? context.colors.accent.withValues(alpha: 0.4)
                          : context.colors.borderLight,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: drawConnector ? 14 : 0, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: step.status == WorkflowStepStatus.active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: step.status == WorkflowStepStatus.pending
                                ? context.colors.textTertiary
                                : context.colors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                      if (step.timestamp != null)
                        Text(
                          DateFormat('d MMM, HH:mm').format(step.timestamp!),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textTertiary,
                            fontFamily: 'Inter',
                          ),
                        ),
                    ],
                  ),
                  if (step.suffix != null) ...[
                    const SizedBox(height: 4),
                    step.suffix!,
                  ],
                  if (nested != null) ...[
                    const SizedBox(height: 10),
                    nested!,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The fine-grained JobProgressStage sub-steps, folded in as a nested
/// detail under the "Work In Progress" step instead of a separate
/// always-mounted widget — this is the one part of the three predecessor
/// widgets that showed genuinely different information (not JobStatus-level
/// duplication), so it's preserved, not dropped, just relocated.
class _InProgressDetail extends ConsumerWidget {
  final JobModel job;
  const _InProgressDetail({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stages = JobProgressStage.values;
    final currentStep = job.progressStage?.step ?? -1;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: stages.map((s) {
              final isDone = s.step <= currentStep;
              final isActive = s.step == currentStep;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDone ? context.colors.primary : context.colors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: isDone
                      ? null
                      : Border.all(color: context.colors.border),
                ),
                child: Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isDone ? Colors.white : context.colors.textTertiary,
                    fontFamily: 'Inter',
                  ),
                ),
              );
            }).toList(),
          ),
          if (job.status == JobStatus.inProgress) ...[
            const SizedBox(height: 10),
            _AdvanceButton(job: job, currentStep: currentStep, stages: stages),
          ],
        ],
      ),
    );
  }
}

class _AdvanceButton extends ConsumerStatefulWidget {
  final JobModel job;
  final int currentStep;
  final List<JobProgressStage> stages;

  const _AdvanceButton({
    required this.job,
    required this.currentStep,
    required this.stages,
  });

  @override
  ConsumerState<_AdvanceButton> createState() => _AdvanceButtonState();
}

class _AdvanceButtonState extends ConsumerState<_AdvanceButton> {
  bool _loading = false;

  Future<void> _advance(JobProgressStage next) async {
    setState(() => _loading = true);
    try {
      await ref.read(escrowNotifierProvider.notifier).updateProgress(widget.job.id, next);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not update progress: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextStep = widget.currentStep + 1;
    final isAtStart = widget.currentStep < 0;
    final isAtEnd = nextStep >= widget.stages.length;

    if (isAtEnd) {
      return Text(
        'All stages completed. Submit the job when ready.',
        style: TextStyle(
          fontSize: 11,
          color: context.colors.textSecondary,
          fontFamily: 'Inter',
        ),
      );
    }

    final nextStage = isAtStart ? widget.stages[0] : widget.stages[nextStep];
    final label = isAtStart ? 'Start: ${nextStage.label}' : 'Advance to: ${nextStage.label}';

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : () => _advance(nextStage),
        icon: _loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.arrow_forward_rounded, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _AutoReleaseChip extends StatelessWidget {
  final DateTime releaseAt;
  const _AutoReleaseChip({required this.releaseAt});

  @override
  Widget build(BuildContext context) {
    final remaining = releaseAt.difference(DateTime.now());
    final isOverdue = remaining.isNegative;
    final label = isOverdue ? 'Auto-release imminent' : _formatDuration(remaining);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOverdue ? context.colors.errorSurface : context.colors.warningSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isOverdue ? context.colors.error : context.colors.warning)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined,
              size: 11, color: isOverdue ? context.colors.error : context.colors.warning),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isOverdue ? context.colors.error : context.colors.warning,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inDays >= 1) {
      final hours = d.inHours - d.inDays * 24;
      return 'Auto-release in ${d.inDays}d ${hours}h';
    }
    if (d.inHours >= 1) return 'Auto-release in ${d.inHours}h ${d.inMinutes % 60}m';
    return 'Auto-release in ${d.inMinutes}m';
  }
}

class _CompactChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isError;
  const _CompactChip({required this.label, required this.icon, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? context.colors.error : context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}
