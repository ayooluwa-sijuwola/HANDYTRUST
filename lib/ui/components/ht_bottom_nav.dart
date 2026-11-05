import 'package:flutter/material.dart';

import '../theme/ht_theme.dart';

class HtNavItem {
  const HtNavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Floating pill bottom navigation (references 4, 5, 6, 19, 21, 22): icon
/// above label, the active item in a filled pill.
class HtBottomNav extends StatelessWidget {
  const HtBottomNav({super.key, required this.items, required this.current, required this.onTap});
  final List<HtNavItem> items;
  final int current;
  final ValueChanged<int> onTap;

  static const customerItems = [
    HtNavItem(Icons.explore_outlined, 'Discovery'),
    HtNavItem(Icons.calendar_month_outlined, 'Bookings'),
    HtNavItem(Icons.account_balance_wallet_outlined, 'Payments'),
    HtNavItem(Icons.person_outline_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        height: 66,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: p.navBar,
          borderRadius: BorderRadius.circular(33),
          border: Border.all(color: p.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.07), blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == current,
                  button: true,
                  label: items[i].label,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: i == current
                          ? BoxDecoration(
                              gradient: p.isDark ? p.primary : null,
                              color: p.isDark ? null : p.navActive,
                              borderRadius: BorderRadius.circular(32),
                              boxShadow: [BoxShadow(color: p.primaryGlow, blurRadius: 16, offset: const Offset(0, 4))],
                            )
                          : null,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(items[i].icon, size: 22, color: i == current ? p.onNavActive : p.textSecondary),
                          const SizedBox(height: 4),
                          Text(
                            items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HtType.smallStrong(i == current ? p.onNavActive : p.textSecondary).copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
