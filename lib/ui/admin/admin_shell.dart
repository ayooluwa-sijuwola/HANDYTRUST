import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/admin_catalog.dart';
import '../../models/job_model.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dispute_provider.dart';
import '../../providers/support_ticket_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/verification_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../theme/ht_theme.dart';
import 'admin_kit.dart';

/// Admin sections and their URLs (deep-linkable; `/admin` → dashboard).
enum AdminSection {
  dashboard, analytics, users, artisans, verifications, jobs, disputes, support, reviews, deletions, finance, auditLogs, settings;

  String get path => switch (this) {
        AdminSection.auditLogs => '/admin/audit-logs',
        _ => '/admin/$name',
      };

  String get label => switch (this) {
        AdminSection.dashboard => 'Dashboard',
        AdminSection.analytics => 'Analytics',
        AdminSection.users => 'Users',
        AdminSection.artisans => 'Artisans',
        AdminSection.verifications => 'Verifications',
        AdminSection.jobs => 'Jobs',
        AdminSection.disputes => 'Disputes',
        AdminSection.support => 'Support',
        AdminSection.reviews => 'Reviews',
        AdminSection.deletions => 'Deletion requests',
        AdminSection.finance => 'Finance',
        AdminSection.auditLogs => 'Audit logs',
        AdminSection.settings => 'Settings',
      };

  IconData get icon => switch (this) {
        AdminSection.dashboard => Icons.space_dashboard_outlined,
        AdminSection.analytics => Icons.insights_rounded,
        AdminSection.users => Icons.people_outline_rounded,
        AdminSection.artisans => Icons.handyman_outlined,
        AdminSection.verifications => Icons.verified_user_outlined,
        AdminSection.jobs => Icons.work_outline_rounded,
        AdminSection.disputes => Icons.gavel_rounded,
        AdminSection.support => Icons.support_agent_rounded,
        AdminSection.reviews => Icons.star_outline_rounded,
        AdminSection.deletions => Icons.person_remove_outlined,
        AdminSection.finance => Icons.account_balance_outlined,
        AdminSection.auditLogs => Icons.history_rounded,
        AdminSection.settings => Icons.settings_outlined,
      };

  static AdminSection fromPath(String path) => AdminSection.values.firstWhere((s) => s.path == path, orElse: () => AdminSection.dashboard);
}

const _groups = <(String, List<AdminSection>)>[
  ('Overview', [AdminSection.dashboard, AdminSection.analytics]),
  ('People', [AdminSection.users, AdminSection.artisans, AdminSection.verifications]),
  ('Operations', [AdminSection.jobs, AdminSection.disputes, AdminSection.support, AdminSection.reviews, AdminSection.deletions]),
  ('Finance', [AdminSection.finance]),
  ('Compliance', [AdminSection.auditLogs]),
];

/// Work waiting for an admin, per section (genuine counts of loaded queues).
final adminPendingCountsProvider = Provider<Map<AdminSection, int>>((ref) {
  int n<T>(AsyncValue<List<T>> a) => a.asData?.value.length ?? 0;
  return {
    AdminSection.artisans: n(ref.watch(adminPendingArtisansProvider)),
    AdminSection.verifications: n(ref.watch(pendingVerificationsProvider)),
    AdminSection.disputes: n(ref.watch(openDisputesProvider)),
    AdminSection.support: ref.watch(allTicketsProvider).asData?.value.where((t) => t.status == 'open').length ?? 0,
    AdminSection.deletions: ref.watch(adminDeletionRequestsProvider).asData?.value.where((d) => d['status'] != 'resolved').length ?? 0,
  };
});

/// Persistent admin frame (ShellRoute): navigation + top bar around the
/// active section. The isAdmin check here is a UI gate only; firestore.rules
/// and the admin callables enforce admin access independently.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final isAdmin = ref.watch(isAdminProvider);
    return isAdmin.when(
      loading: () => Scaffold(backgroundColor: p.background, body: const HtLoadingView(label: 'Checking admin access…')),
      error: (e, _) => Scaffold(backgroundColor: p.background, body: Center(child: HtErrorView(message: 'Admin access could not be checked.', onRetry: () => ref.invalidate(isAdminProvider)))),
      data: (ok) => ok ? _AdminFrame(child: child) : const _NotAuthorised(),
    );
  }
}

