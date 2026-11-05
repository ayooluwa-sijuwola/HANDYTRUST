import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/services/admin_audit_service.dart';
import '../../core/services/admin_finance_service.dart';
import '../../core/services/artisan_eligibility.dart';
import '../../core/services/trust_score_service.dart';
import '../../models/admin_audit_log_model.dart';
import '../../models/artisan_model.dart';
import '../../models/dispute_model.dart';
import '../../models/job_model.dart';
import '../../models/payment_model.dart';
import '../../models/review_model.dart';
import '../../models/support_ticket_model.dart';
import '../../models/user_model.dart';
import '../../models/verification_model.dart';
import '../../core/utils/safe_firestore.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/dispute_provider.dart';
import '../../providers/escrow_provider.dart' show jobPrivateLocationProvider;
import '../../providers/quote_provider.dart';
import '../../providers/review_provider.dart';
import '../../providers/support_ticket_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/verification_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';
import '../../widgets/job_status_badge.dart';
import '../../widgets/review_tile.dart';
import 'admin_charts.dart';
import 'admin_data_table.dart';
import 'admin_finance_dialogs.dart';
import 'admin_palette.dart';
import 'admin_sidebar.dart';
import 'admin_widgets.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _allUsersProvider = StreamProvider<List<UserModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(200),
    (d) => UserModel.fromJson({...d.data(), 'uid': d.id}),
    debugLabel: 'allUsers',
  );
});

/// All jobs, newest-first — drives the admin Jobs tab. isAdmin() already
/// grants full /jobs read access (see firestore.rules); no rule change
/// needed. No orderBy+where combo, same composite-index-avoidance pattern
/// as every other admin list provider.
final _allJobsProvider = StreamProvider<List<JobModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('jobs')
        .orderBy('createdAt', descending: true)
        .limit(200),
    (d) => JobModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'allJobs',
  );
});

/// Resolves display names for a batch of user/artisan uids (both live in
/// /users — even artisans get a /users doc at signup), for the Jobs tab's
/// "Customer"/"Assigned artisan" columns and name search. Keyed by a sorted,
/// comma-joined string (not the raw List) so Riverpod actually caches
/// repeat lookups for the same set of ids instead of refetching on every
/// snapshot tick.
final _jobPeopleNamesProvider =
    FutureProvider.family<Map<String, String>, String>((ref, idsKey) async {
      if (idsKey.isEmpty) return const {};
      final ids = idsKey.split(',');
      final result = <String, String>{};
      for (var i = 0; i < ids.length; i += 30) {
        final chunk = ids.sublist(
          i,
          (i + 30 > ids.length) ? ids.length : i + 30,
        );
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          result[doc.id] = (doc.data()['name'] as String?) ?? '';
        }
      }
      return result;
    });

final _pendingArtisansProvider = StreamProvider<List<ArtisanModel>>((ref) {
  // No orderBy on the query itself: where(approvalStatus) + orderBy(createdAt)
  // on different fields requires a Firestore composite index that was never
  // deployed for this project. Sorting client-side avoids needing one at
  // all — same pattern already used by every other admin/job list provider.
  // safeStream is still the right wrapper on top: it protects against any
  // OTHER stream-level failure (permission, offline), not just this one.
  return safeStream(
    FirebaseFirestore.instance
        .collection('artisans')
        .where('approvalStatus', isEqualTo: 'pending'),
    (d) => ArtisanModel.fromJson({...d.data(), 'uid': d.id}),
    debugLabel: 'pendingArtisans',
  ).map(
    (artisans) => artisans..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  );
});

final _deletionRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('account_deletion_requests')
      .orderBy('requestedAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => Map<String, dynamic>.from({...d.data(), 'uid': d.id}))
          .toList());
});

/// Operational alerts written by Cloud Functions (reconcileStuckEscrowReleases,
/// _alertAdminDispute in functions/index.js) — see design/STITCH_ADMIN_AUDIT.md.
/// The two writers use different shapes (stuck_escrow_release vs
/// dispute_from_job), so a raw Map is the honest representation here rather
/// than forcing a single model onto two different payloads — same pattern
/// already used by [_deletionRequestsProvider] for the same reason.
final _adminAlertsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('admin_alerts')
        .where('resolved', isEqualTo: false)
        .limit(100),
    (d) => Map<String, dynamic>.from({...d.data(), 'id': d.id}),
    debugLabel: 'adminAlerts',
  ).map((alerts) => alerts
    ..sort((a, b) => (b['createdAt'] as Timestamp? ?? Timestamp(0, 0))
        .compareTo(a['createdAt'] as Timestamp? ?? Timestamp(0, 0))));
});

/// All payments, admin-wide — drives the Escrow Volume stat. isAdmin()
/// already grants full /payments read (see firestore.rules' payments
/// match block: payerId/artisanId/isAdmin()); no rule change needed.
final _allPaymentsProvider = StreamProvider<List<PaymentModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance.collection('payments').limit(500),
    (d) => PaymentModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'allPayments',
  );
});

/// All disputes (not just open ones) — drives the dashboard's dispute-rate
/// metric and sparkline. isAdmin() already grants full /disputes read.
final _allDisputesProvider = StreamProvider<List<DisputeModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('disputes')
        .orderBy('createdAt', descending: true)
        .limit(200),
    (d) => DisputeModel.fromJson({...d.data(), 'id': d.id}),
    debugLabel: 'allDisputes',
  );
});

/// Admin-account count for the Users Overview donut — the /admins
/// collection holds one membership doc per admin uid (no profile fields).
final _adminCountProvider = StreamProvider<int>((ref) {
  return FirebaseFirestore.instance
      .collection('admins')
      .snapshots()
      .map((s) => s.docs.length);
});

/// All verification submissions (not just pending) — drives the Analytics
/// tab's Verification Success Rate. isAdmin() already grants full
/// /verifications read per firestore.rules.
final _allVerificationsProvider = StreamProvider<List<VerificationModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance.collection('verifications').limit(500),
    (d) => VerificationModel.fromJson(d.data()),
    debugLabel: 'allVerifications',
  );
});

// ---------------------------------------------------------------------------
// AdminShell — persistent sidebar + top-bar shell used by ShellRoute.
//
// With ShellRoute the router keeps this widget alive across all /admin/*
// navigations. Only the section content (widget.child) is swapped out on
// each sidebar click, so:
//   • The isAdmin check and loading spinner run once, not per navigation.
//   • The sidebar never unmounts — no "disappearing drawer" flash.
//   • Sidebar highlight updates automatically via GoRouterState.of(context).
// ---------------------------------------------------------------------------

class AdminShell extends ConsumerStatefulWidget {
  /// The section content supplied by the matched nested GoRoute.
  final Widget child;
  const AdminShell({super.key, required this.child});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Derives the active section from the live route path so the sidebar
  /// highlight stays in sync with the URL without explicit state management.
  AdminSection get _currentSection =>
      AdminSection.fromPath(GoRouterState.of(context).uri.path);

  void _navigateTo(AdminSection section) {
    context.go(section.path);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _openCommandPalette() {
    final palette = AdminPalette.of(ref.read(themeProvider));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdminSearchSheet(palette: palette, onNavigate: _navigateTo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdminAsync = ref.watch(isAdminProvider);

    // Guard: show a loading/error/denied state for the whole shell so
    // individual section pages never need to repeat this check.
    return isAdminAsync.when(
      loading: () => Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: context.colors.primary),
        ),
      ),
      error: (e, _) {
        debugPrint('[AdminShell] isAdminProvider error: $e');
        return Scaffold(
          appBar: AppBar(title: const Text('Admin')),
          body: Center(
            child: Text(
              'Error checking admin access: $e',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        );
      },
      data: (isAdmin) {
        if (!isAdmin) {
          return Scaffold(
            appBar: AppBar(title: const Text('Admin')),
            body: Center(
              child: Text(
                'Access denied. Admin privileges required.',
                style: TextStyle(color: context.colors.error),
              ),
            ),
          );
        }

        final palette = AdminPalette.of(ref.watch(themeProvider));
        // kIsWeb-gated (same reasoning as theme/breakpoints.dart's
        // ResponsiveContext) — without it, a wide Android device (tablet
        // landscape, unfolded foldable) would cross this width threshold
        // and get the sidebar+Row desktop shell instead of the mobile
        // drawer shell below, which is exactly the "mobile widget tree
        // got replaced by width alone" outcome this app's platform gate
        // exists to prevent.
        final isWide = kIsWeb && MediaQuery.of(context).size.width >= 1100;
        final currentSection = _currentSection;

        final sidebar = AdminSidebar(
          selectedSection: currentSection,
          onSelect: _navigateTo,
          onSignOut: () => ref.read(authNotifierProvider.notifier).signOut(),
        );

        final body = Column(
          children: [
            _AdminTopBar(
              palette: palette,
              showMenuButton: !isWide,
              onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
              onNavigate: _navigateTo,
            ),
            Expanded(
              child: Container(
                color: palette.bg0,
                // widget.child is the section content from the matched
                // nested GoRoute — it renders here without rebuilding the
                // surrounding shell on every navigation.
                child: widget.child,
              ),
            ),
          ],
        );

        final scaffold = isWide
            ? Scaffold(
                key: _scaffoldKey,
                backgroundColor: palette.bg0,
                body: Row(
                  children: [
                    sidebar,
                    Expanded(child: SafeArea(child: body)),
                  ],
                ),
              )
            : Scaffold(
                key: _scaffoldKey,
                backgroundColor: palette.bg0,
                drawer: Drawer(
                  backgroundColor: palette.bg1,
                  child: SafeArea(child: sidebar),
                ),
                body: SafeArea(child: body),
              );

        // Global command palette shortcut — Ctrl+K (Windows/Linux/web) and
        // Cmd+K (macOS) both open the same search/navigate sheet used by the
        // top bar's search button.
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                _openCommandPalette,
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                _openCommandPalette,
          },
          child: Focus(autofocus: true, child: scaffold),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// AdminDashboardScreen — thin content-only page for each admin section.
//
// This widget is rendered by the nested GoRoutes inside the ShellRoute and
// becomes the `child` passed to AdminShell. It contains no sidebar, no
// top-bar, and no isAdmin check (AdminShell already handles all of that).
// ---------------------------------------------------------------------------

class AdminDashboardScreen extends ConsumerWidget {
  final AdminSection section;
  const AdminDashboardScreen({super.key, this.section = AdminSection.dashboard});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(_pendingArtisansProvider);
    return switch (section) {
      AdminSection.dashboard =>
          _DashboardHomeTab(onNavigate: (s) => context.go(s.path)),
      AdminSection.users => const _UsersTab(),
      AdminSection.artisans => _ArtisansSection(pendingAsync: pendingAsync),
      AdminSection.jobs => const _JobsTab(),
      AdminSection.verifications => const _VerificationCenterTab(),
      AdminSection.disputes => const _DisputesTab(),
      AdminSection.reviews => const _ReviewsTab(),
      AdminSection.support => const _SupportTicketsTab(),
      AdminSection.deletions => const _DeletionRequestsTab(),
      AdminSection.auditLogs => const _ActivityTab(),
      AdminSection.analytics => const _AnalyticsTab(),
      AdminSection.settings => const _AdminSettingsTab(),
    };
  }
}

// ---------------------------------------------------------------------------
// Top bar — greeting, date range, search, notifications, theme toggle.
// ---------------------------------------------------------------------------

/// "Exit Admin Panel / Return to Main App" — does NOT sign out and does
/// NOT touch admin permissions (no Firestore/Auth write of any kind, just
/// navigation), so admin access is unaffected by using it. Navigates to
/// the existing `/home` route rather than a new admin-specific
/// destination: home_screen.dart's HomeScreen already branches on the
/// user's own `activeRole` (customer vs artisan home tabs), and
/// router.dart's own redirect already sends a dual-role user with no
/// `activeRole` resolved yet to `/role-select` on the way to `/home` — both
/// pieces of "which dashboard for this user" logic already exist and are
/// reused here verbatim, not re-derived. Only ever rendered inside
/// AdminShell (_AdminTopBar), i.e. only on /admin/* routes — per the
/// requirement that this action must only appear inside admin screens.
class _BackToAppButton extends StatelessWidget {
  final AdminPalette palette;

  const _BackToAppButton({required this.palette});

  @override
  Widget build(BuildContext context) {
    final showLabel = kIsWeb && MediaQuery.of(context).size.width >= 720;
    return Material(
      color: palette.bg1,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.go('/home'),
        child: Container(
          height: 38,
          padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, size: 18, color: palette.textSecondary),
              if (showLabel) ...[
                const SizedBox(width: 8),
                Text(
                  'Back to App',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminTopBar extends ConsumerWidget {
  final AdminPalette palette;
  final bool showMenuButton;
  final VoidCallback onMenuTap;
  final void Function(AdminSection) onNavigate;

  const _AdminTopBar({
    required this.palette,
    required this.showMenuButton,
    required this.onMenuTap,
    required this.onNavigate,
  });

  String get _dateRangeLabel {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final sameMonth = monday.month == sunday.month;
    final start = sameMonth
        ? DateFormat('MMM d').format(monday)
        : DateFormat('MMM d').format(monday);
    final end = DateFormat('MMM d, yyyy').format(sunday);
    return '$start - $end';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(currentUserProfileProvider).asData?.value;
    final themeMode = ref.watch(themeProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: palette.bg0,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          if (showMenuButton) ...[
            IconButton(
              icon: Icon(Icons.menu_rounded, color: palette.textPrimary),
              onPressed: onMenuTap,
            ),
            const SizedBox(width: 4),
          ],
          _BackToAppButton(palette: palette),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back, ${admin?.name.split(' ').first ?? 'Admin'} 👋',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Here's what's happening with your platform today.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: palette.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          if (kIsWeb && MediaQuery.of(context).size.width >= 720) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: palette.bg1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 14, color: palette.textTertiary),
                  const SizedBox(width: 8),
                  Text(
                    _dateRangeLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
          ],
          Material(
            color: palette.bg1,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openSearch(context),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_rounded, size: 18, color: palette.textSecondary),
                    if (kIsWeb && MediaQuery.of(context).size.width >= 900) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: palette.bg2,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text('Ctrl K',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: palette.textTertiary,
                                fontFamily: 'Inter')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _AdminNotificationBell(palette: palette, onNavigate: onNavigate),
          const SizedBox(width: 8),
          _topBarIconButton(
            context,
            icon: themeMode == ThemeMode.dark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            onTap: () => ref.read(themeProvider.notifier).toggle(),
          ),
        ],
      ),
    );
  }

  Widget _topBarIconButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: palette.bg1,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border),
          ),
          child: Icon(icon, size: 18, color: palette.textSecondary),
        ),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdminSearchSheet(palette: palette, onNavigate: onNavigate),
    );
  }
}

/// Global command palette (Ctrl+K / search icon) — combines "go to section"
/// navigation with cross-entity search over already-loaded users and jobs.
/// Artisans are covered by the People group (every artisan also has a
/// /users doc — see _jobPeopleNamesProvider's comment for why that's true).
class _AdminSearchSheet extends ConsumerStatefulWidget {
  final AdminPalette palette;
  final void Function(AdminSection) onNavigate;
  const _AdminSearchSheet({required this.palette, required this.onNavigate});

  @override
  ConsumerState<_AdminSearchSheet> createState() => _AdminSearchSheetState();
}

class _AdminSearchSheetState extends ConsumerState<_AdminSearchSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final users = ref.watch(_allUsersProvider).value ?? [];
    final jobs = ref.watch(_allJobsProvider).value ?? [];
    final q = _query.trim().toLowerCase();

    final matchedSections = q.isEmpty
        ? <AdminNavItem>[]
        : adminNavItems.where((s) => s.label.toLowerCase().contains(q)).toList();
    final matchedUsers = q.isEmpty
        ? <UserModel>[]
        : users.where((u) => u.name.toLowerCase().contains(q)).take(8).toList();
    final matchedJobs = q.isEmpty
        ? <JobModel>[]
        : jobs
            .where((j) =>
                j.category.toLowerCase().contains(q) ||
                j.description.toLowerCase().contains(q))
            .take(8)
            .toList();

