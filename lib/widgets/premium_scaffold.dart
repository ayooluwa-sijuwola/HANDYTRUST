import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_design_system.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import 'user_avatar.dart';

/// One bottom-nav item: icon + label, matching Stitch's own nav bar
/// exactly. Icon choice is the one unavoidable approximation in this
/// pixel-match pass — Stitch's source screens are raster images, not
/// vector icon assets, so these are the closest Material equivalents by
/// shape/meaning, not a literal asset match.
class NavBarItem {
  final IconData icon;
  final String label;
  const NavBarItem({required this.icon, required this.label});
}

/// The 4-tab bottom navigation shell used for the main app screens.
///
/// Pixel-matched to the Stitch reference's nav bar (design/
/// STITCH_IMPLEMENTATION_AUDIT.md): icon stacked above label — both
/// always visible, not label-only-when-selected — with the active tab's
/// icon sitting on a small filled green circle, not a wide pill spanning
/// icon+label. [items] is caller-supplied because Stitch specifies
/// different tab sets per role (Discovery/Bookings/Wallet/Profile for
/// customers, Find Jobs/My Jobs/Inbox/Profile for artisans) rather than
/// one fixed set for both, per home_screen.dart.
class MainShellScreen extends StatefulWidget {
  final List<Widget> tabs;
  final List<NavBarItem> items;
  final int initialTab;
  final ValueChanged<int>? onTabChange;

  const MainShellScreen({
    super.key,
    required this.tabs,
    required this.items,
    this.initialTab = 0,
    this.onTabChange,
  });

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  late int _currentTab;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
  }

  void _onTabTap(int index) {
    if (_currentTab == index) return;
    setState(() => _currentTab = index);
    widget.onTabChange?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    // Sidebar replaces the bottom bar from the tablet breakpoint up, not
    // just at full desktop width — collapsed (icon-only) between tablet
    // and desktop, expanded (icon+label) at/above desktop. Previously this
    // branched on isDesktop alone, so the 700-1100 tablet band silently
    // fell through to the mobile bottom-nav bar instead of the collapsed
    // sidebar breakpoints.dart's own doc comment describes.
    final showSidebar = context.isTablet;
    final collapsed = context.isTabletOnly;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: context.colors.background,
        body: showSidebar
            ? Row(
                children: [
                  _DesktopSidebar(
                    items: widget.items,
                    currentTab: _currentTab,
                    onTabTap: _onTabTap,
                    collapsed: collapsed,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
                        child: IndexedStack(index: _currentTab, children: widget.tabs),
                      ),
                    ),
                  ),
                ],
              )
            : IndexedStack(index: _currentTab, children: widget.tabs),
        bottomNavigationBar: showSidebar
            ? null
            : _FlatNavBar(
                items: widget.items,
                currentTab: _currentTab,
                onTabTap: _onTabTap,
              ),
      ),
    );
  }
}

/// Desktop/web nav — a persistent left sidebar replacing the bottom bar
/// above [AppBreakpoints.desktop]. No Stitch reference exists for web (by
/// explicit instruction); this reuses the mobile design system's tokens
/// (colors, type, the same [NavBarItem] set per role) rather than
/// inventing a new visual language, while using a layout shape — a fixed
/// vertical rail — that's standard for desktop web apps and was never
/// going to be a literal stretch of the mobile bottom bar.
class _DesktopSidebar extends ConsumerWidget {
  final List<NavBarItem> items;
  final int currentTab;
  final ValueChanged<int> onTabTap;
  final bool collapsed;

  const _DesktopSidebar({
    required this.items,
    required this.currentTab,
    required this.onTabTap,
    required this.collapsed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider).asData?.value;
    return Container(
      width: collapsed ? 76 : 232,
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: collapsed ? 12 : 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          right: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.borderLight),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            child: Row(
              mainAxisAlignment:
                  collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: context.colors.primary,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.handyman_rounded, color: Colors.white, size: 18),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Text(
                    'HandyTrust',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Inter',
                      color: context.colors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          for (var i = 0; i < items.length; i++) ...[
            _SidebarItem(
              item: items[i],
              selected: i == currentTab,
              collapsed: collapsed,
              onTap: () => onTabTap(i),
            ),
            const SizedBox(height: 4),
          ],
          const Spacer(),
          Divider(height: 1, color: isDark ? AppColors.darkBorder : AppColors.borderLight),
          const SizedBox(height: 12),
          // User profile summary — the sidebar's one piece of state that
          // isn't a NavBarItem, so it's fetched here directly rather than
          // prop-drilled through MainShellScreen's per-role item lists.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 4),
            child: Row(
              mainAxisAlignment:
                  collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                UserAvatar(
                  photoUrl: user?.photoUrl,
                  displayName: user?.displayUsername ?? '',
                  size: 32,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      user?.displayUsername ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SidebarItem(
            item: const NavBarItem(icon: Icons.logout_rounded, label: 'Log Out'),
            selected: false,
            collapsed: collapsed,
            danger: true,
            onTap: () => ref.read(authNotifierProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final NavBarItem item;
  final bool selected;
  final bool collapsed;
  final bool danger;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger
        ? context.colors.error
        : selected
            ? context.colors.primary
            : context.colors.textSecondary;
    final row = Row(
      mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Icon(item.icon, size: 20, color: fg),
        if (!collapsed) ...[
          const SizedBox(width: 12),
          Text(
            item.label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: danger ? fg : (selected ? fg : context.colors.textPrimary),
            ),
          ),
        ],
      ],
    );
    return Material(
      color: selected ? context.colors.primarySurface : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Tooltip(
          message: collapsed ? item.label : '',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: row,
          ),
        ),
      ),
    );
  }
}

class _FlatNavBar extends StatelessWidget {
  final List<NavBarItem> items;
  final int currentTab;
  final ValueChanged<int> onTabTap;

  const _FlatNavBar({
    required this.items,
    required this.currentTab,
    required this.onTabTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.borderLight,
          ),
        ),
      ),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              _NavItem(
                icon: items[i].icon,
                label: items[i].label,
                index: i,
                currentTab: currentTab,
                onTap: onTabTap,
              ),
          ],
        ),
      ),
    );
  }
}

/// Stitch's own nav bar pattern (design/STITCH_IMPLEMENTATION_AUDIT.md):
/// icon stacked above label, both always visible — unlike the previous
/// pill-that-only-shows-the-label-when-selected design. The active tab's
/// icon sits on a small filled circle; the label turns primary-green and
/// bold. Inactive tabs are plain gray icon+label, no container.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentTab;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentTab,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: AppAnimations.fast,
              curve: AppAnimations.defaultCurve,
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? context.colors.primary : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.white : context.colors.textTertiary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? context.colors.primary : context.colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