class _NotAuthorised extends StatelessWidget {
  const _NotAuthorised();
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Scaffold(
      backgroundColor: p.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: HtEmptyView(
            icon: Icons.lock_outline_rounded,
            title: 'Administrators only',
            message: 'This account doesn’t have admin access.',
            action: HtSmallPrimaryButton(label: 'Back to app', onPressed: () => context.go('/home')),
          ),
        ),
      ),
    );
  }
}

class _AdminFrame extends ConsumerWidget {
  const _AdminFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final current = AdminSection.fromPath(GoRouterState.of(context).uri.path);
    final w = MediaQuery.of(context).size.width;
    final counts = ref.watch(adminPendingCountsProvider);
    void go(AdminSection s) => context.go(s.path);

    if (w < kAdminTablet) {
      return Scaffold(
        backgroundColor: p.background,
        drawer: Drawer(backgroundColor: p.surface, child: SafeArea(child: _NavList(current: current, counts: counts, onSelect: (s) {
          Navigator.of(context).pop();
          go(s);
        }))),
        appBar: AppBar(
          backgroundColor: p.background,
          surfaceTintColor: Colors.transparent,
          foregroundColor: p.textPrimary,
          titleSpacing: 0,
          title: Text(current.label, style: HtType.cardTitle(p.textPrimary)),
          actions: const [_SearchButton(), _BellButton(), _ThemeButton(), SizedBox(width: 6)],
        ),
        body: SafeArea(top: false, child: child),
      );
    }

    final rail = w < kAdminWide;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Row(children: [
          Container(
            width: rail ? 76 : 248,
            decoration: BoxDecoration(color: p.surface, border: Border(right: BorderSide(color: p.border))),
            child: rail ? _Rail(current: current, counts: counts, onSelect: go) : _NavList(current: current, counts: counts, onSelect: go),
          ),
          Expanded(
            child: Column(children: [
              Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
                child: Row(children: [
                  const Expanded(child: _SearchBox()),
                  const SizedBox(width: 12),
                  const _BellButton(),
                  const _ThemeButton(),
                  const SizedBox(width: 8),
                  HtSecondaryButton(label: 'Back to app', icon: Icons.open_in_new_rounded, dense: true, onPressed: () => context.go('/home')),
                ]),
              ),
              Expanded(child: child),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle), child: Icon(Icons.verified_user_rounded, size: 20, color: p.accentStrong)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('HandyTrust', style: HtType.cardTitle(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('ADMIN', style: HtType.caps(p.textMuted).copyWith(fontSize: 9.5)),
          ]),
        ),
      ]),
    );
  }
}

