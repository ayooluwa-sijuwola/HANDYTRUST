import 'package:flutter/material.dart';
import '../theme/app_design_system.dart';
import '../theme/app_theme.dart';

/// One labeled money figure — the unit both the Wallet summary card and
/// the Earnings dashboard are built from. Generalizes what was previously
/// wallet_screen.dart's private _SummaryStat, so both screens share one
/// implementation instead of two near-identical ones.
///
/// [valueColor] is used as-is on a light card now (pixel-matched to
/// Stitch's pale green balance card) — callers that previously passed
/// Colors.white for "the neutral figure on a dark card" should pass a dark
/// color instead; see wallet_screen.dart's own callers.
class BalanceStat extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const BalanceStat({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Pale-green card holding a row of [BalanceStat]s, separated by thin
/// dividers — pixel-matched to Stitch's light "Total Funds in Escrow"
/// card (not the dark-navy variant, which was explicitly not chosen for
/// this app's Wallet screen). Shared shell both the customer Wallet
/// summary and the artisan Earnings summary use.
class BalanceCard extends StatelessWidget {
  final List<BalanceStat> stats;

  const BalanceCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < stats.length; i++) {
      if (i > 0) {
        children.add(Container(width: 1, height: 40, color: context.colors.primary.withValues(alpha: 0.15)));
      }
      children.add(Expanded(child: stats[i]));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppGradients.walletBalance,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: children),
    );
  }
}
