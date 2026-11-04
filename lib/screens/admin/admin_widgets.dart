import 'package:flutter/material.dart';
import 'admin_palette.dart';

/// Premium stat card — gradient icon chip, animated count, trend pill,
/// clickable to drill into the relevant management section.
class AdminStatCard extends StatelessWidget {
  final AdminPalette palette;
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final double? trendPercent; // null = no comparable history yet
  final VoidCallback? onTap;

  /// Overrides the animated integer counter with static formatted text —
  /// for figures that aren't a plain count (e.g. a currency amount like
  /// Escrow Volume, where an animated raw-integer tick-up reads wrong and
  /// unformatted). [value] is ignored when this is set.
  final String? valueLabel;

  const AdminStatCard({
    super.key,
    required this.palette,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.trendPercent,
    this.onTap,
    this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    final trend = trendPercent;
    final isUp = (trend ?? 0) >= 0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: palette.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [color, color.withValues(alpha: 0.6)],
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  Icon(Icons.more_vert_rounded,
                      size: 18, color: palette.textTertiary),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: palette.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 4),
              if (valueLabel != null)
                Text(
                  valueLabel!,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                    fontFamily: 'Inter',
                  ),
                )
              else
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text(
                    v.round().toString(),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: palette.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              if (trend != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      isUp
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 13,
                      color: isUp ? AdminPalette.green : AdminPalette.red,
                    ),
                    Text(
                      '${trend.abs().toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isUp ? AdminPalette.green : AdminPalette.red,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'vs last week',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textTertiary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared rounded card shell with title + trailing action used by every
/// dashboard section (charts, activity feed, pending actions, health).
class AdminSectionCard extends StatelessWidget {
  final AdminPalette palette;
  final String title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AdminSectionCard({
    super.key,
    required this.palette,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: palette.cardDecoration(),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Small "N" badge used on Pending Actions rows.
class AdminCountBadge extends StatelessWidget {
  final int count;
  final Color color;
  const AdminCountBadge({super.key, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

class AdminPendingActionRow extends StatelessWidget {
  final AdminPalette palette;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback onTap;

  const AdminPendingActionRow({
    super.key,
    required this.palette,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textTertiary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              AdminCountBadge(count: count, color: color),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: palette.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminActivityRow extends StatelessWidget {
  final AdminPalette palette;
  final IconData icon;
  final Color color;
  final String title;
  final String timeLabel;

  const AdminActivityRow({
    super.key,
    required this.palette,
    required this.icon,
    required this.color,
    required this.title,
    required this.timeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timeLabel,
            style: TextStyle(
              fontSize: 11,
              color: palette.textTertiary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}

class AdminCategoryBar extends StatelessWidget {
  final AdminPalette palette;
  final IconData icon;
  final Color color;
  final String label;
  final int value;
  final int maxValue;

  const AdminCategoryBar({
    super.key,
    required this.palette,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue == 0 ? 0.0 : value / maxValue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: ratio),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor: palette.bg2,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}