    final noResults = matchedSections.isEmpty &&
        matchedUsers.isEmpty &&
        matchedJobs.isEmpty;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: palette.bg1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(color: palette.textPrimary, fontFamily: 'Inter'),
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search or jump to a section…',
                hintStyle: TextStyle(color: palette.textTertiary),
                prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
                filled: true,
                fillColor: palette.bg2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: q.isEmpty
                  ? ListView(
                      children: [
                        _sectionLabel(palette, 'Go to'),
                        ...adminNavItems.map((s) => ListTile(
                              leading: Icon(s.icon, color: AdminPalette.indigo),
                              title: Text(s.label,
                                  style: TextStyle(
                                      color: palette.textPrimary,
                                      fontFamily: 'Inter')),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onNavigate(s.section);
                              },
                            )),
                      ],
                    )
                  : ListView(
                      children: [
                        if (matchedSections.isNotEmpty) ...[
                          _sectionLabel(palette, 'Go to'),
                          ...matchedSections.map((s) => ListTile(
                                leading: Icon(s.icon, color: AdminPalette.indigo),
                                title: Text(s.label,
                                    style: TextStyle(
                                        color: palette.textPrimary,
                                        fontFamily: 'Inter')),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onNavigate(s.section);
                                },
                              )),
                        ],
                        if (matchedUsers.isNotEmpty) ...[
                          _sectionLabel(palette, 'People'),
                          ...matchedUsers.map((u) => ListTile(
                                leading: Icon(
                                    u.role == UserRole.artisan
                                        ? Icons.handyman_rounded
                                        : Icons.person_rounded,
                                    color: AdminPalette.indigo),
                                title: Text(u.name,
                                    style: TextStyle(
                                        color: palette.textPrimary,
                                        fontFamily: 'Inter')),
                                subtitle: Text(
                                    u.role == UserRole.artisan
                                        ? 'Artisan'
                                        : 'Customer',
                                    style: TextStyle(
                                        color: palette.textTertiary,
                                        fontFamily: 'Inter')),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onNavigate(u.role == UserRole.artisan
                                      ? AdminSection.artisans
                                      : AdminSection.users);
                                },
                              )),
                        ],
                        if (matchedJobs.isNotEmpty) ...[
                          _sectionLabel(palette, 'Jobs'),
                          ...matchedJobs.map((j) => ListTile(
                                leading: const Icon(Icons.work_rounded,
                                    color: AdminPalette.purple),
                                title: Text(j.category,
                                    style: TextStyle(
                                        color: palette.textPrimary,
                                        fontFamily: 'Inter')),
                                subtitle: Text(j.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: palette.textTertiary,
                                        fontFamily: 'Inter')),
                                onTap: () {
                                  Navigator.of(context).pop();
                                  context.push('/job/${j.id}');
                                },
                              )),
                        ],
                        if (noResults)
                          Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Center(
                              child: Text(
                                'No results for "$_query"',
                                style: TextStyle(
                                    color: palette.textTertiary,
                                    fontFamily: 'Inter'),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(AdminPalette palette, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: palette.textTertiary,
            fontFamily: 'Inter',
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Admin notification center — derived from existing pending-action queues
// (no new Firestore collection or write path). Distinct from the
// customer/artisan NotificationBell: those are addressed to a specific
// userId for job events; admins need "what needs my attention right now"
// across the whole platform instead, which is exactly what the
// pending-artisans / pending-verifications / open-tickets / open-disputes
// streams already represent — this just merges them into one feed.
// ---------------------------------------------------------------------------

class _AdminNotificationEntry {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final AdminSection target;
  const _AdminNotificationEntry({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.target,
  });
}

class _AdminNotificationBell extends ConsumerWidget {
  final AdminPalette palette;
  final void Function(AdminSection) onNavigate;
  const _AdminNotificationBell({required this.palette, required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingArtisans = ref.watch(_pendingArtisansProvider).value ?? [];
    final pendingVerifications = ref.watch(pendingVerificationsProvider).value ?? [];
    final openTickets =
        (ref.watch(allTicketsProvider).value ?? []).where((t) => t.status == 'open').toList();
    final openDisputes = ref.watch(openDisputesProvider).value ?? [];

    final entries = <_AdminNotificationEntry>[
      ...pendingArtisans.map((a) => _AdminNotificationEntry(
            icon: Icons.handyman_rounded,
            color: AdminPalette.purple,
            title: 'New artisan application',
            subtitle: a.name,
            timestamp: a.createdAt,
            target: AdminSection.artisans,
          )),
      ...pendingVerifications.map((v) => _AdminNotificationEntry(
            icon: Icons.verified_user_rounded,
            color: AdminPalette.blue,
            title: 'New verification request',
            subtitle: v.uid,
            timestamp: v.submittedAt ?? DateTime.now(),
            target: AdminSection.verifications,
          )),
      ...openTickets.map((t) => _AdminNotificationEntry(
            icon: Icons.support_agent_rounded,
            color: AdminPalette.amber,
            title: 'New support ticket',
            subtitle: t.subject,
            timestamp: t.createdAt,
            target: AdminSection.support,
          )),
      ...openDisputes.map((d) => _AdminNotificationEntry(
            icon: Icons.gavel_rounded,
            color: AdminPalette.red,
            title: 'Job dispute raised',
            subtitle: d.reason,
            timestamp: d.createdAt,
            target: AdminSection.disputes,
          )),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final count = entries.length;

    return Material(
      color: palette.bg1,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(context, entries),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border),
              ),
              child: Icon(
                count > 0 ? Icons.notifications_rounded : Icons.notifications_outlined,
                size: 18,
                color: count > 0 ? AdminPalette.indigo : palette.textSecondary,
              ),
            ),
            if (count > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AdminPalette.red,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.bg0, width: 1.5),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontFamily: 'Inter'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, List<_AdminNotificationEntry> entries) {
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 64, right: 20),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 360,
              constraints: const BoxConstraints(maxHeight: 480),
              decoration: BoxDecoration(
                color: palette.bg1,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.border),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Notifications',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                            fontFamily: 'Inter')),
                  ),
                  Flexible(
                    child: entries.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Center(
                              child: Text('All caught up',
                                  style: TextStyle(
                                      color: palette.textTertiary, fontFamily: 'Inter')),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: entries.length,
                            itemBuilder: (context, i) {
                              final e = entries[i];
                              return ListTile(
                                dense: true,
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: e.color.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(e.icon, size: 16, color: e.color),
                                ),
                                title: Text(e.title,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: palette.textPrimary,
                                        fontFamily: 'Inter')),
                                subtitle: Text(e.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: palette.textTertiary,
                                        fontFamily: 'Inter')),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  onNavigate(e.target);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Artisans section — combines the former "Pending Approval" and
// "All Artisans" tabs into one sidebar destination with an internal
// segmented switch, preserving both workflows without two separate
// top-level nav entries.
// ---------------------------------------------------------------------------

class _ArtisansSection extends StatefulWidget {
  final AsyncValue<List<ArtisanModel>> pendingAsync;
  const _ArtisansSection({required this.pendingAsync});

  @override
  State<_ArtisansSection> createState() => _ArtisansSectionState();
}

class _ArtisansSectionState extends State<_ArtisansSection> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final pendingCount = widget.pendingAsync.value?.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              _segmentButton(context, 0, 'Pending Approval', pendingCount),
              const SizedBox(width: 8),
              _segmentButton(context, 1, 'All Artisans', null),
            ],
          ),
        ),
        Expanded(
          child: _segment == 0
              ? _PendingArtisansTab(pendingAsync: widget.pendingAsync)
              : const _AllArtisansTab(),
        ),
      ],
    );
  }

  Widget _segmentButton(
    BuildContext context,
    int index,
    String label,
    int? badge,
  ) {
    final selected = _segment == index;
    return Material(
      color: selected
          ? context.colors.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _segment = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? context.colors.primary
                  : context.colors.borderLight,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? context.colors.primary
                      : context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
              if (badge != null && badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: context.colors.warning,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard home — the new sidebar-shell landing page. Every number here
// is computed from the same Firestore-backed providers the old tabs used
// (_allUsersProvider, _allArtisansProvider, _allJobsProvider, etc.) — no
// hardcoded or simulated values.
// ---------------------------------------------------------------------------

const _categoryIcons = <String, IconData>{
  'plumbing': Icons.plumbing_rounded,
  'electrical': Icons.electrical_services_rounded,
  'carpentry': Icons.carpenter_rounded,
  'cleaning': Icons.cleaning_services_rounded,
  'air conditioning': Icons.ac_unit_rounded,
  'painting': Icons.format_paint_rounded,
  'appliance repair': Icons.build_circle_rounded,
  'masonry': Icons.foundation_rounded,
  'gardening': Icons.yard_rounded,
  'moving': Icons.local_shipping_rounded,
};

// Not const: .blue/.amber derive from AppColors (02-design-system-v2.md
// §7's AdminPalette drift-prevention refactor), which makes them
// non-constant getters — this list is still only computed once, just not
// at compile time.
final _categoryColors = <Color>[
  AdminPalette.indigo,
  AdminPalette.blue,
  AdminPalette.cyan,
  AdminPalette.amber,
  AdminPalette.pink,
];

class _ActivityEntry {
  final IconData icon;
  final Color color;
  final String title;
  final DateTime timestamp;
  const _ActivityEntry(this.icon, this.color, this.title, this.timestamp);
}

double? _weekOverWeekTrend(List<DateTime> dates) {
  final now = DateTime.now();
  final weekAgo = now.subtract(const Duration(days: 7));
  final twoWeeksAgo = now.subtract(const Duration(days: 14));
  final thisWeek = dates.where((d) => d.isAfter(weekAgo)).length;
  final lastWeek =
      dates.where((d) => d.isAfter(twoWeeksAgo) && !d.isAfter(weekAgo)).length;
  if (lastWeek == 0) return thisWeek == 0 ? null : 100.0;
  return ((thisWeek - lastWeek) / lastWeek) * 100;
}

class _DashboardHomeTab extends ConsumerStatefulWidget {
  final void Function(AdminSection) onNavigate;
  const _DashboardHomeTab({required this.onNavigate});

  @override
  ConsumerState<_DashboardHomeTab> createState() => _DashboardHomeTabState();
}

class _DashboardHomeTabState extends ConsumerState<_DashboardHomeTab> {
  ChartPeriod _period = ChartPeriod.week;

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(ref.watch(themeProvider));
    final users = ref.watch(_allUsersProvider).valueOrNull ?? [];
    final artisans = ref.watch(_allArtisansProvider).valueOrNull ?? [];
    final jobs = ref.watch(_allJobsProvider).valueOrNull ?? [];
    final verifications = ref.watch(pendingVerificationsProvider).valueOrNull ?? [];
    final pendingArtisans = ref.watch(_pendingArtisansProvider).valueOrNull ?? [];
    final tickets = ref.watch(allTicketsProvider).valueOrNull ?? [];
    final reviews = ref.watch(allReviewsProvider).valueOrNull ?? [];
    final disputes = ref.watch(_allDisputesProvider).valueOrNull ?? [];
    final adminCount = ref.watch(_adminCountProvider).valueOrNull ?? 0;
    final auditLogsAsync = ref.watch(_recentAuditLogsProvider);
    final payments = ref.watch(_allPaymentsProvider).valueOrNull ?? [];
    final alertsAsync = ref.watch(_adminAlertsProvider);

    final activeJobs = jobs.where((j) => j.status.isActive).toList();
    final completedJobs =
        jobs.where((j) => j.status == JobStatus.completed).toList();
    final escrowVolume = payments
        .where((p) => p.status == PaymentStatus.escrowHeld)
        .fold<double>(0, (total, p) => total + p.amount);
    final ratedArtisans = artisans.where((a) => a.totalRatings > 0).toList();
    final avgRating = ratedArtisans.isEmpty
        ? 0.0
        : ratedArtisans.map((a) => a.rating).reduce((a, b) => a + b) /
            ratedArtisans.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Needs Attention: alerts + pending actions, first thing on
          // the page — an admin's first question is "what needs me right
          // now", not "how big is the platform" (that's the KPI grid
          // below). Same two cards as before, just resequenced to the top
          // instead of buried in a lower row; neither card's own content
          // or data source changed.
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = kIsWeb && constraints.maxWidth >= 900;
              final alerts = _buildAdminAlertsCard(palette, alertsAsync);
              final pendingActions = _buildPendingActionsCard(
                  palette,
                  pendingArtisans.length,
                  verifications.length,
                  tickets.where((t) => t.status == 'open').length,
                  disputes.where((d) => d.status == DisputeStatus.open).length);

              if (!wide) {
                return Column(
                  children: [
                    pendingActions,
                    const SizedBox(height: 14),
                    alerts,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: pendingActions),
                    const SizedBox(width: 14),
                    Expanded(child: alerts),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 18),

          // ── Stat cards ──────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              // kIsWeb-gated, same reasoning as the outer shell's isWide
              // check above — a wide Android device must still get the
              // narrowest (1-column) card layout, not scale up with
              // viewport width the way the web experience does.
              final cols = !kIsWeb
                  ? 1
                  : constraints.maxWidth >= 1300
                      ? 6
                      : constraints.maxWidth >= 900
                          ? 3
                          : constraints.maxWidth >= 560
                              ? 2
                              : 1;
              final cards = [
                AdminStatCard(
                  palette: palette,
                  label: 'Total Users',
                  value: users.length,
                  icon: Icons.people_alt_rounded,
                  color: AdminPalette.purple,
                  trendPercent:
                      _weekOverWeekTrend(users.map((u) => u.createdAt).toList()),
                  onTap: () => widget.onNavigate(AdminSection.users),
                ),
                AdminStatCard(
                  palette: palette,
                  label: 'Total Artisans',
                  value: artisans.length,
                  icon: Icons.handyman_rounded,
                  color: AdminPalette.blue,
                  trendPercent: _weekOverWeekTrend(
                      artisans.map((a) => a.createdAt).toList()),
                  onTap: () => widget.onNavigate(AdminSection.artisans),
                ),
                AdminStatCard(
                  palette: palette,
                  label: 'Active Jobs',
                  value: activeJobs.length,
                  icon: Icons.work_rounded,
                  color: AdminPalette.cyan,
                  trendPercent: _weekOverWeekTrend(
                      activeJobs.map((j) => j.createdAt).toList()),
                  onTap: () => widget.onNavigate(AdminSection.jobs),
                ),
                AdminStatCard(
                  palette: palette,
                  label: 'Escrow Volume',
                  value: 0,
                  valueLabel: NumberFormat.currency(
                          locale: 'en_NG', symbol: '₦', decimalDigits: 0)
                      .format(escrowVolume),
                  icon: Icons.lock_outline_rounded,
                  color: AdminPalette.green,
                  onTap: () => widget.onNavigate(AdminSection.jobs),
                ),
                AdminStatCard(
                  palette: palette,
                  label: 'Completed Jobs',
                  value: completedJobs.length,
                  icon: Icons.task_alt_rounded,
                  color: AdminPalette.amber,
                  trendPercent: _weekOverWeekTrend(completedJobs
                      .map((j) => j.completedAt ?? j.createdAt)
                      .toList()),
                  onTap: () => widget.onNavigate(AdminSection.jobs),
                ),
                AdminStatCard(
                  palette: palette,
                  label: 'Pending Verifications',
                  value: verifications.length,
                  icon: Icons.verified_user_rounded,
                  color: AdminPalette.pink,
                  trendPercent: _weekOverWeekTrend(verifications
                      .map((v) => v.submittedAt ?? DateTime.now())
                      .toList()),
                  onTap: () => widget.onNavigate(AdminSection.verifications),
                ),
                AdminStatCard(
                  palette: palette,
                  label: 'Average Rating',
                  value: avgRating.round(),
                  icon: Icons.star_rounded,
                  color: AdminPalette.indigo,
                  onTap: () => widget.onNavigate(AdminSection.reviews),
                ),
              ];
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.55,
                children: cards,
              );
            },
          ),
          const SizedBox(height: 18),

          // ── Charts row ──────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = kIsWeb && constraints.maxWidth >= 1100;
              final jobsChart = _buildJobsOverviewCard(palette, jobs);
              final usersDonut = _buildUsersDonutCard(
                  palette, users, artisans.length, adminCount);
              final topCategories = _buildTopCategoriesCard(palette, jobs);

              if (!wide) {
                return Column(
                  children: [
                    jobsChart,
                    const SizedBox(height: 14),
                    usersDonut,
                    const SizedBox(height: 14),
                    topCategories,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: jobsChart),
                    const SizedBox(width: 14),
                    Expanded(flex: 3, child: usersDonut),
                    const SizedBox(width: 14),
                    Expanded(flex: 3, child: topCategories),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),

          // ── Activity / Health row — Pending Actions and Operational
          // Alerts both moved to the top of the page (see above); this
          // row keeps the two cards that are informational rather than
          // actionable.
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = kIsWeb && constraints.maxWidth >= 900;
              final activity = _buildRecentActivityCard(
                  palette, users, jobs, reviews, tickets, auditLogsAsync);
              final health = _buildPlatformHealthCard(
                  palette, jobs, artisans, disputes, auditLogsAsync.valueOrNull ?? []);

              if (!wide) {
                return Column(
                  children: [
                    activity,
                    const SizedBox(height: 14),
                    health,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: activity),
                    const SizedBox(width: 14),
                    Expanded(child: health),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---- Jobs Overview line chart ------------------------------------------

  Widget _buildJobsOverviewCard(AdminPalette palette, List<JobModel> jobs) {
    final (labels, created, inProgress, completed) =
        _bucketJobs(jobs, _period);

    return AdminSectionCard(
      palette: palette,
      title: 'Jobs Overview',
      trailing: PopupMenuButton<ChartPeriod>(
        initialValue: _period,
        onSelected: (p) => setState(() => _period = p),
        color: palette.bg2,
        itemBuilder: (_) => ChartPeriod.values
            .map((p) => PopupMenuItem(value: p, child: Text(p.label,
                style: TextStyle(color: palette.textPrimary, fontFamily: 'Inter'))))
            .toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: palette.bg2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_period.label,
                  style: TextStyle(
                      fontSize: 12, color: palette.textSecondary, fontFamily: 'Inter')),
              Icon(Icons.expand_more_rounded, size: 16, color: palette.textTertiary),
            ],
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            children: [
              ChartLegendDot(color: AdminPalette.purple, label: 'Created', palette: palette),
              ChartLegendDot(color: AdminPalette.blue, label: 'In Progress', palette: palette),
              ChartLegendDot(color: AdminPalette.green, label: 'Completed', palette: palette),
            ],
          ),
          const SizedBox(height: 12),
          JobsOverviewChart(
            palette: palette,
            xLabels: labels,
            created: created,
            inProgress: inProgress,
            completed: completed,
          ),
        ],
      ),
    );
  }

  (List<String>, List<double>, List<double>, List<double>) _bucketJobs(
      List<JobModel> jobs, ChartPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case ChartPeriod.week:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        final labels = List.generate(
            7, (i) => DateFormat('E').format(start.add(Duration(days: i))));
        return _bucket(jobs, 7, (d) => d.difference(start).inDays, labels);
      case ChartPeriod.month:
        final start = DateTime(now.year, now.month, 1);
        final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
        final weeks = (daysInMonth / 7).ceil();
        final labels = List.generate(weeks, (i) => 'Wk ${i + 1}');
        return _bucket(
            jobs, weeks, (d) => d.difference(start).inDays ~/ 7, labels);
      case ChartPeriod.year:
        final start = DateTime(now.year, 1, 1);
        final labels = List.generate(
            12, (i) => DateFormat('MMM').format(DateTime(now.year, i + 1)));
        return _bucket(
            jobs, 12, (d) => (d.year - start.year) * 12 + d.month - 1, labels);
    }
  }

  (List<String>, List<double>, List<double>, List<double>) _bucket(
    List<JobModel> jobs,
    int bucketCount,
    int Function(DateTime) bucketOf,
    List<String> labels,
  ) {
    final created = List<double>.filled(bucketCount, 0);
    final inProgress = List<double>.filled(bucketCount, 0);
    final completed = List<double>.filled(bucketCount, 0);

    void addTo(List<double> bucket, DateTime date) {
      final i = bucketOf(date);
      if (i >= 0 && i < bucketCount) bucket[i]++;
    }

    for (final job in jobs) {
      addTo(created, job.createdAt);
      if (job.startedAt != null) addTo(inProgress, job.startedAt!);
      if (job.completedAt != null) addTo(completed, job.completedAt!);
    }
    return (labels, created, inProgress, completed);
  }

  // ---- Users donut --------------------------------------------------------

  Widget _buildUsersDonutCard(AdminPalette palette, List<UserModel> users,
      int artisanCount, int adminCount) {
    final customers = users.where((u) => u.role == UserRole.customer).length;

    return AdminSectionCard(
      palette: palette,
      title: 'Users Overview',
      child: Column(
        children: [
          UsersDonutChart(
            palette: palette,
            customers: customers,
            artisans: artisanCount,
            admins: adminCount,
          ),
          const SizedBox(height: 8),
          _donutLegendRow(palette, AdminPalette.purple, 'Customers', customers),
          _donutLegendRow(palette, AdminPalette.blue, 'Artisans', artisanCount),
          _donutLegendRow(palette, AdminPalette.amber, 'Admins', adminCount),
        ],
      ),
    );
  }

  Widget _donutLegendRow(
      AdminPalette palette, Color color, String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: palette.textSecondary, fontFamily: 'Inter')),
          ),
          Text('$value',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                  fontFamily: 'Inter')),
        ],
      ),
    );
  }

  // ---- Top categories -----------------------------------------------------

  Widget _buildTopCategoriesCard(AdminPalette palette, List<JobModel> jobs) {
    final counts = <String, int>{};
    for (final j in jobs) {
      counts[j.category] = (counts[j.category] ?? 0) + 1;
    }
    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topFive = top.take(5).toList();
    final maxValue = topFive.isEmpty ? 1 : topFive.first.value;

    return AdminSectionCard(
      palette: palette,
      title: 'Top Categories',
      child: topFive.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('No job data yet',
                  style: TextStyle(color: palette.textTertiary, fontFamily: 'Inter')),
            )
          : Column(
              children: [
                for (var i = 0; i < topFive.length; i++)
                  AdminCategoryBar(
                    palette: palette,
                    icon: _categoryIcons[topFive[i].key.toLowerCase()] ??
                        Icons.category_rounded,
                    color: _categoryColors[i % _categoryColors.length],
                    label: topFive[i].key,
                    value: topFive[i].value,
                    maxValue: maxValue,
                  ),
              ],
            ),
    );
  }

  // ---- Recent activity (merged real feed) ----------------------------------

  Widget _buildRecentActivityCard(
    AdminPalette palette,
    List<UserModel> users,
    List<JobModel> jobs,
    List<ReviewModel> reviews,
    List<SupportTicketModel> tickets,
    AsyncValue<List<AdminAuditLogModel>> auditLogsAsync,
  ) {
    final entries = <_ActivityEntry>[
      ...users.take(15).map((u) => _ActivityEntry(
            u.role == UserRole.artisan
                ? Icons.handyman_rounded
                : Icons.person_add_alt_1_rounded,
            AdminPalette.purple,
            '${u.role == UserRole.artisan ? 'New artisan' : 'New user'} registered: ${u.name}',
            u.createdAt,
          )),
      ...jobs.take(15).map((j) => _ActivityEntry(
            Icons.work_rounded,
            AdminPalette.cyan,
            'New job created: ${j.category}',
            j.createdAt,
          )),
      ...reviews.take(15).map((r) => _ActivityEntry(
            Icons.star_rounded,
            AdminPalette.amber,
            'Review submitted (${r.rating}★)',
            r.createdAt,
          )),
      ...tickets.take(15).map((t) => _ActivityEntry(
            Icons.support_agent_rounded,
            AdminPalette.blue,
            'Support ticket created',
            t.createdAt,
          )),
      ...(auditLogsAsync.valueOrNull ?? []).take(15).map((log) => _ActivityEntry(
            _ActivityTab._auditIcon(log.action),
            _ActivityTab._auditColor(log.action, palette),
            log.actionLabel,
            log.timestamp,
          )),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final recent = entries.take(8).toList();

    return AdminSectionCard(
      palette: palette,
      title: 'Recent Activity',
      trailing: TextButton(
        onPressed: () => widget.onNavigate(AdminSection.auditLogs),
        child: const Text('View All'),
      ),
      child: recent.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('No activity yet',
                  style: TextStyle(color: palette.textTertiary, fontFamily: 'Inter')),
            )
          : Column(
              children: recent
                  .map((e) => AdminActivityRow(
                        palette: palette,
                        icon: e.icon,
                        color: e.color,
                        title: e.title,
                        timeLabel: timeago.format(e.timestamp, locale: 'en_short'),
                      ))
                  .toList(),
            ),
    );
  }

  // ---- Pending actions ------------------------------------------------------

  Widget _buildPendingActionsCard(
    AdminPalette palette,
    int pendingArtisans,
    int pendingVerifications,
    int openTickets,
    int openDisputes,
  ) {
    return AdminSectionCard(
      palette: palette,
      title: 'Pending Actions',
      trailing: TextButton(
        onPressed: () => widget.onNavigate(AdminSection.artisans),
        child: const Text('View All'),
      ),
      child: Column(
        children: [
          AdminPendingActionRow(
            palette: palette,
            icon: Icons.handyman_rounded,
            color: AdminPalette.purple,
            title: 'Artisan Approvals',
            subtitle: 'Review and approve new artisans',
            count: pendingArtisans,
            onTap: () => widget.onNavigate(AdminSection.artisans),
          ),
          AdminPendingActionRow(
            palette: palette,
            icon: Icons.verified_user_rounded,
            color: AdminPalette.blue,
            title: 'Verifications',
            subtitle: 'Pending verification requests',
            count: pendingVerifications,
            onTap: () => widget.onNavigate(AdminSection.verifications),
          ),
          AdminPendingActionRow(
            palette: palette,
            icon: Icons.support_agent_rounded,
            color: AdminPalette.amber,
            title: 'Support Tickets',
            subtitle: 'Waiting for admin response',
            count: openTickets,
            onTap: () => widget.onNavigate(AdminSection.support),
          ),
          AdminPendingActionRow(
            palette: palette,
            icon: Icons.gavel_rounded,
            color: AdminPalette.red,
            title: 'Open Disputes',
            subtitle: 'Awaiting admin resolution',
            count: openDisputes,
            onTap: () => widget.onNavigate(AdminSection.disputes),
          ),
        ],
      ),
    );
  }

  // ---- Operational alerts ------------------------------------------------------
  //
  // admin_alerts is written by Cloud Functions (reconcileStuckEscrowReleases,
  // _alertAdminDispute in functions/index.js) but, until the firestore.rules
  // addition alongside this change, had no match block at all — completely
  // unreadable from the app under Firestore's default-deny model. See
  // design/STITCH_ADMIN_AUDIT.md. This card is the first (and currently
  // only) surface that reads it. No new business rule: "resolved" is the
  // exact field both Cloud Functions writers already set to false — this
  // only exposes flipping it to true, not inventing new alert semantics.
  Widget _buildAdminAlertsCard(
    AdminPalette palette,
    AsyncValue<List<Map<String, dynamic>>> alertsAsync,
  ) {
    return AdminSectionCard(
      palette: palette,
      title: 'Operational Alerts',
      trailing: alertsAsync.valueOrNull != null
          ? Text(
              '${alertsAsync.valueOrNull!.length} open',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary,
                fontFamily: 'Inter',
              ),
            )
          : null,
      child: alertsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) {
          debugPrint('[AdminDashboard] admin_alerts stream error: $e\n$st');
          return Text(
            "Couldn't load alerts.",
            style: TextStyle(color: palette.textSecondary, fontFamily: 'Inter'),
          );
        },
        data: (alerts) {
          if (alerts.isEmpty) {
            return Row(
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 18, color: AdminPalette.green),
                const SizedBox(width: 8),
                Text(
                  'No active alerts',
                  style: TextStyle(color: palette.textSecondary, fontFamily: 'Inter'),
                ),
              ],
            );
          }
          return Column(
            children: alerts
                .take(5)
                .map((a) => _AdminAlertRow(palette: palette, alert: a))
                .toList(),
          );
        },
      ),
    );
  }

  // ---- Platform health --------------------------------------------------------

  Widget _buildPlatformHealthCard(
    AdminPalette palette,
    List<JobModel> jobs,
    List<ArtisanModel> artisans,
    List<DisputeModel> disputes,
    List<AdminAuditLogModel> auditLogs,
  ) {
    final completedJobs =
        jobs.where((j) => j.status == JobStatus.completed).toList();
    final completionRate =
        jobs.isEmpty ? 0.0 : completedJobs.length / jobs.length * 100;

    final verifiedArtisans = artisans
        .where((a) =>
            a.verificationStatus == 'id_verified' ||
            a.verificationStatus == 'trusted')
        .length;
    final verificationRate =
        artisans.isEmpty ? 0.0 : verifiedArtisans / artisans.length * 100;

    final responseTimes = artisans.map((a) => a.responseTimeMinutes).toList();
    final avgResponseMinutes = responseTimes.isEmpty
        ? 0.0
        : responseTimes.reduce((a, b) => a + b) / responseTimes.length;
    final responseLabel = avgResponseMinutes >= 60
        ? '${(avgResponseMinutes / 60).toStringAsFixed(1)}h'
        : '${avgResponseMinutes.toStringAsFixed(0)}m';

    final disputeRate =
        jobs.isEmpty ? 0.0 : disputes.length / jobs.length * 100;

    final now = DateTime.now();
    List<double> dailyCount(Iterable<DateTime> dates) {
      final buckets = List<double>.filled(7, 0);
      for (final d in dates) {
        final diff = now.difference(d).inDays;
        if (diff >= 0 && diff < 7) buckets[6 - diff]++;
      }
      return buckets;
    }

    final completionSpark = dailyCount(
        completedJobs.where((j) => j.completedAt != null).map((j) => j.completedAt!));
    final verificationSpark = dailyCount(auditLogs
        .where((l) => l.action == AdminAction.verificationApproved)
        .map((l) => l.timestamp));
    final disputeSpark = dailyCount(disputes.map((d) => d.createdAt));
    final responseSpark = List<double>.filled(7, avgResponseMinutes);

    return AdminSectionCard(
      palette: palette,
      title: 'Platform Health',
      trailing: TextButton(
        onPressed: () => widget.onNavigate(AdminSection.analytics),
        child: const Text('View Details'),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _healthMetric(
                  palette,
                  'Completion Rate',
                  '${completionRate.toStringAsFixed(0)}%',
                  completionSpark,
                  AdminPalette.purple,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _healthMetric(
                  palette,
                  'Verification Rate',
                  '${verificationRate.toStringAsFixed(0)}%',
                  verificationSpark,
                  AdminPalette.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _healthMetric(
                  palette,
                  'Response Time',
                  responseLabel,
                  responseSpark,
                  AdminPalette.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _healthMetric(
                  palette,
                  'Dispute Rate',
                  '${disputeRate.toStringAsFixed(1)}%',
                  disputeSpark,
                  AdminPalette.amber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _healthMetric(AdminPalette palette, String label, String value,
      List<double> spark, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, color: palette.textTertiary, fontFamily: 'Inter')),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: palette.textPrimary,
                  fontFamily: 'Inter')),
          const Spacer(),
          AdminSparkline(values: spark, color: color),
        ],
      ),
    );
  }
}

