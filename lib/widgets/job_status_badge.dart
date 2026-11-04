import 'package:flutter/material.dart';
import '../models/job_model.dart';
import '../theme/app_theme.dart';

class JobStatusBadge extends StatelessWidget {
  final JobStatus status;
  final bool compact;

  const JobStatusBadge({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = _color(context, status);
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: color,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }

  static Color _color(BuildContext context, JobStatus s) => switch (s) {
        JobStatus.requested => context.colors.statusRequested,
        JobStatus.matched => context.colors.statusMatched,
        JobStatus.inChat => context.colors.statusInChat,
        JobStatus.paymentPending => context.colors.statusInProgress,
        JobStatus.escrowLocked => context.colors.statusEscrowLocked,
        JobStatus.inProgress => context.colors.statusInProgress,
        JobStatus.submitted => context.colors.statusSubmitted,
        JobStatus.completed => context.colors.statusCompleted,
        JobStatus.disputed => context.colors.statusDisputed,
        JobStatus.resolved => context.colors.statusResolved,
        JobStatus.cancelled => context.colors.statusResolved,
        JobStatus.expired => context.colors.textTertiary,
      };
}
