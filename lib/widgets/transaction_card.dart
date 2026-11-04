import 'package:flutter/material.dart';
import '../theme/app_design_system.dart';
import '../theme/app_theme.dart';

/// One payment row — job title, payment status, date, amount, and
/// (optionally) the job's current workflow phase. Generalizes what was
/// wallet_screen.dart's private _LedgerRow, so any screen showing payment
/// history (customer Wallet, artisan Earnings) uses one implementation.
///
/// Purely presentational, same convention as JobBookingCard/
/// WorkflowStatusCard: the caller resolves the related job and computes
/// [phase] (via WorkflowGateService — never derived in here) and passes
/// already-formatted strings in; this widget makes no Firestore reads and
/// no workflow decisions of its own.
class TransactionCard extends StatelessWidget {
  final String jobTitle;
  final String amountFormatted;
  final String dateFormatted;
  final String statusLabel;
  final Color statusColor;

  /// The related job's current WorkflowGateService phase, e.g. "Job In
  /// Progress" — distinct from [statusLabel], which is the *payment's*
  /// state (In Escrow / Released / ...), not the job's.
  final String? phase;

  final VoidCallback? onTap;

  const TransactionCard({
    super.key,
    required this.jobTitle,
    required this.amountFormatted,
    required this.dateFormatted,
    required this.statusLabel,
    required this.statusColor,
    this.phase,
    this.onTap,
  });

  // Circular status icon — pixel-matched to Stitch's "Recent Transactions"
  // rows (bank/arrow/card/document icon in a tinted circle, not a small
  // colored dot).
  IconData get _statusIcon => switch (statusLabel) {
        'Released' => Icons.arrow_downward_rounded,
        'In Escrow' => Icons.lock_outline_rounded,
        'Pending' => Icons.schedule_rounded,
        'Refunded' => Icons.replay_rounded,
        'Failed' => Icons.error_outline_rounded,
        _ => Icons.receipt_long_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(_statusIcon, size: 18, color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    jobTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    phase != null ? '$dateFormatted · $phase' : dateFormatted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amountFormatted,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: context.colors.textTertiary,
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