/// Top-N recent admin audit log entries — same backing collection as the
/// Audit Logs tab, sliced for the dashboard's Recent Activity feed.
final _recentAuditLogsProvider = StreamProvider<List<AdminAuditLogModel>>((ref) {
  return AdminAuditService(FirebaseFirestore.instance).watchAll();
});

/// One row in the Operational Alerts card — the type-specific description
/// plus a "Mark Resolved" action that flips the same `resolved` field
/// reconcileStuckEscrowReleases/_alertAdminDispute already write as false.
class _AdminAlertRow extends ConsumerStatefulWidget {
  final AdminPalette palette;
  final Map<String, dynamic> alert;

  const _AdminAlertRow({required this.palette, required this.alert});

  @override
  ConsumerState<_AdminAlertRow> createState() => _AdminAlertRowState();
}

class _AdminAlertRowState extends ConsumerState<_AdminAlertRow> {
  bool _resolving = false;

  (IconData, Color, String) get _meta {
    final a = widget.alert;
    switch (a['type']) {
      case 'stuck_escrow_release':
        return (
          Icons.error_outline_rounded,
          AdminPalette.red,
          'Escrow release stuck (job ${a['jobId'] ?? '—'}, status: ${a['status'] ?? 'unknown'})',
        );
      case 'dispute_from_job':
        return (
          Icons.gavel_rounded,
          AdminPalette.amber,
          'Dispute on job ${a['jobId'] ?? '—'}: ${a['reason'] ?? 'no reason given'}',
        );
      case 'paid_cancellation_request':
        return (
          Icons.cancel_schedule_send_rounded,
          AdminPalette.amber,
          'Cancellation requested on paid job ${a['jobId'] ?? '—'} (${a['jobStatus'] ?? '—'}): ${a['reason'] ?? 'no reason given'}',
        );
      case 'payout_authorization_failed':
        return (
          Icons.gpp_bad_rounded,
          AdminPalette.red,
          'Payout blocked on job ${a['jobId'] ?? '—'}: ${a['reason'] ?? 'authorization failed'}',
        );
      // Stage 4 alert types.
      case 'payout_frozen':
      case 'autorelease_blocked':
        return (
          Icons.ac_unit_rounded,
          AdminPalette.red,
          'Payout frozen on job ${a['jobId'] ?? '—'}: ${a['reason'] ?? 'freeze active'}',
        );
      case 'transfer_failed':
        return (
          Icons.error_outline_rounded,
          AdminPalette.red,
          'Payout transfer failed on job ${a['jobId'] ?? '—'}: ${a['reason'] ?? ''}',
        );
      case 'charge_requires_refund':
        return (
          Icons.undo_rounded,
          AdminPalette.amber,
          'Charge ${a['reference'] ?? '—'} must be refunded: ${a['reason'] ?? ''}',
        );
      case 'refund_failed':
      case 'refund_needs_attention':
      case 'refund_submit_unknown':
        return (
          Icons.report_problem_rounded,
          AdminPalette.red,
          'Refund ${a['refundId'] ?? '—'}: ${a['type'] == 'refund_failed' ? 'failed at Paystack' : a['type'] == 'refund_needs_attention' ? 'needs customer bank details (resolve in the Paystack dashboard)' : 'submission outcome unknown — reconciling'}',
        );
      case 'non_domestic_card_payment':
        return (
          Icons.public_rounded,
          AdminPalette.amber,
          'Non-Nigerian card (${a['cardCountry'] ?? '—'}) used on job ${a['jobId'] ?? '—'} — check Paystack international setting',
        );
      default:
        return (Icons.info_outline_rounded, AdminPalette.blue, '${a['type'] ?? 'Alert'}');
    }
  }