class _NavList extends StatelessWidget {
  const _NavList({required this.current, required this.counts, required this.onSelect});
  final AdminSection current;
  final Map<AdminSection, int> counts;
  final ValueChanged<AdminSection> onSelect;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    Widget item(AdminSection s) {
      final active = s == current;
      final n = counts[s] ?? 0;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: Material(
          color: active ? p.navActive : Colors.transparent,
          borderRadius: BorderRadius.circular(HtRadius.tile),
          child: InkWell(
            borderRadius: BorderRadius.circular(HtRadius.tile),
            onTap: () => onSelect(s),
            child: Semantics(
              selected: active,
              button: true,
              label: n > 0 ? '${s.label}, $n waiting' : s.label,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(children: [
                  Icon(s.icon, size: 19, color: active ? p.onNavActive : p.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(s.label, style: HtType.smallStrong(active ? p.onNavActive : p.textPrimary).copyWith(fontSize: 13.5))),
                  if (n > 0) AdminCountBadge(n),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _Brand(),
      Expanded(
        child: ListView(children: [
          for (final (label, items) in _groups) ...[
            Padding(padding: const EdgeInsets.fromLTRB(22, 14, 22, 6), child: Text(label.toUpperCase(), style: HtType.caps(p.textMuted).copyWith(fontSize: 10))),
            for (final s in items) item(s),
          ],
        ]),
      ),
      Divider(height: 1, color: p.border),
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: item(AdminSection.settings)),
    ]);
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.current, required this.counts, required this.onSelect});
  final AdminSection current;
  final Map<AdminSection, int> counts;
  final ValueChanged<AdminSection> onSelect;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final all = [for (final g in _groups) ...g.$2, AdminSection.settings];
    return ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
      for (final s in all)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
          child: Tooltip(
            message: s.label,
            child: Material(
              color: s == current ? p.navActive : Colors.transparent,
              borderRadius: BorderRadius.circular(HtRadius.tile),
              child: InkWell(
                borderRadius: BorderRadius.circular(HtRadius.tile),
                onTap: () => onSelect(s),
                child: SizedBox(
                  height: 44,
                  child: Badge(
                    isLabelVisible: (counts[s] ?? 0) > 0,
                    label: Text('${counts[s] ?? 0}'),
                    backgroundColor: p.accentStrong,
                    textColor: p.onPrimary,
                    child: Center(child: Icon(s.icon, size: 21, color: s == current ? p.onNavActive : p.textSecondary)),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _ThemeButton extends ConsumerWidget {
  const _ThemeButton();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(themeProvider) == ThemeMode.dark;
    return IconButton(
      tooltip: dark ? 'Light mode' : 'Dark mode',
      onPressed: () => ref.read(themeProvider.notifier).toggle(),
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: context.ht.textSecondary),
    );
  }
}

// ─── Notifications (pending work) ───────────────────────────────────────────

class _BellButton extends ConsumerWidget {
  const _BellButton();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(adminPendingCountsProvider);
    final alerts = ref.watch(adminAlertsProvider).asData?.value.length ?? 0;
    final total = counts.values.fold(0, (a, b) => a + b) + alerts;
    return IconButton(
      tooltip: total > 0 ? 'Admin notifications ($total)' : 'Admin notifications',
      onPressed: () => showAdminNotifications(context),
      icon: Badge(isLabelVisible: total > 0, label: Text('$total'), child: Icon(Icons.notifications_none_rounded, color: context.ht.textSecondary)),
    );
  }
}

/// What is waiting for an admin, each opening its section (ad15).
Future<void> showAdminNotifications(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.ht.surface,
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final p = ctx.ht;
      final counts = ref.watch(adminPendingCountsProvider);
      final alerts = ref.watch(adminAlertsProvider).asData?.value ?? const [];
      final rows = <(IconData, String, int, AdminSection)>[
        (Icons.report_gmailerrorred_rounded, 'Operational alerts', alerts.length, AdminSection.dashboard),
        (Icons.handyman_outlined, 'Artisan applications', counts[AdminSection.artisans] ?? 0, AdminSection.artisans),
        (Icons.verified_user_outlined, 'Verification requests', counts[AdminSection.verifications] ?? 0, AdminSection.verifications),
        (Icons.gavel_rounded, 'Open disputes', counts[AdminSection.disputes] ?? 0, AdminSection.disputes),
        (Icons.support_agent_rounded, 'Open support tickets', counts[AdminSection.support] ?? 0, AdminSection.support),
        (Icons.person_remove_outlined, 'Deletion requests', counts[AdminSection.deletions] ?? 0, AdminSection.deletions),
      ];
      final waiting = rows.where((r) => r.$3 > 0).toList();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Waiting for an admin', style: HtType.sectionTitle(p.textPrimary)),
            const SizedBox(height: 8),
            if (waiting.isEmpty)
              const HtEmptyView(icon: Icons.task_alt_rounded, title: 'All clear', message: 'Nothing is waiting for review.')
            else
              for (final (icon, label, n, section) in waiting)
                HtMenuRow(icon: icon, title: label, trailing: AdminCountBadge(n), onTap: () {
                  Navigator.of(ctx).pop();
                  ctx.go(section.path);
                }),
          ]),
        ),
      );
    }),
  );
}

