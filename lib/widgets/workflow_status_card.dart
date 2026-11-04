import 'package:flutter/material.dart';
import '../theme/app_design_system.dart';
import '../theme/app_theme.dart';

/// Reusable "what's the current phase, what's next, whose turn is it"
/// card used across the job lifecycle (job_detail_screen.dart) so every
/// stage gets the same clear-next-action treatment instead of a bare
/// button with no framing. One component, not duplicated per-screen markup.
class WorkflowStatusCard extends StatelessWidget {
  /// Short phase label, e.g. "Quote Accepted", "Payment Complete".
  final String phase;

  /// One sentence: what's happening / what this phase means right now.
  final String description;

  /// Who needs to act next — "You" if the viewer is the responsible
  /// party, otherwise the other party's name/role. Null if no one needs
  /// to act (a purely informational phase).
  final String? waitingOn;

  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryLoading;

  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const WorkflowStatusCard({
    super.key,
    required this.phase,
    required this.description,
    this.waitingOn,
    this.primaryLabel,
    this.onPrimary,
    this.primaryLoading = false,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: appCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  phase,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              if (waitingOn != null)
                AppBadge(
                  label: 'Waiting on $waitingOn',
                  color: context.colors.textSecondary,
                  backgroundColor: context.colors.surface,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'Inter',
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
          if (primaryLabel != null || secondaryLabel != null) ...[
            const SizedBox(height: 16),
            if (primaryLabel != null)
              ElevatedButton(
                onPressed: primaryLoading ? null : onPrimary,
                child: primaryLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(primaryLabel!),
              ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: primaryLoading ? null : onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