  Future<void> _resolve() async {
    final adminId = ref.read(currentUserProvider).asData?.value?.uid;
    if (adminId == null) return;
    setState(() => _resolving = true);
    try {
      await FirebaseFirestore.instance
          .collection('admin_alerts')
          .doc(widget.alert['id'] as String)
          .update({
        'resolved': true,
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': adminId,
      });
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not resolve alert: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  /// Stage 4: money-related alerts get a real action that calls the audited
  /// admin finance functions. The action resolves the alert only after the
  /// server accepted it; "Resolve" alone still just dismisses an alert.
  bool get _actionable => const {
        'paid_cancellation_request', 'charge_requires_refund', 'refund_failed',
        'payout_frozen', 'autorelease_blocked', 'transfer_failed',
      }.contains(widget.alert['type']);

  Future<void> _act() async {
    final a = widget.alert;
    final finance = ref.read(adminFinanceServiceProvider);
    final jobId = a['jobId'] as String?;
    Future<void> Function()? run;
    switch (a['type']) {
      case 'paid_cancellation_request':
        if (jobId == null) return;
        final d = await showSettlementDialog(context,
            title: 'Paid Cancellation Request', jobId: jobId, allowDecline: true, allowRelease: false,
            initialOutcome: 'decline');
        if (d == null) return;
        run = () => finance.resolveCancellation(
              jobId: jobId,
              decision: d.outcome,
              reason: d.reason,
              artisanAmount: d.artisanAmount,
              refundAmount: d.refundAmount,
            );
      case 'charge_requires_refund':
        final refReference = a['reference'] as String?;
        if (refReference == null) return;
        final reason = await showAdminReasonDialog(context,
            title: 'Refund Charge',
            message: 'Refund the full captured amount of charge $refReference to the customer.',
            confirmLabel: 'Refund');
        if (reason == null) return;
        run = () => finance.refundCharge(reference: refReference, reason: reason);
      case 'refund_failed':
        final refundId = a['refundId'] as String?;
        if (refundId == null) return;
        final reason = await showAdminReasonDialog(context,
            title: 'Retry Refund', message: 'Submit this refund to Paystack again.', confirmLabel: 'Retry');
        if (reason == null) return;
        run = () => finance.retryRefund(refundId: refundId, reason: reason);
      case 'payout_frozen':
      case 'autorelease_blocked':
      case 'transfer_failed':
        if (jobId == null) return;
        final reason = await showAdminReasonDialog(context,
            title: 'Retry Payout',
            message: 'Retry the payout for this job. If a freeze or suspension is still active, it will stay frozen.',
            confirmLabel: 'Retry payout');
        if (reason == null) return;
        run = a['type'] == 'autorelease_blocked'
            // Auto-release re-runs hourly once the freeze is lifted.
            ? null
            : () => finance.retryPayout(jobId: jobId, reason: reason);
    }
    if (run == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Lift the freeze or suspension first — auto-release will then run within the hour.')));
      }
      return;
    }
    setState(() => _resolving = true);
    try {
      await run();
      await _resolve();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Action failed: ${adminFinanceErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, description) = _meta;
    final palette = widget.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: palette.textPrimary, fontFamily: 'Inter'),
            ),
          ),
          const SizedBox(width: 8),
          if (_resolving)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            if (_actionable)
              TextButton(
                onPressed: _act,
                child: const Text('Take action'),
              ),
            TextButton(
              onPressed: _resolve,
              child: const Text('Resolve'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared friendly states — used by every tab so admins never see a raw
// Firestore exception string, and every empty list gets a consistent,
// non-blank treatment.
// ---------------------------------------------------------------------------

class _AdminErrorState extends StatelessWidget {
  const _AdminErrorState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: context.colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            "Couldn't load this data. Check your connection and try again.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    ),
  );
}

class _AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _AdminEmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: context.colors.accent),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
              fontFamily: 'Inter',
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Pending tab
// ---------------------------------------------------------------------------

class _PendingArtisansTab extends StatelessWidget {
  final AsyncValue<List<ArtisanModel>> pendingAsync;

  const _PendingArtisansTab({required this.pendingAsync});

  @override
  Widget build(BuildContext context) {
    return pendingAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      ),
      error: (e, st) {
        // Admin sees a friendly message; the real Firestore error (e.g. a
        // missing composite index) is logged for debugging instead of
        // being silently swallowed.
        debugPrint('[AdminDashboard] stream error: $e\n$st');
        return const _AdminErrorState();
      },
      data: (artisans) {
        if (artisans.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 56,
                  color: context.colors.accent,
                ),
                SizedBox(height: 12),
                Text(
                  'No pending applications',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'All artisan applications have been reviewed.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: artisans.length,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) =>
              _ArtisanApplicationCard(artisan: artisans[i]),
        );
      },
    );
  }
}

class _ArtisanApplicationCard extends StatefulWidget {
  final ArtisanModel artisan;

  const _ArtisanApplicationCard({required this.artisan});

  @override
  State<_ArtisanApplicationCard> createState() =>
      _ArtisanApplicationCardState();
}

class _ArtisanApplicationCardState extends State<_ArtisanApplicationCard> {
  bool _loading = false;
  String? _error;

  Future<void> _updateStatus(String status) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final artisanRef = FirebaseFirestore.instance
          .collection('artisans')
          .doc(widget.artisan.uid);
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.artisan.uid);

      final updates = {
        'approvalStatus': status,
        'isAvailable': status == 'approved',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // set(merge:true) instead of update() — update() throws if either
      // doc doesn't exist, which would abort the WHOLE batch (a batch is
      // all-or-nothing) and leave the application stuck un-reviewed with a
      // raw Firestore error as the only feedback.
      batch.set(artisanRef, updates, SetOptions(merge: true));
      batch.set(userRef, {'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      await batch.commit();
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      await AdminAuditService(FirebaseFirestore.instance).log(
        action: status == 'approved'
            ? AdminAction.artisanApproved
            : AdminAction.artisanRejected,
        adminId: adminId,
        targetId: widget.artisan.uid,
        targetType: 'artisan',
      );
    } catch (e) {
      debugPrint('[AdminDashboard] artisan approval update failed: $e');
      if (mounted) {
        setState(() => _error = 'Failed to update application: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm(String action, String status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '$action Artisan?',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Are you sure you want to $action ${widget.artisan.name}\'s application?',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: status == 'approved'
                  ? context.colors.accent
                  : context.colors.error,
            ),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed == true) await _updateStatus(status);
  }

  @override
  Widget build(BuildContext context) {
    final artisan = widget.artisan;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _avatar(artisan),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artisan.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        artisan.category ?? 'General',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      if (artisan.location != null)
                        Text(
                          artisan.location!,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textTertiary,
                            fontFamily: 'Inter',
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    // context.colors.warning/warningSurface, not the fixed
                    // light-mode-only hex literals this hardcoded before —
                    // those never adapted for dark mode.
                    color: context.colors.warningSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.colors.warning,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bio
          if (artisan.bio != null && artisan.bio!.isNotEmpty) ...[
            Divider(height: 1, color: context.colors.borderLight),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'About',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textTertiary,
                  fontFamily: 'Inter',
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                artisan.bio!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                  height: 1.5,
                ),
              ),
            ),
          ],

          // Skills
          if (artisan.skills.isNotEmpty) ...[
            Divider(height: 1, color: context.colors.borderLight),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Skills',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textTertiary,
                  fontFamily: 'Inter',
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: artisan.skills
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .map(
                      (s) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.primarySurface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.primary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],

          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _error!,
                style: TextStyle(
                  color: context.colors.error,
                  fontSize: 12,
                  fontFamily: 'Inter',
                ),
              ),
            ),

          // Action buttons
          Divider(height: 1, color: context.colors.borderLight),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _loading
                ? Center(
                    child: SizedBox(
                      height: 36,
                      child: CircularProgressIndicator(
                        color: context.colors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirm('Reject', 'rejected'),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: context.colors.error,
                          ),
                          label: Text(
                            'Reject',
                            style: TextStyle(
                              color: context.colors.error,
                              fontFamily: 'Inter',
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: context.colors.error),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _confirm('Approve', 'approved'),
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text(
                            'Approve',
                            style: TextStyle(fontFamily: 'Inter'),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.colors.accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(ArtisanModel artisan) {
    if (artisan.profileImageUrl != null) {
      return CircleAvatar(
        radius: 26,
        backgroundImage: NetworkImage(artisan.profileImageUrl!),
        backgroundColor: context.colors.primarySurface,
      );
    }
    return CircleAvatar(
      radius: 26,
      backgroundColor: context.colors.primarySurface,
      child: Text(
        artisan.name.isNotEmpty ? artisan.name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: context.colors.primary,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// All artisans tab (searchable list with status filters)
// ---------------------------------------------------------------------------

final _allArtisansProvider = StreamProvider<List<ArtisanModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('artisans')
        .orderBy('createdAt', descending: true)
        .limit(200),
    (d) => ArtisanModel.fromJson({...d.data(), 'uid': d.id}),
    debugLabel: 'allArtisans',
  );
});

class _AllArtisansTab extends ConsumerStatefulWidget {
  const _AllArtisansTab();

  @override
  ConsumerState<_AllArtisansTab> createState() => _AllArtisansTabState();
}

const _kArtisanCategories = [
  'all', 'Plumbing', 'Electrical', 'Cleaning', 'Carpentry',
  'Painting', 'Welding', 'Tiling', 'Generator',
];

class _AllArtisansTabState extends ConsumerState<_AllArtisansTab> {
  String _approvalFilter = 'all';
  String _verifFilter = 'all';
  String _categoryFilter = 'all';
  String _sortBy = 'name';
  String _search = '';
  ArtisanModel? _selected;

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(ref.watch(themeProvider));
    final allAsync = ref.watch(_allArtisansProvider);

    return Column(
      children: [
        // Search + filter bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              TextField(
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Search by name, category, or username…',
                  prefixIcon: Icon(Icons.search_rounded),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _approvalFilter,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Status')),
                        DropdownMenuItem(value: 'approved', child: Text('Approved')),
                        DropdownMenuItem(value: 'pending', child: Text('Pending')),
                        DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _approvalFilter = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _categoryFilter,
                      items: _kArtisanCategories
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                    c == 'all' ? 'All Categories' : c),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _categoryFilter = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _verifFilter,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Any Verif.')),
                        DropdownMenuItem(value: 'unverified', child: Text('Unverified')),
                        DropdownMenuItem(value: 'id_submitted', child: Text('ID Submitted')),
                        DropdownMenuItem(value: 'id_verified', child: Text('ID Verified')),
                        DropdownMenuItem(value: 'trusted', child: Text('Trusted')),
                        // 'beta' is a sentinel, not a real verificationStatus
                        // value — matched against betaTester below, not
                        // verificationStatus, since "Beta Testers" is a
                        // different filter dimension entirely (see
                        // matchesVerif's special case).
                        DropdownMenuItem(value: 'beta', child: Text('Beta Testers')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _verifFilter = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _sortBy,
                      items: const [
                        DropdownMenuItem(value: 'name', child: Text('Sort: Name')),
                        DropdownMenuItem(value: 'rating', child: Text('Sort: Rating')),
                        DropdownMenuItem(value: 'jobs', child: Text('Sort: Jobs')),
                        DropdownMenuItem(value: 'trust', child: Text('Sort: Trust')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _sortBy = v);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // List
        Expanded(
          child: allAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: context.colors.primary),
            ),
            error: (e, st) {
              debugPrint('[AdminDashboard] stream error: $e\n$st');
              return const _AdminErrorState();
            },
            data: (artisans) {
              var filtered = artisans.where((a) {
                final matchesApproval =
                    _approvalFilter == 'all' ||
                    a.approvalStatus == _approvalFilter;
                final matchesVerif = _verifFilter == 'all' ||
                    (_verifFilter == 'beta'
                        ? a.betaTester
                        : a.verificationStatus == _verifFilter);
                final matchesCategory =
                    _categoryFilter == 'all' ||
                    a.category == _categoryFilter;
                final matchesSearch =
                    _search.isEmpty ||
                    a.name.toLowerCase().contains(_search) ||
                    (a.category?.toLowerCase().contains(_search) ?? false) ||
                    (a.username?.toLowerCase().contains(_search) ?? false);
                return matchesApproval && matchesVerif && matchesCategory &&
                    matchesSearch;
              }).toList();

              switch (_sortBy) {
                case 'rating':
                  filtered.sort((a, b) => b.rating.compareTo(a.rating));
                case 'jobs':
                  filtered.sort(
                      (a, b) => b.completedJobs.compareTo(a.completedJobs));
                case 'trust':
                  filtered
                      .sort((a, b) => b.trustScore.compareTo(a.trustScore));
                default:
                  filtered.sort((a, b) => a.name.compareTo(b.name));
              }

              final table = AdminDataTable<ArtisanModel>(
                palette: palette,
                selected: _selected,
                emptyIcon: Icons.search_off_rounded,
                emptyTitle: 'No artisans found',
                emptySubtitle: 'Try a different search or filter.',
                columns: const [
                  AdminTableColumn('Name', flex: 3),
                  AdminTableColumn('Category', flex: 2),
                  AdminTableColumn('Status', flex: 2),
                  AdminTableColumn('Rating', flex: 1),
                ],
                rows: filtered,
                onRowTap: (a) => setState(() => _selected = a),
                rowBuilder: (context, a, selected) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AdminPalette.blue.withValues(alpha: 0.18),
                              child: Text(
                                a.name.isNotEmpty ? a.name[0].toUpperCase() : '?',
                                style: TextStyle(
                                    color: AdminPalette.blue,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Inter'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(a.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: palette.textPrimary,
                                      fontFamily: 'Inter')),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(a.category ?? '—',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: palette.textSecondary,
                                    fontFamily: 'Inter')),
                            if (a.betaTester)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AdminPalette.indigo.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.science_rounded,
                                        size: 10, color: AdminPalette.indigo),
                                    const SizedBox(width: 3),
                                    Text('Beta',
                                        style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: AdminPalette.indigo,
                                            fontFamily: 'Inter')),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (a.approvalStatus == 'approved'
                                    ? AdminPalette.green
                                    : a.approvalStatus == 'rejected'
                                        ? AdminPalette.red
                                        : AdminPalette.amber)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            a.approvalStatus,
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: a.approvalStatus == 'approved'
                                    ? AdminPalette.green
                                    : a.approvalStatus == 'rejected'
                                        ? AdminPalette.red
                                        : AdminPalette.amber,
                                fontFamily: 'Inter'),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Row(
                          children: [
                            Icon(Icons.star_rounded, size: 13, color: AdminPalette.amber),
                            const SizedBox(width: 2),
                            Text(
                              a.totalRatings == 0 ? 'New' : a.rating.toStringAsFixed(1),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: palette.textSecondary,
                                  fontFamily: 'Inter'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                narrowRowBuilder: (context, a, selected) {
                  final statusColor = a.approvalStatus == 'approved'
                      ? AdminPalette.green
                      : a.approvalStatus == 'rejected'
                          ? AdminPalette.red
                          : AdminPalette.amber;
                  return Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: AdminPalette.blue.withValues(alpha: 0.18),
                              child: Text(
                                a.name.isNotEmpty ? a.name[0].toUpperCase() : '?',
                                style: TextStyle(
                                    color: AdminPalette.blue,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Inter'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(a.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: palette.textPrimary,
                                      fontFamily: 'Inter')),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                a.approvalStatus,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                    fontFamily: 'Inter'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(a.category ?? '—',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: palette.textSecondary,
                                    fontFamily: 'Inter')),
                            Text('·', style: TextStyle(color: palette.textTertiary)),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_rounded, size: 13, color: AdminPalette.amber),
                                const SizedBox(width: 2),
                                Text(
                                  a.totalRatings == 0 ? 'New' : a.rating.toStringAsFixed(1),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: palette.textSecondary,
                                      fontFamily: 'Inter'),
                                ),
                              ],
                            ),
                            if (a.betaTester)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AdminPalette.indigo.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.science_rounded,
                                        size: 10, color: AdminPalette.indigo),
                                    const SizedBox(width: 3),
                                    Text('Beta',
                                        style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: AdminPalette.indigo,
                                            fontFamily: 'Inter')),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );

              return AdminMasterDetail(
                palette: palette,
                table: table,
                detail: _selected == null ? null : _ArtisanListTile(artisan: _selected!),
                detailKey: _selected?.uid,
                detailTitle: _selected?.name ?? 'Artisan',
                onCloseDetail: () => setState(() => _selected = null),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ArtisanListTile extends StatelessWidget {
  final ArtisanModel artisan;

  const _ArtisanListTile({required this.artisan});

  Color _statusColor(BuildContext context) {
    switch (artisan.approvalStatus) {
      case 'approved':
        return context.colors.accent;
      case 'rejected':
        return context.colors.error;
      default:
        // context.colors.warning, not a fixed light-mode-only hex literal.
        return context.colors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/artisan/${artisan.uid}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: context.colors.primarySurface,
                  backgroundImage: artisan.profileImageUrl != null
                      ? NetworkImage(artisan.profileImageUrl!)
                      : null,
                  child: artisan.profileImageUrl == null
                      ? Text(
                          artisan.name.isNotEmpty
                              ? artisan.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.colors.primary,
                            fontFamily: 'Inter',
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artisan.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        artisan.category ?? 'General',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      if (artisan.email != null)
                        Text(
                          artisan.email!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.colors.textTertiary,
                            fontFamily: 'Inter',
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(context).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    // Explicit "Approval:" prefix — this chip and the
                    // adminStat row below it ("Verification: …") are easy
                    // to conflate otherwise; both are distinct gates
                    // ArtisanEligibility.canQuote checks together.
                    'Approval: ${artisan.approvalStatus}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _statusColor(context),
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: context.colors.borderLight),
            const SizedBox(height: 10),
            // Admin-visible trust signals — read-only, no new permissions.
            Row(
              children: [
                _adminStat(
                  context,
                  Icons.verified_outlined,
                  '${artisan.trustScore.toStringAsFixed(0)}/100 '
                  '(${TrustScoreService.tierLabel(artisan.trustScore)})',
                ),
                const SizedBox(width: 14),
                _adminStat(
                  context,
                  Icons.star_rounded,
                  artisan.totalRatings > 0
                      ? artisan.rating.toStringAsFixed(1)
                      : 'New',
                ),
                const SizedBox(width: 14),
                _adminStat(
                  context,
                  Icons.check_circle_outline_rounded,
                  '${artisan.completedJobs} jobs',
                ),
              ],
            ),
            const SizedBox(height: 6),
            _adminStat(
              context,
              Icons.fingerprint_rounded,
              'Verification: ${artisan.verificationStatus}',
            ),
            const SizedBox(height: 6),
            _EligibleToQuoteRow(artisan: artisan),
            const SizedBox(height: 10),
            Divider(height: 1, color: context.colors.borderLight),
            const SizedBox(height: 10),
            _BetaTesterSwitchTile(artisan: artisan),
          ],
        ),
      ),
    );
  }

  Widget _adminStat(BuildContext context, IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: context.colors.textTertiary),
      const SizedBox(width: 4),
      Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: context.colors.textSecondary,
          fontFamily: 'Inter',
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Verification Center tab — review selfie + government ID submissions
// ---------------------------------------------------------------------------

class _VerificationCenterTab extends ConsumerWidget {
  const _VerificationCenterTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingVerificationsProvider);

    return pendingAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      ),
      error: (e, st) {
        // Admin sees a friendly message; the real Firestore error (e.g. a
        // missing composite index) is logged for debugging instead of
        // being silently swallowed.
        debugPrint('[AdminDashboard] stream error: $e\n$st');
        return const _AdminErrorState();
      },
      data: (verifications) {
        if (verifications.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 56,
                  color: context.colors.accent,
                ),
                SizedBox(height: 12),
                Text(
                  'No pending verifications',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: verifications.length,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) =>
              _VerificationReviewCard(verification: verifications[i]),
        );
      },
    );
  }
}