// ─── Search (ad14) ──────────────────────────────────────────────────────────

class _SearchBox extends StatelessWidget {
  const _SearchBox();
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: p.input,
          borderRadius: BorderRadius.circular(HtRadius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(HtRadius.pill),
            onTap: () => showAdminSearch(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(children: [
                Icon(Icons.search_rounded, size: 19, color: p.textMuted),
                const SizedBox(width: 10),
                Flexible(child: Text('Search users, jobs, sections…', style: HtType.small(p.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton();
  @override
  Widget build(BuildContext context) => IconButton(tooltip: 'Search', onPressed: () => showAdminSearch(context), icon: Icon(Icons.search_rounded, color: context.ht.textSecondary));
}

/// Searches section names, the loaded users (name, email) and jobs
/// (description, category, reference). Results open the section with the
/// record selected (`?focus=`).
Future<void> showAdminSearch(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const Dialog(insetPadding: EdgeInsets.all(20), child: SizedBox(width: 560, height: 520, child: _SearchPanel())),
  );
}

class _SearchPanel extends ConsumerStatefulWidget {
  const _SearchPanel();
  @override
  ConsumerState<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<_SearchPanel> {
  final _q = TextEditingController();
  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final q = _q.text.trim().toLowerCase();
    final users = ref.watch(adminUsersProvider).asData?.value ?? const <UserModel>[];
    final jobs = ref.watch(adminJobsProvider).asData?.value ?? const <JobModel>[];
    final sections = q.isEmpty ? const <AdminSection>[] : AdminSection.values.where((s) => s.label.toLowerCase().contains(q)).toList();
    final u = q.isEmpty ? const <UserModel>[] : users.where((x) => x.name.toLowerCase().contains(q) || (x.email ?? '').toLowerCase().contains(q)).take(8).toList();
    final j = q.isEmpty
        ? const <JobModel>[]
        : jobs.where((x) => x.description.toLowerCase().contains(q) || x.category.toLowerCase().contains(q) || HtFormat.bookingRef(x.id).toLowerCase().contains(q) || x.id.toLowerCase().contains(q)).take(8).toList();
    void open(String path) {
      Navigator.of(context).pop();
      context.go(path);
    }

    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(HtRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _q,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: HtType.body(p.textPrimary),
            decoration: htInputDecoration(context, hint: 'Search users, jobs, references, sections', prefix: Icon(Icons.search_rounded, color: p.textMuted)),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: q.isEmpty
                ? Center(child: Text('Type to search the latest 200 users and jobs.', style: HtType.small(p.textMuted)))
                : (sections.isEmpty && u.isEmpty && j.isEmpty)
                    ? const HtEmptyView(icon: Icons.search_off_rounded, title: 'No results')
                    : ListView(children: [
                        if (sections.isNotEmpty) adminSection(context, 'Sections'),
                        for (final s in sections) HtMenuRow(icon: s.icon, title: s.label, onTap: () => open(s.path)),
                        if (u.isNotEmpty) adminSection(context, 'Users'),
                        for (final x in u) HtMenuRow(icon: Icons.person_outline_rounded, title: x.name, subtitle: x.email, onTap: () => open('${AdminSection.users.path}?focus=${x.uid}')),
                        if (j.isNotEmpty) adminSection(context, 'Jobs'),
                        for (final x in j)
                          HtMenuRow(icon: Icons.work_outline_rounded, title: '#${HtFormat.bookingRef(x.id)} · ${x.category}', subtitle: x.description, onTap: () => open('${AdminSection.jobs.path}?focus=${x.id}')),
                      ]),
          ),
        ]),
      ),
    );
  }
}

/// Selected record from a `?focus=` deep link.
String? adminFocus(BuildContext context) => GoRouterState.of(context).uri.queryParameters['focus'];

/// Alert severity → tone.
HtTone alertTone(AlertSeverity s) => switch (s) {
      AlertSeverity.actionRequired => HtTone.danger,
      AlertSeverity.needsAttention => HtTone.warning,
      AlertSeverity.information => HtTone.neutral,
    };
