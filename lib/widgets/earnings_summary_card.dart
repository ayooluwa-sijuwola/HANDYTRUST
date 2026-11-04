import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'balance_card.dart';

/// Artisan earnings breakdown — Total / Pending Escrow / Released.
///
/// Deliberately three figures, not four. Task 3 named a fourth,
/// "Available balance" — but this backend has no state that means that:
/// payout is fully automatic (processEscrowRelease fires the moment
/// escrow releases and transfers straight to the artisan's bank account),
/// so there is no separate "released but not yet withdrawn" balance for
/// an "available" figure to describe. Inventing one would either just
/// duplicate releasedEarnings under a different label or imply a pull-
/// based withdrawal step that doesn't exist — both are exactly the "fake
/// balance" this pass was told not to create. Released *is* the honest
/// answer to "what can I count as mine right now."
class EarningsSummaryCard extends StatelessWidget {
  final String totalFormatted;
  final String pendingEscrowFormatted;
  final String releasedFormatted;
  final Color pendingColor;
  final Color releasedColor;

  const EarningsSummaryCard({
    super.key,
    required this.totalFormatted,
    required this.pendingEscrowFormatted,
    required this.releasedFormatted,
    required this.pendingColor,
    required this.releasedColor,
  });

  @override
  Widget build(BuildContext context) {
    return BalanceCard(
      stats: [
        BalanceStat(label: 'Total Earnings', value: totalFormatted, valueColor: context.colors.textPrimary),
        BalanceStat(label: 'Pending Escrow', value: pendingEscrowFormatted, valueColor: pendingColor),
        BalanceStat(label: 'Released', value: releasedFormatted, valueColor: releasedColor),
      ],
    );
  }
}