class _VerificationReviewCard extends ConsumerStatefulWidget {
  final VerificationModel verification;

  const _VerificationReviewCard({required this.verification});

  @override
  ConsumerState<_VerificationReviewCard> createState() =>
      _VerificationReviewCardState();
}

class _VerificationReviewCardState
    extends ConsumerState<_VerificationReviewCard> {
  bool _loading = false;

  Future<void> _approve() async {
    final reviewerId = ref.read(currentUserProvider).asData?.value?.uid;
    if (reviewerId == null) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(verificationServiceProvider)
          .approve(uid: widget.verification.uid, reviewerId: reviewerId);
      await AdminAuditService(FirebaseFirestore.instance).log(
        action: AdminAction.verificationApproved,
        adminId: reviewerId,
        targetId: widget.verification.uid,
        targetType: 'verification',
      );
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Approve failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reject() async {
    final reviewerId = ref.read(currentUserProvider).asData?.value?.uid;
    if (reviewerId == null) return;

    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Reject Verification',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Reason (e.g. "ID photo is blurry, please resubmit")',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(reasonController.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty) return;

    setState(() => _loading = true);
    try {
      await ref
          .read(verificationServiceProvider)
          .reject(
            uid: widget.verification.uid,
            reviewerId: reviewerId,
            reason: reason,
          );
      await AdminAuditService(FirebaseFirestore.instance).log(
        action: AdminAction.verificationRejected,
        adminId: reviewerId,
        targetId: widget.verification.uid,
        targetType: 'verification',
        metadata: {'reason': reason},
      );
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Reject failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) {
              debugPrint('[AdminVerification] full-screen image load failed for $url: $error');
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 48),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.verification;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              v.uid,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _VerificationThumb(
                    label: 'Selfie',
                    url: v.selfieUrl,
                    onTap: () => _openImage(v.selfieUrl),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _VerificationThumb(
                    label: 'Government ID',
                    url: v.governmentIdUrl,
                    onTap: () => _openImage(v.governmentIdUrl),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: context.colors.borderLight),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _loading
                ? Center(
                    child: SizedBox(
                      height: 36,
                      child: CircularProgressIndicator(
                        color: context.colors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _reject,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: context.colors.error,
                          ),
                          label: Text(
                            'Reject',
                            style: TextStyle(
                              color: context.colors.error,
                              fontFamily: 'Inter',
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: context.colors.error),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _approve,
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text(
                            'Approve',
                            style: TextStyle(fontFamily: 'Inter'),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.colors.accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Disputes tab — review evidence from both parties, resolve or dismiss
// ---------------------------------------------------------------------------

class _DisputesTab extends ConsumerWidget {
  const _DisputesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputesAsync = ref.watch(openDisputesProvider);

    return disputesAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      ),
      error: (e, st) {
        // Admin sees a friendly message; the real Firestore error (e.g. a
        // missing composite index) is logged for debugging instead of
        // being silently swallowed.
        debugPrint('[AdminDashboard] stream error: $e\n$st');
        return const _AdminErrorState();
      },
      data: (disputes) {
        if (disputes.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.gavel_outlined,
                  size: 56,
                  color: context.colors.accent,
                ),
                SizedBox(height: 12),
                Text(
                  'No open disputes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: disputes.length,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) => _DisputeReviewCard(dispute: disputes[i]),
        );
      },
    );
  }
}

class _DisputeReviewCard extends ConsumerStatefulWidget {
  final DisputeModel dispute;

  const _DisputeReviewCard({required this.dispute});

  @override
  ConsumerState<_DisputeReviewCard> createState() => _DisputeReviewCardState();
}

class _DisputeReviewCardState extends ConsumerState<_DisputeReviewCard> {
  bool _loading = false;

  /// Stage 4 (HT-007, D3): a dispute decision now always carries a money
  /// outcome — release / full refund / split — executed server-side by
  /// adminResolveDispute (admin-checked, idempotent, audited). "Dismiss"
  /// simply preselects release to the artisan. The previous free-text-only
  /// resolution moved no money and is no longer permitted by the rules.
  Future<void> _resolve({required bool dismiss}) async {
    final decision = await showSettlementDialog(
      context,
      title: dismiss ? 'Dismiss Dispute' : 'Resolve Dispute',
      jobId: widget.dispute.jobId,
      initialOutcome: 'release',
    );
    if (decision == null || !mounted) return;

    setState(() => _loading = true);
    try {
      await ref.read(adminFinanceServiceProvider).resolveDispute(
            jobId: widget.dispute.jobId,
            disputeId: widget.dispute.id,
            outcome: decision.outcome,
            reason: decision.reason,
            artisanAmount: decision.artisanAmount,
            refundAmount: decision.refundAmount,
          );
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Resolution failed: ${adminFinanceErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _evidenceRow(List<String> urls) => urls.isEmpty
      ? const SizedBox.shrink()
      : SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, index) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () => _openImage(urls[i]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  urls[i],
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final d = widget.dispute;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              'Job ${d.jobId}',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Customer Complaint',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              d.reason,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
          ),
          if (d.evidenceImageUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _evidenceRow(d.evidenceImageUrls),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Artisan Response',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              d.artisanResponseText ?? 'No response yet.',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
          ),
          if (d.artisanEvidenceUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _evidenceRow(d.artisanEvidenceUrls),
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: context.colors.borderLight),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _loading
                ? Center(
                    child: SizedBox(
                      height: 36,
                      child: CircularProgressIndicator(
                        color: context.colors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _resolve(dismiss: true),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.textSecondary,
                            side: BorderSide(color: context.colors.border),
                          ),
                          child: const Text('Dismiss'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _resolve(dismiss: false),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.colors.accent,
                          ),
                          child: const Text('Resolve'),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Users tab — search/filter all accounts, suspend/reactivate
// ---------------------------------------------------------------------------

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  String _filter = 'all';
  String _search = '';
  String _sortBy = 'name';
  bool _sortAsc = true;
  UserModel? _selected;

  void _onSort(int columnIndex) {
    const byIndex = ['name', 'role', 'status', 'joined'];
    final col = byIndex[columnIndex];
    setState(() {
      if (_sortBy == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortBy = col;
        _sortAsc = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(ref.watch(themeProvider));
    final usersAsync = ref.watch(_allUsersProvider);
    // Beta Tester badge + filter (design/BETA_TESTING_GUIDE.md) — betaTester
    // lives on artisans/{uid}, not users/{uid}, so the uid set is built
    // once here from the same _allArtisansProvider _AllArtisansTab already
    // uses, rather than watching a per-row provider per user in the filter.
    final betaTesterUids = (ref.watch(_allArtisansProvider).valueOrNull ?? [])
        .where((a) => a.betaTester)
        .map((a) => a.uid)
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  style: TextStyle(color: palette.textPrimary, fontFamily: 'Inter'),
                  decoration: InputDecoration(
                    hintText: 'Search by name or email…',
                    hintStyle: TextStyle(color: palette.textTertiary),
                    prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
                    filled: true,
                    fillColor: palette.bg1,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filter,
                dropdownColor: palette.bg2,
                style: TextStyle(color: palette.textPrimary, fontFamily: 'Inter'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'customer', child: Text('Customers')),
                  DropdownMenuItem(value: 'artisan', child: Text('Artisans')),
                  DropdownMenuItem(
                    value: 'suspended',
                    child: Text('Suspended'),
                  ),
                  DropdownMenuItem(
                    value: 'beta',
                    child: Text('Beta Testers'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _filter = v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: usersAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: context.colors.primary),
              ),
              error: (e, st) {
                debugPrint('[AdminDashboard] stream error: $e\n$st');
                return const _AdminErrorState();
              },
              data: (users) {
                final filtered = users.where((u) {
                  final matchesFilter =
                      _filter == 'all' ||
                      (_filter == 'suspended' && u.isSuspended) ||
                      (_filter == 'customer' && u.isCustomer) ||
                      (_filter == 'artisan' && u.isArtisan) ||
                      (_filter == 'beta' && betaTesterUids.contains(u.uid));
                  final matchesSearch =
                      _search.isEmpty ||
                      u.name.toLowerCase().contains(_search) ||
                      (u.email?.toLowerCase().contains(_search) ?? false);
                  return matchesFilter && matchesSearch;
                }).toList();

                switch (_sortBy) {
                  case 'role':
                    filtered.sort((a, b) => a.isArtisan == b.isArtisan
                        ? 0
                        : (a.isArtisan ? 1 : -1));
                  case 'status':
                    filtered.sort((a, b) =>
                        a.isSuspended == b.isSuspended ? 0 : (a.isSuspended ? 1 : -1));
                  case 'joined':
                    filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                  default:
                    filtered.sort((a, b) => a.name.compareTo(b.name));
                }
                if (!_sortAsc) {
                  filtered.setAll(0, filtered.reversed.toList());
                }

                final table = AdminDataTable<UserModel>(
                  palette: palette,
                  selected: _selected,
                  emptyIcon: Icons.people_outline_rounded,
                  emptyTitle: 'No users found',
                  emptySubtitle: 'Try a different search or filter.',
                  sortColumnIndex: ['name', 'role', 'status', 'joined'].indexOf(_sortBy),
                  sortAscending: _sortAsc,
                  onSort: _onSort,
                  columns: const [
                    AdminTableColumn('Name', flex: 3, sortable: true),
                    AdminTableColumn('Role', flex: 2, sortable: true),
                    AdminTableColumn('Status', flex: 2, sortable: true),
                    AdminTableColumn('Joined', flex: 2, sortable: true),
                  ],
                  rows: filtered,
                  onRowTap: (u) => setState(() => _selected = u),
                  rowBuilder: (context, u, selected) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AdminPalette.indigo.withValues(alpha: 0.18),
                                child: Text(
                                  u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                      color: AdminPalette.indigo,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Inter'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(u.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: palette.textPrimary,
                                        fontFamily: 'Inter')),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(u.isArtisan ? 'Artisan' : 'Customer',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: palette.textSecondary,
                                      fontFamily: 'Inter')),
                              if (betaTesterUids.contains(u.uid))
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AdminPalette.indigo.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.science_rounded,
                                          size: 10, color: AdminPalette.indigo),
                                      const SizedBox(width: 3),
                                      Text('Beta',
                                          style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: AdminPalette.indigo,
                                              fontFamily: 'Inter')),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (u.isSuspended ? AdminPalette.red : AdminPalette.green)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              u.isSuspended ? 'Suspended' : 'Active',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: u.isSuspended ? AdminPalette.red : AdminPalette.green,
                                  fontFamily: 'Inter'),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(DateFormat('d MMM yyyy').format(u.createdAt),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: palette.textTertiary,
                                  fontFamily: 'Inter')),
                        ),
                      ],
                    ),
                  ),
                  narrowRowBuilder: (context, u, selected) => Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: AdminPalette.indigo.withValues(alpha: 0.18),
                              child: Text(
                                u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    color: AdminPalette.indigo,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Inter'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(u.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: palette.textPrimary,
                                      fontFamily: 'Inter')),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (u.isSuspended ? AdminPalette.red : AdminPalette.green)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                u.isSuspended ? 'Suspended' : 'Active',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: u.isSuspended ? AdminPalette.red : AdminPalette.green,
                                    fontFamily: 'Inter'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(u.isArtisan ? 'Artisan' : 'Customer',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: palette.textSecondary,
                                    fontFamily: 'Inter')),
                            Text('·', style: TextStyle(color: palette.textTertiary)),
                            Text('Joined ${DateFormat('d MMM yyyy').format(u.createdAt)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: palette.textTertiary,
                                    fontFamily: 'Inter')),
                            if (betaTesterUids.contains(u.uid))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AdminPalette.indigo.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.science_rounded,
                                        size: 10, color: AdminPalette.indigo),
                                    const SizedBox(width: 3),
                                    Text('Beta',
                                        style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: AdminPalette.indigo,
                                            fontFamily: 'Inter')),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );

                return AdminMasterDetail(
                  palette: palette,
                  table: table,
                  detail: _selected == null ? null : _UserListTile(user: _selected!),
                  detailKey: _selected?.uid,
                  detailTitle: _selected?.name ?? 'User',
                  onCloseDetail: () => setState(() => _selected = null),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// Beta testing (design/BETA_TESTING_GUIDE.md): lets an admin flag a
// SPECIFIC, already-approved artisan account so it can quote/be matched
// without completing real identity verification — for controlled test
// accounts only, never a general relaxation. betaTester is admin-only-
// writable (firestore.rules' artisans/{uid} update rule forbids the owner
// from touching it), so this widget is the only place it can ever be set.
// Does not touch verificationStatus, approvalStatus, or any production
// verification requirement — see isArtisanEligible() and isReallyVerified()
// in firestore.rules for exactly what changes.
//
// One shared widget, embedded in both _UserListTile (Users tab) and
// _ArtisanListTile (Artisans tab) — not two independently-written toggles.
// The caller must pass a stream-watched [artisan] so the switch reflects
// the live Firestore value after a toggle, not a stale snapshot.
class _BetaTesterSwitchTile extends StatefulWidget {
  final ArtisanModel artisan;
  final bool disabled;

  const _BetaTesterSwitchTile({required this.artisan, this.disabled = false});

  @override
  State<_BetaTesterSwitchTile> createState() => _BetaTesterSwitchTileState();
}

class _BetaTesterSwitchTileState extends State<_BetaTesterSwitchTile> {
  bool _toggling = false;

  Future<void> _toggle() async {
    final artisan = widget.artisan;
    final next = !artisan.betaTester;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          next ? 'Enable Beta Tester?' : 'Disable Beta Tester?',
          style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: Text(
          next
              ? 'This artisan will be allowed to participate in beta testing and may bypass selected restrictions intended only for testing.'
              : 'This artisan will lose beta testing privileges immediately.',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(next ? 'Enable' : 'Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _toggling = true);
    try {
      await FirebaseFirestore.instance
          .collection('artisans')
          .doc(artisan.uid)
          .set({'betaTester': next}, SetOptions(merge: true));
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      // action type 'beta_tester_changed' (design/BETA_TESTING_GUIDE.md) —
      // previousValue/newValue recorded explicitly rather than just the
      // new value, so the audit trail shows what actually changed, not
      // just what it ended up as.
      await AdminAuditService(FirebaseFirestore.instance).log(
        action: AdminAction.betaTesterChanged,
        adminId: adminId,
        targetId: artisan.uid,
        targetType: 'artisan',
        metadata: {
          'previousValue': artisan.betaTester,
          'newValue': next,
          'name': artisan.name,
        },
      );
    } catch (e) {
      debugPrint('[BetaTesterSwitchTile] toggle failed for ${artisan.uid}: $e');
      if (mounted) {
        showErrorSnackbar(context, 'Failed to update beta testing status: $e');
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final artisan = widget.artisan;
    return GestureDetector(
      // Absorbs the tap so an ancestor card's own onTap (e.g.
      // _ArtisanListTile navigates to the full profile on tap) doesn't
      // also fire when the admin taps this switch.
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text('🧪', style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Beta Tester',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            if (_toggling)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              Text(
                artisan.betaTester ? 'ON' : 'OFF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: artisan.betaTester
                      ? context.colors.accent
                      : context.colors.textTertiary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(width: 6),
              Switch(
                value: artisan.betaTester,
                onChanged: widget.disabled ? null : (_) => _toggle(),
                activeThumbColor: context.colors.accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Read-only "can this artisan actually quote right now" indicator, driven
/// by the same ArtisanEligibility.canQuote the real quote-eligibility gate
/// in the artisan Find Work screen/quote_service.dart uses — lets an admin
/// instantly see the *effect* of approval/verification/betaTester together,
/// not just each field in isolation.
class _EligibleToQuoteRow extends StatelessWidget {
  final ArtisanModel artisan;

  const _EligibleToQuoteRow({required this.artisan});

  @override
  Widget build(BuildContext context) {
    final eligible = ArtisanEligibility.canQuote(artisan);
    return Row(
      children: [
        Icon(Icons.task_alt_rounded, size: 14, color: context.colors.textTertiary),
        const SizedBox(width: 6),
        Text(
          'Eligible to Quote: ',
          style: TextStyle(
            fontSize: 12,
            color: context.colors.textSecondary,
            fontFamily: 'Inter',
          ),
        ),
        Text(
          eligible ? 'YES' : 'NO',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: eligible ? context.colors.accent : context.colors.error,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );
  }
}

class _UserListTile extends ConsumerStatefulWidget {
  final UserModel user;

  const _UserListTile({required this.user});

  @override
  ConsumerState<_UserListTile> createState() => _UserListTileState();
}

class _UserListTileState extends ConsumerState<_UserListTile> {
  bool _loading = false;
  bool _deleting = false;

  // Deletion is now entirely server-side (design/ADMIN_USER_DELETION_AUDIT.md)
  // — adminDeleteUser writes the audit log, deletes the Firebase Auth
  // account for real, cleans up Storage (profile photo, verification
  // documents, portfolio images), and deletes every Firestore document
  // that is this account's OWN personal data (users/artisans/verifications/
  // artisan_private/favorites/portfolio_projects/notifications). It
  // deliberately does not touch jobs/quotes/chats/payments/reviews/
  // disputes — those are the other party's history too. Previously this
  // method did a client-side Firestore batch (users/artisans only, no
  // audit log, no Storage cleanup) and then treated the Cloud Function
  // call as a best-effort side effect that only *disabled* sign-in; now
  // the Cloud Function is the single, authoritative, audited path, so a
  // failure here means the deletion genuinely did not happen — it must
  // not be swallowed as a soft warning.
  Future<void> _deleteUser() async {
    final user = widget.user;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete User?',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This permanently deletes ${user.name}\'s sign-in, profile'
          '${user.isArtisan ? ", artisan profile, and verification/portfolio photos" : " and photos"}. '
          "Their job history, payments, and reviews are kept — this cannot be undone.",
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: context.colors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminDeleteUser')
          .call({'uid': user.uid});
      debugPrint('[AdminDashboard] deleted ${user.uid}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.name} was deleted.')),
        );
      }
    } catch (e, st) {
      // Full technical detail (exception type, FirebaseFunctionsException
      // code/message, stack trace) goes to the debug log only — an admin
      // seeing "firebase_functions/not-found", a Dart stack trace, or
      // package-internal class names (CloudFunctionsHostApi,
      // MethodChannelHttpsCallable) is not actionable for them and leaks
      // implementation detail. The snackbar always shows one fixed,
      // friendly string regardless of what actually went wrong.
      debugPrint('[AdminDashboard] deleteUser failed for ${user.uid}: $e\n$st');
      if (mounted) {
        showErrorSnackbar(context, 'Unable to delete user. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _toggleSuspension() async {
    final user = widget.user;
    final newStatus = user.isSuspended ? 'active' : 'suspended';

    // Stage 4 (D9): a suspension must be classified. fraud / safety /
    // security freeze the artisan's payouts server-side (checked
    // immediately before every transfer and auto-release); administrative /
    // verification suspensions let existing jobs complete.
    String? suspensionType;
    if (!user.isSuspended) {
      suspensionType = await showSuspensionTypeDialog(context, userName: user.name);
      if (suspensionType == null || !mounted) return;
    }

    final confirmed = user.isSuspended ? await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          user.isSuspended ? 'Reactivate Account?' : 'Suspend Account?',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          user.isSuspended
              ? '${user.name} will regain access to the app.'
              : '${user.name} will be signed out and locked out of the app.',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: user.isSuspended
                  ? context.colors.accent
                  : context.colors.error,
            ),
            child: Text(user.isSuspended ? 'Reactivate' : 'Suspend'),
          ),
        ],
      ),
    ) : true;

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final statusFields = <String, dynamic>{
        'accountStatus': newStatus,
        'suspensionType': suspensionType ?? FieldValue.delete(),
      };
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        FirebaseFirestore.instance.collection('users').doc(user.uid),
        statusFields,
        SetOptions(merge: true),
      );
      if (user.isArtisan) {
        batch.set(
          FirebaseFirestore.instance.collection('artisans').doc(user.uid),
          statusFields,
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      await AdminAuditService(FirebaseFirestore.instance).log(
        action: user.isSuspended
            ? AdminAction.userReactivated
            : AdminAction.userSuspended,
        adminId: adminId,
        targetId: user.uid,
        targetType: 'user',
        metadata: {'name': user.name, 'newStatus': newStatus},
      );
    } catch (e) {
      debugPrint('[AdminDashboard] account status update failed: $e');
      if (mounted) showErrorSnackbar(context, 'Failed to update account: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Restructured from a single Row packing avatar + name/email + a fixed-
  // width action button into one line — on narrower screens (and once a
  // second action button was needed for delete) that Row overflowed,
  // which renders as Flutter's diagonal-striped "RenderFlex overflowed"
  // bar. Splitting into stacked rows (identity → chips → actions) keeps
  // every element within the available width regardless of screen size.
  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final artisan =
        user.isArtisan ? ref.watch(artisanProfileProvider(user.uid)).value : null;
    final busy = _loading || _deleting;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: context.colors.primarySurface,
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                        fontFamily: 'Inter',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      user.email ?? '—',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (user.isSuspended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.colors.errorSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Suspended',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.colors.error,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final role in user.roles) _chip(context, role),
              if (artisan != null) ...[
                _chip(
                  context,
                  '${artisan.trustScore.toStringAsFixed(0)}/100 trust',
                  icon: Icons.verified_outlined,
                ),
                _chip(
                  context,
                  'Verification: ${artisan.verificationStatus}',
                  icon: Icons.fingerprint_rounded,
                ),
                if (artisan.betaTester)
                  _chip(
                    context,
                    'Beta Tester',
                    icon: Icons.science_outlined,
                  ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: context.colors.borderLight),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: user.isArtisan
                      ? () => context.push('/artisan/${user.uid}')
                      : () => _showUserProfile(context, user),
                  icon: const Icon(Icons.person_outline_rounded, size: 14),
                  label: const Text('Profile'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.primary,
                    side: BorderSide(color: context.colors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showActivityHistory(context, user.uid),
                  icon: const Icon(Icons.history_rounded, size: 14),
                  label: const Text('Activity'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.primary,
                    side: BorderSide(color: context.colors.border),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : _toggleSuspension,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: user.isSuspended
                        ? context.colors.accent
                        : context.colors.error,
                    side: BorderSide(
                      color: user.isSuspended
                          ? context.colors.accent
                          : context.colors.error,
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(user.isSuspended ? 'Reactivate' : 'Suspend'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : _deleteUser,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.error,
                    side: BorderSide(color: context.colors.error),
                  ),
                  child: _deleting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: context.colors.error),
                        )
                      : const Text('Delete'),
                ),
              ),
            ],
          ),
          if (artisan != null) ...[
            const SizedBox(height: 8),
            _BetaTesterSwitchTile(artisan: artisan, disabled: busy),
            const SizedBox(height: 8),
            _EligibleToQuoteRow(artisan: artisan),
          ],
        ],
      ),
    );
  }

  void _showUserProfile(BuildContext context, UserModel user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          user.name,
          style: const TextStyle(
              fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _profileRow('Email', user.email ?? '—'),
            _profileRow('Phone', user.phoneNumber ?? '—'),
            _profileRow('Roles', user.roles.join(', ')),
            _profileRow('Status', user.accountStatus),
            _profileRow(
                'Member since',
                '${user.createdAt.day}/${user.createdAt.month}/'
                    '${user.createdAt.year}'),
            if (user.username != null && user.username!.isNotEmpty)
              _profileRow('Username', '@${user.username}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _profileRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(
                '$label:',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    fontFamily: 'Inter'),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style:
                    const TextStyle(fontSize: 13, fontFamily: 'Inter'),
              ),
            ),
          ],
        ),
      );

  void _showActivityHistory(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _UserActivitySheet(uid: uid),
    );
  }

  Widget _chip(BuildContext context, String text, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: context.colors.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// User activity history bottom sheet
// ---------------------------------------------------------------------------

class _UserActivitySheet extends StatelessWidget {
  final String uid;

  const _UserActivitySheet({required this.uid});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: ctx.colors.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ctx.colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  'Activity History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ctx.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchActivity(uid),
                  builder: (ctx2, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                            color: ctx2.colors.primary),
                      );
                    }
                    if (snap.hasError || snap.data == null) {
                      return Center(
                        child: Text(
                          'Could not load activity.',
                          style: TextStyle(
                              color: ctx2.colors.textSecondary,
                              fontFamily: 'Inter'),
                        ),
                      );
                    }
                    final items = snap.data!;
                    if (items.isEmpty) {
                      return Center(
                        child: Text(
                          'No recent jobs found.',
                          style: TextStyle(
                              color: ctx2.colors.textSecondary,
                              fontFamily: 'Inter'),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 8),
                      itemBuilder: (ctx3, i) {
                        final job = items[i];
                        final role =
                            job['customerId'] == uid ? 'Customer' : 'Artisan';
                        final ts = job['createdAt'];
                        final date = ts is Timestamp
                            ? ts.toDate()
                            : DateTime.now();
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: ctx3.colors.background,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: ctx3.colors.borderLight),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: ctx3.colors.primarySurface,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  role,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: ctx3.colors.primary,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      job['category'] as String? ??
                                          'Job',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: ctx3.colors.textPrimary,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                    Text(
                                      '${date.day}/${date.month}/${date.year}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: ctx3.colors.textTertiary,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: ctx3.colors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  job['status'] as String? ?? '—',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: ctx3.colors.textSecondary,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchActivity(String uid) async {
    final db = FirebaseFirestore.instance;
    final results = <Map<String, dynamic>>[];

    final asCustomer = await db
        .collection('jobs')
        .where('customerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .get();
    results.addAll(asCustomer.docs
        .map((d) => Map<String, dynamic>.from({...d.data(), 'id': d.id})));

    final asArtisan = await db
        .collection('jobs')
        .where('artisanId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .get();
    results.addAll(asArtisan.docs
        .map((d) => Map<String, dynamic>.from({...d.data(), 'id': d.id})));

    results.sort((a, b) {
      final ta = a['createdAt'];
      final tb = b['createdAt'];
      if (ta is Timestamp && tb is Timestamp) {
        return tb.compareTo(ta);
      }
      return 0;
    });
    return results.take(20).toList();
  }
}

// ---------------------------------------------------------------------------
// Support tab — review and respond to support tickets
// ---------------------------------------------------------------------------

class _SupportTicketsTab extends ConsumerStatefulWidget {
  const _SupportTicketsTab();

  @override
  ConsumerState<_SupportTicketsTab> createState() => _SupportTicketsTabState();
}

class _SupportTicketsTabState extends ConsumerState<_SupportTicketsTab> {
  String _search = '';
  String _filter = 'all';
  SupportTicketModel? _selected;

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(ref.watch(themeProvider));
    final ticketsAsync = ref.watch(allTicketsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  style: TextStyle(color: palette.textPrimary, fontFamily: 'Inter'),
                  decoration: InputDecoration(
                    hintText: 'Search by subject or user…',
                    hintStyle: TextStyle(color: palette.textTertiary),
                    prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
                    filled: true,
                    fillColor: palette.bg1,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filter,
                dropdownColor: palette.bg2,
                style: TextStyle(color: palette.textPrimary, fontFamily: 'Inter'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _filter = v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ticketsAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: context.colors.primary),
              ),
              error: (e, st) {
                debugPrint('[AdminDashboard] stream error: $e\n$st');
                return const _AdminErrorState();
              },
              data: (tickets) {
                final filtered = tickets.where((t) {
                  final matchesFilter = _filter == 'all' ||
                      (_filter == 'open' && t.status == 'open') ||
                      (_filter == 'resolved' && t.status != 'open');
                  final matchesSearch = _search.isEmpty ||
                      t.subject.toLowerCase().contains(_search) ||
                      t.userName.toLowerCase().contains(_search);
                  return matchesFilter && matchesSearch;
                }).toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                final table = AdminDataTable<SupportTicketModel>(
                  palette: palette,
                  selected: _selected,
                  emptyIcon: Icons.support_agent_outlined,
                  emptyTitle: 'No support tickets',
                  emptySubtitle: 'Customer and artisan tickets will appear here.',
                  columns: const [
                    AdminTableColumn('Subject', flex: 3),
                    AdminTableColumn('From', flex: 2),
                    AdminTableColumn('Status', flex: 1),
                    AdminTableColumn('Created', flex: 2),
                  ],
                  rows: filtered,
                  onRowTap: (t) => setState(() => _selected = t),
                  rowBuilder: (context, t, selected) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(t.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textPrimary,
                                  fontFamily: 'Inter')),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(t.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: palette.textSecondary,
                                  fontFamily: 'Inter')),
                        ),
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (t.status == 'open'
                                      ? AdminPalette.amber
                                      : AdminPalette.green)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              t.status == 'open' ? 'Open' : 'Resolved',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: t.status == 'open'
                                      ? AdminPalette.amber
                                      : AdminPalette.green,
                                  fontFamily: 'Inter'),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(DateFormat('d MMM yyyy').format(t.createdAt),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: palette.textTertiary,
                                  fontFamily: 'Inter')),
                        ),
                      ],
                    ),
                  ),
                  narrowRowBuilder: (context, t, selected) {
                    final statusColor =
                        t.status == 'open' ? AdminPalette.amber : AdminPalette.green;
                    return Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(t.subject,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: palette.textPrimary,
                                        fontFamily: 'Inter')),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  t.status == 'open' ? 'Open' : 'Resolved',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                      fontFamily: 'Inter'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('${t.userName} · ${DateFormat('d MMM yyyy').format(t.createdAt)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: palette.textSecondary,
                                  fontFamily: 'Inter')),
                        ],
                      ),
                    );
                  },
                );

                return AdminMasterDetail(
                  palette: palette,
                  table: table,
                  detail: _selected == null ? null : _TicketReviewCard(ticket: _selected!),
                  detailKey: _selected?.id,
                  detailTitle: _selected?.subject ?? 'Ticket',
                  onCloseDetail: () => setState(() => _selected = null),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TicketReviewCard extends ConsumerStatefulWidget {
  final SupportTicketModel ticket;

  const _TicketReviewCard({required this.ticket});

  @override
  ConsumerState<_TicketReviewCard> createState() => _TicketReviewCardState();
}

class _TicketReviewCardState extends ConsumerState<_TicketReviewCard> {
  bool _loading = false;

  Future<void> _respond() async {
    final responseController = TextEditingController();
    final response = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Respond & Resolve',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: responseController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Your response to the user',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(responseController.text.trim()),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );

    if (response == null || response.isEmpty) return;

    setState(() => _loading = true);
    try {
      await ref
          .read(supportTicketServiceProvider)
          .resolveTicket(ticketId: widget.ticket.id, adminResponse: response);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Resolve failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final resolved = t.status != 'open';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.subject,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
              Text(
                t.userName,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.textTertiary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t.message,
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
          if (t.adminResponse != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.accentSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Response: ${t.adminResponse}',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.accent,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
          if (!resolved) ...[
            const SizedBox(height: 10),
            _loading
                ? const Center(
                    child: SizedBox(
                      height: 28,
                      width: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _respond,
                      style: FilledButton.styleFrom(
                        backgroundColor: context.colors.accent,
                      ),
                      child: const Text('Respond & Resolve'),
                    ),
                  ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reviews tab — moderate reviews, with rating-aggregate cleanup on delete
// ---------------------------------------------------------------------------

class _ReviewsTab extends ConsumerStatefulWidget {
  const _ReviewsTab();

  @override
  ConsumerState<_ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends ConsumerState<_ReviewsTab> {
  String _search = '';
  String _sortBy = 'date';
  bool _sortAsc = false;
  ReviewModel? _selected;

  void _onSort(int columnIndex) {
    const byIndex = ['rating', 'comment', 'date'];
    final col = byIndex[columnIndex];
    setState(() {
      if (_sortBy == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortBy = col;
        _sortAsc = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(ref.watch(themeProvider));
    final reviewsAsync = ref.watch(allReviewsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
            style: TextStyle(color: palette.textPrimary, fontFamily: 'Inter'),
            decoration: InputDecoration(
              hintText: 'Search reviews by comment…',
              hintStyle: TextStyle(color: palette.textTertiary),
              prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
              filled: true,
              fillColor: palette.bg1,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.border),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: reviewsAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: context.colors.primary),
              ),
              error: (e, st) {
                debugPrint('[AdminDashboard] stream error: $e\n$st');
                return const _AdminErrorState();
              },
              data: (reviews) {
                final filtered = reviews
                    .where((r) =>
                        _search.isEmpty || r.comment.toLowerCase().contains(_search))
                    .toList();

                switch (_sortBy) {
                  case 'rating':
                    filtered.sort((a, b) => a.rating.compareTo(b.rating));
                  case 'comment':
                    filtered.sort((a, b) => a.comment.compareTo(b.comment));
                  default:
                    filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                }
                if (!_sortAsc) {
                  filtered.setAll(0, filtered.reversed.toList());
                }

                final table = AdminDataTable<ReviewModel>(
                  palette: palette,
                  selected: _selected,
                  emptyIcon: Icons.star_outline_rounded,
                  emptyTitle: 'No reviews yet',
                  emptySubtitle: 'Reviews appear here once customers rate completed jobs.',
                  sortColumnIndex: ['rating', 'comment', 'date'].indexOf(_sortBy),
                  sortAscending: _sortAsc,
                  onSort: _onSort,
                  columns: const [
                    AdminTableColumn('Rating', flex: 1, sortable: true),
                    AdminTableColumn('Comment', flex: 4, sortable: true),
                    AdminTableColumn('Date', flex: 2, sortable: true),
                  ],
                  rows: filtered,
                  onRowTap: (r) => setState(() => _selected = r),
                  rowBuilder: (context, r, selected) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, size: 13, color: AdminPalette.amber),
                              const SizedBox(width: 2),
                              Text('${r.rating}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: palette.textPrimary,
                                      fontFamily: 'Inter')),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                              r.comment.isEmpty ? '(no comment)' : r.comment,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: palette.textSecondary,
                                  fontFamily: 'Inter')),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(DateFormat('d MMM yyyy').format(r.createdAt),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: palette.textTertiary,
                                  fontFamily: 'Inter')),
                        ),
                      ],
                    ),
                  ),
                  narrowRowBuilder: (context, r, selected) => Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.star_rounded, size: 15, color: AdminPalette.amber),
                            const SizedBox(width: 3),
                            Text('${r.rating}',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: palette.textPrimary,
                                    fontFamily: 'Inter')),
                            const Spacer(),
                            Text(DateFormat('d MMM yyyy').format(r.createdAt),
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: palette.textTertiary,
                                    fontFamily: 'Inter')),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                            r.comment.isEmpty ? '(no comment)' : r.comment,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: palette.textSecondary,
                                fontFamily: 'Inter')),
                      ],
                    ),
                  ),
                );

                return AdminMasterDetail(
                  palette: palette,
                  table: table,
                  detail: _selected == null ? null : _AdminReviewCard(review: _selected!),
                  detailKey: _selected?.id,
                  detailTitle: 'Review · ${_selected?.rating ?? ''}★',
                  onCloseDetail: () => setState(() => _selected = null),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminReviewCard extends ConsumerStatefulWidget {
  final ReviewModel review;

  const _AdminReviewCard({required this.review});

  @override
  ConsumerState<_AdminReviewCard> createState() => _AdminReviewCardState();
}

class _AdminReviewCardState extends ConsumerState<_AdminReviewCard> {
  bool _loading = false;

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Review?',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This permanently removes the review and recalculates the artisan\'s rating.',
          style: TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;
      final review = widget.review;

      // Recompute the artisan's rating/totalRatings from the remaining
      // reviews so deleting one never leaves a stale aggregate behind.
      final otherDocs = await db
          .collection('reviews')
          .where('artisanId', isEqualTo: review.artisanId)
          .get();
      final remaining = otherDocs.docs
          .where((d) => d.id != review.id)
          .map((d) => (d.data()['rating'] as num).toDouble())
          .toList();

      final newCount = remaining.length;
      final newRating = newCount == 0
          ? 0.0
          : double.parse(
              (remaining.reduce((a, b) => a + b) / newCount).toStringAsFixed(2),
            );

      final batch = db.batch();
      batch.delete(db.collection('reviews').doc(review.id));
      // set(merge:true) instead of update() — the artisan doc may no longer
      // exist if an admin deleted that account, which would otherwise abort
      // this whole batch (including the review delete itself).
      batch.set(db.collection('artisans').doc(review.artisanId), {
        'rating': newRating,
        'totalRatings': newCount,
      }, SetOptions(merge: true));
      await batch.commit();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Delete failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReviewTile(
      review: widget.review,
      trailing: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: context.colors.error,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _delete,
            ),
    );
  }
}

