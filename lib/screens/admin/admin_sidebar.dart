import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import 'admin_palette.dart';

/// One destination per top-level admin URL (`/admin/<section>`). The enum
/// is the single source of truth for the route path so the sidebar, the
/// router, and deep-link guards can never drift out of sync.
enum AdminSection {
  dashboard,
  users,
  artisans,
  jobs,
  verifications,
  disputes,
  reviews,
  support,
  deletions,
  auditLogs,
  analytics,
  settings;

  String get path => switch (this) {
        AdminSection.dashboard => '/admin/dashboard',
        AdminSection.users => '/admin/users',
        AdminSection.artisans => '/admin/artisans',
        AdminSection.jobs => '/admin/jobs',
        AdminSection.verifications => '/admin/verifications',
        AdminSection.disputes => '/admin/disputes',
        AdminSection.reviews => '/admin/reviews',
        AdminSection.support => '/admin/support',
        AdminSection.deletions => '/admin/deletions',
        AdminSection.auditLogs => '/admin/audit-logs',
        AdminSection.analytics => '/admin/analytics',
        AdminSection.settings => '/admin/settings',
      };

  static AdminSection fromPath(String path) => AdminSection.values.firstWhere(
        (s) => s.path == path,
        orElse: () => AdminSection.dashboard,
      );
}

class AdminNavItem {
  final AdminSection section;
  final IconData icon;
  final String label;
  const AdminNavItem(this.section, this.icon, this.label);
}

const adminNavItems = [
  AdminNavItem(AdminSection.dashboard, Icons.dashboard_rounded, 'Dashboard'),
  AdminNavItem(AdminSection.users, Icons.people_alt_rounded, 'Users'),
  AdminNavItem(AdminSection.artisans, Icons.handyman_rounded, 'Artisans'),
  AdminNavItem(AdminSection.jobs, Icons.work_rounded, 'Jobs'),
  AdminNavItem(AdminSection.verifications, Icons.verified_user_rounded, 'Verifications'),
  AdminNavItem(AdminSection.disputes, Icons.gavel_rounded, 'Disputes'),
  AdminNavItem(AdminSection.reviews, Icons.star_rounded, 'Reviews'),
  AdminNavItem(AdminSection.support, Icons.support_agent_rounded, 'Support Tickets'),
  AdminNavItem(AdminSection.deletions, Icons.person_remove_rounded, 'Deletion Requests'),
  AdminNavItem(AdminSection.auditLogs, Icons.history_rounded, 'Audit Logs'),
  AdminNavItem(AdminSection.analytics, Icons.analytics_rounded, 'Analytics'),
  AdminNavItem(AdminSection.settings, Icons.settings_rounded, 'Settings'),
];

/// Permanent left navigation panel for the admin dashboard. Used both as
/// a fixed-width rail (wide screens) and inside a [Drawer] (narrow screens)
/// — same widget, same behaviour, just a different host.
class AdminSidebar extends ConsumerWidget {
  final AdminSection selectedSection;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onSignOut;

  const AdminSidebar({
    super.key,
    required this.selectedSection,
    required this.onSelect,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AdminPalette.of(ref.watch(themeProvider));
    final admin = ref.watch(currentUserProfileProvider).asData?.value;

    return Container(
      width: 248,
      color: palette.bg1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AdminPalette.purpleIndigoGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.handyman_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  'HandyTrust',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              'ADMIN PANEL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AdminPalette.indigo,
                fontFamily: 'Inter',
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: adminNavItems.length,
              itemBuilder: (context, i) {
                final item = adminNavItems[i];
                final selected = item.section == selectedSection;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelect(item.section),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: selected
                              ? AdminPalette.purpleIndigoGradient
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: AdminPalette.purple
                                        .withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              size: 19,
                              color: selected
                                  ? Colors.white
                                  : palette.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? Colors.white
                                      : palette.textSecondary,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
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
                    decoration: const BoxDecoration(
                      gradient: AdminPalette.purpleIndigoGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (admin?.name.isNotEmpty ?? false)
                            ? admin!.name[0].toUpperCase()
                            : 'A',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          admin?.name ?? 'Admin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                            fontFamily: 'Inter',
                          ),
                        ),
                        Text(
                          'Super Administrator',
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.textTertiary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.logout_rounded,
                        size: 18, color: palette.textTertiary),
                    tooltip: 'Sign out',
                    onPressed: onSignOut,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
