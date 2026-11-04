import 'package:flutter/material.dart';
import '../theme/app_design_system.dart';
import '../theme/app_theme.dart';

/// One tab in a [PillTabSelector] — a label and an optional count shown in
/// parentheses (e.g. "Active (2)").
class PillTabItem {
  final String label;
  final int? count;

  const PillTabItem(this.label, {this.count});
}

/// Segmented pill-tab selector — the "Active (2) / Completed (14) / Drafts
/// (1)" pattern from the Stitch My Bookings screen. Purely presentational:
/// the caller owns which index is selected and what changing it means, this
/// widget has no opinion about what the tabs filter.
class PillTabSelector extends StatelessWidget {
  final List<PillTabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const PillTabSelector({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _PillTab(
              item: tabs[i],
              selected: i == selectedIndex,
              onTap: () => onChanged(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  final PillTabItem item;
  final bool selected;
  final VoidCallback onTap;

  const _PillTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = item.count != null ? '${item.label} (${item.count})' : item.label;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppAnimations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? context.colors.navy : context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.full),
          // Same reasoning as CommitButton: context.colors.navy is already
          // lifted above the page in dark mode, but a hairline border
          // guarantees the selected pill reads as raised, not as a gap.
          border: (selected && isDark)
              ? Border.all(color: Colors.white.withValues(alpha: 0.10))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? context.colors.onNavy : context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