class _VerificationThumb extends StatelessWidget {
  final String label;
  final String url;
  final VoidCallback onTap;

  const _VerificationThumb({
    required this.label,
    required this.url,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.colors.textTertiary,
              fontFamily: 'Inter',
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 1,
              child: url.isEmpty
                  ? Container(color: context.colors.borderLight)
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) {
                        debugPrint('[AdminVerification] image load failed for $url: $error');
                        return Container(
                          color: context.colors.borderLight,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: context.colors.textTertiary,
                            size: 20,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Jobs tab — read-only, real-time view of every job request. Job editing
// stays out of scope here; mutations remain JobService's exclusively.
// ---------------------------------------------------------------------------

class _JobsTab extends ConsumerStatefulWidget {
  const _JobsTab();

  @override
  ConsumerState<_JobsTab> createState() => _JobsTabState();
}

class _JobsTabState extends ConsumerState<_JobsTab> {
  String _filter = 'all';
  String _search = '';

  static const _statusFilters = [
    ('all', 'All'),
    ('requested', 'Requested'),
    ('matched', 'Assigned'),
    ('inProgress', 'In Progress'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
    ('disputed', 'Disputed'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(ref.watch(themeProvider));
    final jobsAsync = ref.watch(_allJobsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  style: TextStyle(color: palette.textPrimary, fontFamily: 'Inter'),
                  decoration: InputDecoration(
                    hintText:
                        'Search by job ID, category, customer or artisan…',
                    hintStyle: TextStyle(color: palette.textTertiary),
                    prefixIcon: Icon(Icons.search_rounded, color: palette.textTertiary),
                    filled: true,
                    fillColor: palette.bg1,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filter,
                dropdownColor: palette.bg2,
                style: TextStyle(color: palette.textPrimary, fontFamily: 'Inter'),
                items: _statusFilters
                    .map(
                      (f) => DropdownMenuItem(value: f.$1, child: Text(f.$2)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _filter = v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: jobsAsync.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: context.colors.primary),
              ),
              error: (e, st) {
                debugPrint('[AdminDashboard] stream error: $e\n$st');
                return const _AdminErrorState();
              },
              data: (jobs) {
                // Resolve customer/artisan names for every job currently in
                // view — keyed by a stable, sorted id string so repeat
                // lookups for the same set of people are cached, not refetched
                // on every snapshot tick.
                final ids = <String>{};
                for (final j in jobs) {
                  if (j.customerId.isNotEmpty) ids.add(j.customerId);
                  if (j.artisanId.isNotEmpty) ids.add(j.artisanId);
                }
                final idsKey = (ids.toList()..sort()).join(',');
                final names =
                    ref.watch(_jobPeopleNamesProvider(idsKey)).value ?? const {};

                final filtered = jobs.where((j) {
                  final matchesFilter =
                      _filter == 'all' || j.status.name == _filter;
                  if (!matchesFilter) return false;
                  if (_search.isEmpty) return true;
                  final customerName = (names[j.customerId] ?? '').toLowerCase();
                  final artisanName = (names[j.artisanId] ?? '').toLowerCase();
                  return j.id.toLowerCase().contains(_search) ||
                      j.category.toLowerCase().contains(_search) ||
                      customerName.contains(_search) ||
                      artisanName.contains(_search);
                }).toList();

                return AdminDataTable<JobModel>(
                  palette: palette,
                  emptyIcon: Icons.work_off_outlined,
                  emptyTitle: 'No jobs found',
                  emptySubtitle: 'Try a different search or filter.',
                  columns: const [
                    AdminTableColumn('Category', flex: 3),
                    AdminTableColumn('Customer', flex: 2),
                    AdminTableColumn('Artisan', flex: 2),
                    AdminTableColumn('Status', flex: 2),
                    AdminTableColumn('Created', flex: 2),
                  ],
                  rows: filtered,
                  onRowTap: (job) => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _JobDetailSheet(
                      job: job,
                      customerName: names[job.customerId],
                      artisanName: names[job.artisanId],
                    ),
                  ),
                  rowBuilder: (context, job, selected) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(job.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: palette.textPrimary,
                                      fontFamily: 'Inter')),
                              Text('#${job.id}',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: palette.textTertiary,
                                      fontFamily: 'Inter')),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                              names[job.customerId]?.isNotEmpty == true
                                  ? names[job.customerId]!
                                  : '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: palette.textSecondary,
                                  fontFamily: 'Inter')),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                              job.artisanId.isEmpty
                                  ? 'Unassigned'
                                  : (names[job.artisanId]?.isNotEmpty == true
                                      ? names[job.artisanId]!
                                      : '—'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: palette.textSecondary,
                                  fontFamily: 'Inter')),
                        ),
                        Expanded(
                          flex: 2,
                          child: JobStatusBadge(status: job.status, compact: true),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(DateFormat('d MMM yyyy').format(job.createdAt),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: palette.textTertiary,
                                  fontFamily: 'Inter')),
                        ),
                      ],
                    ),
                  ),
                  narrowRowBuilder: (context, job, selected) => Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(job.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: palette.textPrimary,
                                      fontFamily: 'Inter')),
                            ),
                            const SizedBox(width: 8),
                            JobStatusBadge(status: job.status, compact: true),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('#${job.id}',
                            style: TextStyle(
                                fontSize: 10,
                                color: palette.textTertiary,
                                fontFamily: 'Inter')),
                        const SizedBox(height: 8),
                        Text(
                          '${names[job.customerId]?.isNotEmpty == true ? names[job.customerId]! : '—'}'
                          ' → '
                          '${job.artisanId.isEmpty ? 'Unassigned' : (names[job.artisanId]?.isNotEmpty == true ? names[job.artisanId]! : '—')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: palette.textSecondary,
                              fontFamily: 'Inter'),
                        ),
                        const SizedBox(height: 4),
                        Text(DateFormat('d MMM yyyy').format(job.createdAt),
                            style: TextStyle(
                                fontSize: 11.5,
                                color: palette.textTertiary,
                                fontFamily: 'Inter')),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Read-only job detail sheet — view-only by design (no status/edit
/// controls); mutations remain exclusively JobService's. Links out to the
/// artisan's existing profile screen and surfaces quotes/dispute inline via
/// already-existing providers rather than duplicating their UI.
class _JobDetailSheet extends ConsumerStatefulWidget {
  final JobModel job;
  final String? customerName;
  final String? artisanName;

  const _JobDetailSheet({
    required this.job,
    required this.customerName,
    required this.artisanName,
  });

  @override
  ConsumerState<_JobDetailSheet> createState() => _JobDetailSheetState();
}

class _JobDetailSheetState extends ConsumerState<_JobDetailSheet> {
  bool _deleting = false;

  // Hard delete — distinct from every other mutation here, which goes
  // through JobService's state machine. Reserved for spam/fake job
  // requests an admin wants gone entirely, not a status transition.
  // Firestore rules already grant isAdmin() delete on /jobs; messages are
  // cleaned up best-effort (rules now allow isAdmin() to delete them too)
  // since deleting the job doc does not cascade-delete its subcollections.
  Future<void> _deleteJob() async {
    final job = widget.job;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Job Request?',
          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This permanently deletes the job and its chat history. Use this '
          'only for spam or fake requests — this cannot be undone.',
          style: TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: context.colors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      final db = FirebaseFirestore.instance;
      final jobRef = db.collection('jobs').doc(job.id);

      final messages = await jobRef.collection('messages').get();
      if (messages.docs.isNotEmpty) {
        final msgBatch = db.batch();
        for (final doc in messages.docs) {
          msgBatch.delete(doc.reference);
        }
        await msgBatch.commit();
      }

      await jobRef.delete();
      debugPrint('[AdminDashboard] deleted job ${job.id}');
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      await AdminAuditService(FirebaseFirestore.instance).log(
        action: AdminAction.jobDeleted,
        adminId: adminId,
        targetId: job.id,
        targetType: 'job',
        metadata: {'category': job.category, 'status': job.status.name},
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[AdminDashboard] deleteJob failed for ${job.id}: $e');
      if (mounted) showErrorSnackbar(context, 'Failed to delete job: $e');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final customerName = widget.customerName;
    final artisanName = widget.artisanName;
    final quotesAsync = ref.watch(jobQuotesProvider(job.id));
    final disputeAsync = ref.watch(disputeForJobProvider(job.id));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.category,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
                JobStatusBadge(status: job.status),
              ],
            ),
            Text(
              'Job ID: ${job.id}',
              style: TextStyle(
                fontSize: 11,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 16),
            _section(context, 'Description', job.description),
            const SizedBox(height: 14),
            _section(
              context,
              'Budget',
              (job.budgetMin == null && job.budgetMax == null)
                  ? 'Not specified'
                  : '₦${(job.budgetMin ?? 0).toStringAsFixed(0)} – ₦${(job.budgetMax ?? job.budgetMin ?? 0).toStringAsFixed(0)}',
            ),
            const SizedBox(height: 14),
            _section(
              context,
              'Created',
              DateFormat('d MMM yyyy, h:mm a').format(job.createdAt),
            ),
            // Stage 6 (P-K): the exact location now lives in the job's
            // private sub-document (admins may read it); legacy jobs not yet
            // migrated still carry it on the job itself.
            Consumer(builder: (context, ref, _) {
              final private = ref.watch(jobPrivateLocationProvider(job.id)).asData?.value;
              final address = (private?['customerAddress'] as String?) ?? job.customerAddress;
              if (address == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _section(context, 'Location', address),
              );
            }),
            const SizedBox(height: 18),
            Divider(color: context.colors.borderLight),
            const SizedBox(height: 10),
            // Customer — no dedicated admin customer-profile screen exists
            // yet; the existing Users tab (searchable) covers deeper detail.
            Text(
              'Customer',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              customerName?.isNotEmpty == true ? customerName! : job.customerId,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Assigned Artisan',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            if (job.artisanId.isEmpty)
              Text(
                'None yet',
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textSecondary,
                  fontFamily: 'Inter',
                ),
              )
            else
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/artisan/${job.artisanId}');
                },
                child: Row(
                  children: [
                    Text(
                      artisanName?.isNotEmpty == true
                          ? artisanName!
                          : job.artisanId,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.colors.primary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: context.colors.primary,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 14, color: context.colors.textTertiary),
                const SizedBox(width: 6),
                Text(
                  'Chat Exists: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textTertiary,
                    fontFamily: 'Inter',
                  ),
                ),
                ref.watch(jobHasChatProvider(job.id)).when(
                  loading: () => SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: context.colors.textTertiary),
                  ),
                  error: (_, _) => Text(
                    'Unknown',
                    style: TextStyle(fontSize: 12, color: context.colors.textTertiary),
                  ),
                  data: (exists) => Text(
                    exists ? 'Yes' : 'No',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: exists ? context.colors.accent : context.colors.textTertiary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Divider(color: context.colors.borderLight),
            const SizedBox(height: 10),
            Text(
              'Quotes',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            quotesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const _AdminErrorState(),
              data: (quotes) {
                if (quotes.isEmpty) {
                  return Text(
                    'No quotes submitted yet.',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  );
                }
                return Column(
                  children: quotes
                      .map(
                        (q) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: context.colors.surfaceVariant,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${q.artisanName} — ₦${q.amount.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: context.colors.textPrimary,
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                      if (q.materialsCost > 0)
                                        Text(
                                          'Labour ₦${q.laborCost.toStringAsFixed(0)} + Materials ₦${q.materialsCost.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: context.colors.textSecondary,
                                            fontFamily: 'Inter',
                                          ),
                                        ),
                                      if (q.artisanTrustScore > 0)
                                        Text(
                                          'Trust: ${q.artisanTrustScore.toStringAsFixed(1)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: context.colors.textTertiary,
                                            fontFamily: 'Inter',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  q.status.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.colors.textSecondary,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 18),
            Divider(color: context.colors.borderLight),
            const SizedBox(height: 10),
            Text(
              'Dispute',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            disputeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const _AdminErrorState(),
              data: (dispute) {
                if (dispute == null) {
                  return Text(
                    'No dispute on this job.',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  );
                }
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.colors.errorSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dispute.status.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.colors.error,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dispute.reason,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Review and resolve from the Disputes tab.',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.textSecondary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            // ── Appointment scheduling ───────────────────────────────────
            if (job.appointmentSlots.isNotEmpty || job.confirmedAppointment != null) ...[
              const SizedBox(height: 18),
              Divider(color: context.colors.borderLight),
              const SizedBox(height: 10),
              Text(
                'Appointment',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 8),
              if (job.confirmedAppointment != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.colors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_available_rounded,
                          size: 16, color: context.colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Confirmed: ${DateFormat('d MMM yyyy, h:mm a').format(job.confirmedAppointment!)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.colors.primary,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                )
              else if (job.appointmentSlots.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Proposed slots (${job.appointmentSlots.length}):',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...job.appointmentSlots.map(
                      (slot) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• ${DateFormat('d MMM yyyy, h:mm a').format(slot)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],

            // ── Before/After completion photos ───────────────────────────
            if (job.beforePhotoUrls.isNotEmpty || job.completionImageUrls.isNotEmpty) ...[
              const SizedBox(height: 18),
              Divider(color: context.colors.borderLight),
              const SizedBox(height: 10),
              Text(
                'Completion Photos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 8),
              if (job.beforePhotoUrls.isNotEmpty) ...[
                Text(
                  'Before (${job.beforePhotoUrls.length} photos)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: job.beforePhotoUrls.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (ctx, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        job.beforePhotoUrls[i],
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 80,
                          height: 80,
                          color: context.colors.surfaceVariant,
                          child: Icon(Icons.broken_image_outlined,
                              color: context.colors.textTertiary),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (job.completionImageUrls.isNotEmpty) ...[
                Text(
                  'After (${job.completionImageUrls.length} photos)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 80,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: job.completionImageUrls.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (ctx, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        job.completionImageUrls[i],
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 80,
                          height: 80,
                          color: context.colors.surfaceVariant,
                          child: Icon(Icons.broken_image_outlined,
                              color: context.colors.textTertiary),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 24),
            Divider(color: context.colors.borderLight),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _deleting ? null : _deleteJob,
                icon: _deleting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.colors.error),
                      )
                    : Icon(Icons.delete_outline_rounded, color: context.colors.error),
                label: Text(
                  _deleting ? 'Deleting…' : 'Delete Job Request',
                  style: TextStyle(color: context.colors.error, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.colors.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Only for spam or fake job requests.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: context.colors.textTertiary,
          fontFamily: 'Inter',
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(
          fontSize: 14,
          color: context.colors.textPrimary,
          fontFamily: 'Inter',
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Overview tab — stats cards, job progress, top artisans, recent reviews
// ---------------------------------------------------------------------------

/// Analytics — deep-dive metrics not already surfaced on the Dashboard home
/// page: live in-progress job timelines, top-rated artisans, recent reviews,
/// and the Phase 2A marketplace adoption metrics (appointment scheduling,
/// before/after photo capture, trust scoring).
class _AnalyticsTab extends ConsumerWidget {
  const _AnalyticsTab();

  static const _weeks = 8;

  /// Weekly bucket counts for the last [_weeks] weeks, oldest first.
  static List<double> _weeklyBuckets(Iterable<DateTime> dates) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1 + (_weeks - 1) * 7));
    final buckets = List<double>.filled(_weeks, 0);
    for (final d in dates) {
      final idx = d.difference(start).inDays ~/ 7;
      if (idx >= 0 && idx < _weeks) buckets[idx]++;
    }
    return buckets;
  }

  static List<String> _weekLabels() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1 + (_weeks - 1) * 7));
    return List.generate(
        _weeks, (i) => DateFormat('d MMM').format(start.add(Duration(days: i * 7))));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AdminPalette.of(ref.watch(themeProvider));
    final users = ref.watch(_allUsersProvider).value ?? [];
    final artisans = ref.watch(_allArtisansProvider).value ?? [];
    final jobs = ref.watch(_allJobsProvider).value ?? [];
    final reviews = ref.watch(allReviewsProvider).value ?? [];
    final disputes = ref.watch(_allDisputesProvider).value ?? [];
    final verifications = ref.watch(_allVerificationsProvider).value ?? [];

    final completedJobsList =
        jobs.where((j) => j.status == JobStatus.completed).toList();
    final completionRate =
        jobs.isEmpty ? 0.0 : completedJobsList.length / jobs.length * 100;
    final disputeRate = jobs.isEmpty ? 0.0 : disputes.length / jobs.length * 100;

    final decidedVerifications = verifications
        .where((v) =>
            v.status == VerificationStatus.approved ||
            v.status == VerificationStatus.rejected)
        .toList();
    final approvedVerifications =
        decidedVerifications.where((v) => v.status == VerificationStatus.approved).length;
    final verificationSuccessRate = decidedVerifications.isEmpty
        ? 0.0
        : approvedVerifications / decidedVerifications.length * 100;

    final avgRating = reviews.isEmpty
        ? 0.0
        : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
    final ratingCounts = List<int>.filled(5, 0);
    for (final r in reviews) {
      if (r.rating >= 1 && r.rating <= 5) ratingCounts[r.rating - 1]++;
    }

    final categoryCounts = <String, int>{};
    for (final j in jobs) {
      categoryCounts[j.category] = (categoryCounts[j.category] ?? 0) + 1;
    }
    final categoryEntries = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final userGrowth = _weeklyBuckets(users.map((u) => u.createdAt));
    final jobGrowth = _weeklyBuckets(jobs.map((j) => j.createdAt));
    final weekLabels = _weekLabels();

    final inProgressJobs =
        jobs.where((j) => j.status == JobStatus.inProgress).toList();

    // Phase 2A metrics
    final jobsWithApptSlots =
        jobs.where((j) => j.appointmentSlots.isNotEmpty).length;
    final jobsWithConfirmedAppt =
        jobs.where((j) => j.confirmedAppointment != null).length;
    final jobsWithBeforePhotos =
        jobs.where((j) => j.beforePhotoUrls.isNotEmpty).length;
    final trustScores = artisans
        .where((a) => a.trustScore > 0)
        .map((a) => a.trustScore)
        .toList();
    final avgTrustScore = trustScores.isEmpty
        ? 0.0
        : trustScores.reduce((a, b) => a + b) / trustScores.length;

    final topRated = ([...artisans]
          ..sort((a, b) => b.rating.compareTo(a.rating)))
        .where((a) => a.totalRatings >= 3)
        .take(5)
        .toList();

    final recentReviews = ([...reviews]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
        .take(5)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Rate cards ──────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = kIsWeb && constraints.maxWidth >= 900 ? 4 : 2;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.7,
                children: [
                  _rateCard(palette, 'Completion Rate',
                      '${completionRate.toStringAsFixed(0)}%', AdminPalette.green,
                      Icons.task_alt_rounded),
                  _rateCard(palette, 'Verification Success',
                      '${verificationSuccessRate.toStringAsFixed(0)}%', AdminPalette.blue,
                      Icons.verified_user_rounded),
                  _rateCard(palette, 'Dispute Rate',
                      '${disputeRate.toStringAsFixed(1)}%', AdminPalette.amber,
                      Icons.gavel_rounded),
                  _rateCard(palette, 'Average Rating',
                      avgRating.toStringAsFixed(1), AdminPalette.purple,
                      Icons.star_rounded),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // ── Growth + category distribution ─────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = kIsWeb && constraints.maxWidth >= 1100;
              final growthCard = AdminSectionCard(
                palette: palette,
                title: 'User & Job Growth (last 8 weeks)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 16,
                      children: [
                        ChartLegendDot(
                            color: AdminPalette.purple, label: 'New Users', palette: palette),
                        ChartLegendDot(
                            color: AdminPalette.cyan, label: 'New Jobs', palette: palette),
                      ],
                    ),
                    const SizedBox(height: 12),
                    JobsOverviewChart(
                      palette: palette,
                      xLabels: weekLabels,
                      created: userGrowth,
                      inProgress: jobGrowth,
                      completed: const [],
                      seriesNames: const ['New Users', 'New Jobs', ''],
                    ),
                  ],
                ),
              );
              final categoryCard = AdminSectionCard(
                palette: palette,
                title: 'Category Distribution',
                child: categoryEntries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text('No job data yet',
                            style: TextStyle(
                                color: palette.textTertiary, fontFamily: 'Inter')),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < categoryEntries.length; i++)
                            AdminCategoryBar(
                              palette: palette,
                              icon: _categoryIcons[categoryEntries[i].key.toLowerCase()] ??
                                  Icons.category_rounded,
                              color: _categoryColors[i % _categoryColors.length],
                              label: categoryEntries[i].key,
                              value: categoryEntries[i].value,
                              maxValue: categoryEntries.first.value,
                            ),
                        ],
                      ),
              );

              if (!wide) {
                return Column(
                  children: [growthCard, const SizedBox(height: 14), categoryCard],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: growthCard),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: categoryCard),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── Rating distribution ─────────────────────────────────────
          AdminSectionCard(
            palette: palette,
            title: 'Rating Distribution',
            child: reviews.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('No reviews yet',
                        style: TextStyle(color: palette.textTertiary, fontFamily: 'Inter')),
                  )
                : Column(
                    children: [
                      for (var star = 5; star >= 1; star--)
                        AdminCategoryBar(
                          palette: palette,
                          icon: Icons.star_rounded,
                          color: AdminPalette.amber,
                          label: '$star star${star == 1 ? '' : 's'}',
                          value: ratingCounts[star - 1],
                          maxValue: ratingCounts.fold(0, (m, v) => v > m ? v : m),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),

          _header(context, 'Marketplace Adoption Metrics'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Appt Slots Proposed',
                  value: '$jobsWithApptSlots',
                  icon: Icons.calendar_today_outlined,
                  color: const Color(0xFF6366F1),
                  onTap: null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Appt Confirmed',
                  value: '$jobsWithConfirmedAppt',
                  icon: Icons.event_available_rounded,
                  color: const Color(0xFF22C55E),
                  onTap: null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Before Photos Filed',
                  value: '$jobsWithBeforePhotos',
                  icon: Icons.photo_camera_outlined,
                  color: const Color(0xFFF59E0B),
                  onTap: null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Avg Trust Score',
                  value: avgTrustScore.toStringAsFixed(1),
                  icon: Icons.shield_outlined,
                  color: const Color(0xFF0EA5E9),
                  onTap: null,
                ),
              ),
            ],
          ),
          if (inProgressJobs.isNotEmpty) ...[
            const SizedBox(height: 24),
            _header(context, 'Job Progress Overview'),
            const SizedBox(height: 10),
            ...inProgressJobs
                .take(5)
                .map((j) => _JobProgressRow(job: j)),
          ],
          if (topRated.isNotEmpty) ...[
            const SizedBox(height: 24),
            _header(context, 'Top Rated Artisans'),
            const SizedBox(height: 10),
            ...topRated.map((a) => _TopArtisanRow(artisan: a)),
          ],
          if (recentReviews.isNotEmpty) ...[
            const SizedBox(height: 24),
            _header(context, 'Recent Reviews'),
            const SizedBox(height: 10),
            ...recentReviews.map((r) => ReviewTile(review: r)),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String title) => Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
          fontFamily: 'Inter',
        ),
      );

  Widget _rateCard(
    AdminPalette palette,
    String label,
    String value,
    Color color,
    IconData icon,
  ) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: palette.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                    fontFamily: 'Inter')),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5, color: palette.textTertiary, fontFamily: 'Inter')),
          ],
        ),
      );
}

/// Sign-out, theme, and account info for the signed-in admin.
class _AdminSettingsTab extends ConsumerWidget {
  const _AdminSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AdminPalette.of(ref.watch(themeProvider));
    final admin = ref.watch(currentUserProfileProvider).asData?.value;
    final themeMode = ref.watch(themeProvider);
    final firebaseUser = FirebaseAuth.instance.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionCard(
            palette: palette,
            title: 'Admin Account',
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
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
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter'),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(admin?.name ?? 'Admin',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                              fontFamily: 'Inter')),
                      Text(firebaseUser?.email ?? '',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: palette.textSecondary,
                              fontFamily: 'Inter')),
                      const SizedBox(height: 4),
                      Text('Super Administrator',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AdminPalette.indigo,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Inter')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AdminSectionCard(
            palette: palette,
            title: 'Appearance',
            child: Row(
              children: [
                Icon(
                  themeMode == ThemeMode.dark
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  color: AdminPalette.indigo,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    themeMode == ThemeMode.dark ? 'Dark theme' : 'Light theme',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                        fontFamily: 'Inter'),
                  ),
                ),
                Switch(
                  value: themeMode == ThemeMode.dark,
                  activeThumbColor: AdminPalette.indigo,
                  onChanged: (_) => ref.read(themeProvider.notifier).toggle(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AdminSectionCard(
            palette: palette,
            title: 'Session',
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    ref.read(authNotifierProvider.notifier).signOut(),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign Out'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminPalette.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                if (onTap != null) ...[
                  const Spacer(),
                  Icon(Icons.arrow_forward_rounded,
                      size: 13, color: context.colors.textTertiary),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobProgressRow extends StatelessWidget {
  final JobModel job;

  const _JobProgressRow({required this.job});

  @override
  Widget build(BuildContext context) {
    final stage = job.progressStage;
    final total = JobProgressStage.values.length;
    final current = stage != null ? stage.step + 1 : 0;

    return GestureDetector(
      onTap: () => context.push('/job/${job.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.category,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  if (stage != null)
                    Text(
                      stage.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: current / total,
                      backgroundColor: context.colors.borderLight,
                      color: context.colors.primary,
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${(current / total * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.colors.textTertiary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopArtisanRow extends StatelessWidget {
  final ArtisanModel artisan;

  const _TopArtisanRow({required this.artisan});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/artisan/${artisan.uid}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: context.colors.primarySurface,
              backgroundImage: artisan.profileImageUrl != null
                  ? NetworkImage(artisan.profileImageUrl!)
                  : null,
              child: artisan.profileImageUrl == null
                  ? Text(
                      artisan.name.isNotEmpty
                          ? artisan.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.colors.primary,
                        fontFamily: 'Inter',
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artisan.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  Text(
                    artisan.category ?? 'General',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Icon(Icons.star_rounded,
                    size: 14, color: context.colors.ratingGold),
                const SizedBox(width: 2),
                Text(
                  artisan.rating.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                Text(
                  ' (${artisan.totalRatings})',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.textTertiary,
                    fontFamily: 'Inter',
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

// ---------------------------------------------------------------------------
// Deletions tab — account deletion requests pending admin review
// ---------------------------------------------------------------------------

class _DeletionRequestsTab extends ConsumerStatefulWidget {
  const _DeletionRequestsTab();

  @override
  ConsumerState<_DeletionRequestsTab> createState() =>
      _DeletionRequestsTabState();
}

class _DeletionRequestsTabState extends ConsumerState<_DeletionRequestsTab> {
  final Map<String, bool> _processing = {};

  Future<void> _markResolved(String uid) async {
    setState(() => _processing[uid] = true);
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      batch.update(
        db.collection('account_deletion_requests').doc(uid),
        {
          'status': 'resolved',
          'resolvedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.set(
        db.collection('users').doc(uid),
        {'accountDeletionRequested': false},
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _processing.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(_deletionRequestsProvider);

    return requestsAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: context.colors.primary)),
      error: (e, st) {
        debugPrint('[AdminDashboard] deletion requests error: $e\n$st');
        return const _AdminErrorState();
      },
      data: (requests) {
        final pending =
            requests.where((r) => r['status'] == 'pending').toList();

        if (pending.isEmpty) {
          return const _AdminEmptyState(
            icon: Icons.delete_sweep_outlined,
            title: 'No pending deletion requests',
            subtitle: 'Users who request account deletion will appear here.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: pending.length,
          separatorBuilder: (_, i) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final r = pending[i];
            final uid = r['uid'] as String;
            final reason = r['reason'] as String?;
            final requestedAt = r['requestedAt'];
            DateTime? date;
            if (requestedAt is Timestamp) date = requestedAt.toDate();

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person_remove_outlined,
                        size: 18,
                        color: context.colors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          uid,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (date != null)
                        Text(
                          DateFormat('d MMM yyyy').format(date),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textTertiary,
                            fontFamily: 'Inter',
                          ),
                        ),
                    ],
                  ),
                  if (reason != null && reason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Reason: $reason',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _processing[uid] == true
                          ? null
                          : () => _markResolved(uid),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.colors.accent,
                        side: BorderSide(color: context.colors.accent),
                      ),
                      child: _processing[uid] == true
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Mark Resolved'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Activity tab — streams top-level admin_audit_logs collection
// ---------------------------------------------------------------------------

// Audit Logs — previously the one admin section that bypassed AdminPalette
// entirely (raw Theme.of(context).colorScheme + default ListTile styling),
// so it visually read as a different app from the rest of admin even
// though it did technically respond to the theme toggle. Rebuilt to match
// every other section's card/list language.
class _ActivityTab extends ConsumerWidget {
  const _ActivityTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AdminPalette.of(ref.watch(themeProvider));
    final svc = AdminAuditService(FirebaseFirestore.instance);
    return StreamBuilder<List<AdminAuditLogModel>>(
      stream: svc.watchAll(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Error: ${snap.error}',
                  style: TextStyle(
                      fontFamily: 'Inter', color: palette.textPrimary)),
            ),
          );
        }
        final logs = snap.data ?? [];
        if (logs.isEmpty) {
          return const _AdminEmptyState(
            icon: Icons.history_rounded,
            title: 'No admin actions recorded yet.',
          );
        }
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: palette.cardDecoration(),
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: logs.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: palette.border),
            itemBuilder: (context, i) {
              final log = logs[i];
              final color = _auditColor(log.action, palette);
              return ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(_auditIcon(log.action), size: 16, color: color),
                ),
                title: Text(
                  log.actionLabel,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Target: ${log.targetId} · ${log.targetType}',
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: palette.textSecondary),
                ),
                trailing: Text(
                  DateFormat('d MMM, HH:mm').format(log.timestamp.toLocal()),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: palette.textTertiary,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  static Color _auditColor(AdminAction action, AdminPalette palette) =>
      switch (action) {
        AdminAction.artisanApproved ||
        AdminAction.verificationApproved ||
        AdminAction.userReactivated =>
          AdminPalette.green,
        AdminAction.artisanRejected ||
        AdminAction.verificationRejected ||
        AdminAction.userSuspended ||
        AdminAction.userDeleted ||
        AdminAction.jobDeleted =>
          AdminPalette.red,
        AdminAction.jobCancelled => AdminPalette.amber,
        AdminAction.disputeResolved => AdminPalette.blue,
        _ => palette.textTertiary,
      };

  static IconData _auditIcon(AdminAction action) => switch (action) {
        AdminAction.artisanApproved => Icons.check_circle_outline,
        AdminAction.artisanRejected => Icons.cancel_outlined,
        AdminAction.verificationApproved => Icons.verified_outlined,
        AdminAction.verificationRejected => Icons.gpp_bad_outlined,
        AdminAction.userSuspended => Icons.block_outlined,
        AdminAction.userReactivated => Icons.lock_open_outlined,
        AdminAction.userDeleted => Icons.person_remove_outlined,
        AdminAction.jobDeleted => Icons.delete_outline,
        AdminAction.jobCancelled => Icons.work_off_outlined,
        AdminAction.disputeResolved => Icons.gavel_rounded,
        AdminAction.adminLogin => Icons.login_outlined,
        AdminAction.adminOverride => Icons.admin_panel_settings_outlined,
        AdminAction.betaTesterChanged => Icons.science_outlined,
      };
}
