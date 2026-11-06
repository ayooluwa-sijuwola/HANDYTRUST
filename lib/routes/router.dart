import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';
import '../ui/screens/artisan_profile_screen.dart';
import '../ui/artisan/artisan_shell.dart';
import '../ui/artisan/screens/artisan_inbox_screens.dart';
import '../ui/artisan/screens/artisan_registration_screen.dart';
import '../ui/artisan/screens/artisan_verification_screen.dart';
import '../ui/artisan/screens/business_profile_screen.dart';
import '../ui/artisan/screens/payout_account_screen.dart';
import '../ui/artisan/screens/portfolio_screen.dart';
import '../ui/artisan/screens/submit_work_screen.dart';
import '../ui/artisan/screens/work_order_screen.dart';
import '../models/job_model.dart';
import '../providers/escrow_provider.dart';
import '../ui/components/ht_components.dart';
import '../ui/screens/bookings_screen.dart';
import '../ui/screens/chat_screen.dart';
import '../ui/screens/confirm_pay_screen.dart';
import '../ui/screens/discovery_screen.dart';
import '../ui/screens/notifications_screen.dart';
import '../ui/screens/onboarding_screen.dart';
import '../ui/screens/payments_screen.dart';
import '../ui/screens/post_job_screen.dart';
import '../ui/screens/profile_screen.dart';
import '../ui/screens/verification_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/verify_email_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/artisan/artisan_list_screen.dart';
import '../screens/artisan/secure_booking_screen.dart';
import '../screens/artisan/favorites_screen.dart';
import '../screens/payment/payment_webview_screen.dart';
import '../screens/job/job_detail_screen.dart';
import '../screens/review/review_screen.dart';
import '../screens/dispute/dispute_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../ui/admin/admin_finance_compliance.dart';
import '../ui/admin/admin_operations.dart';
import '../ui/admin/admin_overview.dart';
import '../ui/admin/admin_people.dart';
import '../ui/admin/admin_shell.dart';
import '../models/portfolio_project_model.dart';
import '../widgets/cannot_open_directly_screen.dart';
import '../ui/screens/messages_screen.dart';
import '../ui/settings/help_screens.dart';
import '../ui/settings/settings_screens.dart';
import '../core/firebase/emulator_config.dart';
import '../ui/staging/media_staging_screen.dart';
import '../screens/auth/suspended_screen.dart';
import '../screens/auth/role_selection_screen.dart';

class AuthChangeNotifier extends ChangeNotifier {
  AuthChangeNotifier(Ref ref) {
    ref.listen<AsyncValue<User?>>(
      authStateChangesProvider,
      (previous, next) => notifyListeners(),
      fireImmediately: true,
    );
    // Also re-run the redirect when the profile doc changes (e.g. an admin
    // suspends the account live) so SuspendedScreen kicks in immediately.
    ref.listen(
      currentUserProfileProvider,
      (previous, next) => notifyListeners(),
    );
    // Re-run once isAdminProvider settles — without this, a non-admin who
    // lands on /admin/* while the admin-doc lookup is still in flight would
    // stay there until some unrelated navigation re-triggered the guard.
    ref.listen(
      isAdminProvider,
      (previous, next) => notifyListeners(),
    );
    // Stage 8: signed-out first-run users see onboarding once.
    ref.listen<bool?>(
      onboardingSeenProvider,
      (previous, next) => notifyListeners(),
    );
  }
}

String _paramOrEmpty(GoRouterState state, String key) {
  final val = state.pathParameters[key];
  if (val == null) {
    debugPrint('[router] missing path parameter "$key" in ${state.uri.path}');
    return '';
  }
  return val;
}

final authChangeNotifierProvider =
    Provider<AuthChangeNotifier>((ref) => AuthChangeNotifier(ref));

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: ref.watch(authChangeNotifierProvider),
    redirect: (context, state) {
      final authAsync = ref.watch(authStateChangesProvider);

      if (authAsync.isLoading) return null;

      final firebaseUser = authAsync.asData?.value;
      final path = state.uri.path;

      // Strip any anonymous/demo sessions — treat them as signed-out
      final isRealUser = firebaseUser != null && !firebaseUser.isAnonymous;

      const publicPaths = {'/login', '/register', '/register/artisan', '/forgot-password', '/onboarding'};
      final isPublic = publicPaths.any((p) => path == p || path.startsWith('$p/'));

      if (!isRealUser) {
        // The isLoading guard above already keeps splash ('/') showing
        // while Firebase resolves. Once auth state is known — including
        // "definitely signed out" — every non-public path, '/' included,
        // must redirect to /login. (Previously '/' was special-cased to
        // never redirect, which parked signed-out users on splash forever.)
        if (!isPublic) {
          // First launch shows onboarding once. While the local flag is still
          // loading, the splash route waits (the guard re-runs when it loads);
          // any other protected path goes straight to sign-in.
          final seen = ref.read(onboardingSeenProvider);
          if (seen == null) return path == '/' ? null : '/login';
          return seen ? '/login' : '/onboarding';
        }
        return null;
      }

      // Authenticated but email not verified → gate on verify screen
      if (!firebaseUser.emailVerified && path != '/verify-email') {
        return '/verify-email';
      }

      // Verified user trying to access auth screens → send home
      // Exception: /register/artisan is the artisan step-2 onboarding form —
      // verified artisan users may still need to complete it.
      if (firebaseUser.emailVerified &&
          (path == '/login' ||
              path == '/' ||
              path == '/verify-email' ||
              path == '/onboarding' ||
              path == '/register')) {
        return '/home';
      }

      // Suspended accounts are locked out of the entire app except the
      // suspended screen itself (which only offers sign-out).
      final profile = ref.watch(currentUserProfileProvider).asData?.value;
      // Stage 5 (D9) restricted existing-jobs mode: a suspended user may
      // still reach their EXISTING jobs, disputes, notifications and support —
      // never anything that starts new marketplace activity (posting, quoting,
      // browsing/booking artisans). Administrative/verification suspensions
      // may also chat and pay for an existing job; fraud/safety/security (or
      // unclassified) suspensions are view + dispute only. The server
      // enforces all of this regardless (firestore.rules + Cloud Functions);
      // this only keeps the UI consistent with it.
      if (profile != null && profile.isSuspended && path != '/suspended') {
        const viewPrefixes = ['/jobs', '/job/', '/dispute/', '/notifications', '/support'];
        const restrictedExtra = ['/chat/', '/payment/'];
        final allowed = viewPrefixes.any(path.startsWith) ||
            (profile.hasRestrictedSuspension && restrictedExtra.any(path.startsWith));
        if (!allowed) return '/suspended';
      }
      if ((profile == null || !profile.isSuspended) && path == '/suspended') {
        return '/home';
      }

      // Admin route guard — every /admin/* path requires a doc at
      // /admins/{uid} (mirrors the Firestore rules' isAdmin() check).
      // While isAdminProvider is still resolving, let the navigation
      // through rather than bouncing to /home — AdminDashboardScreen shows
      // its own loading spinner and re-checks the same provider, so a
      // genuine non-admin is still blocked the instant it resolves false.
      if (path.startsWith('/admin')) {
        final isAdminAsync = ref.watch(isAdminProvider);
        if (!isAdminAsync.isLoading && !(isAdminAsync.asData?.value ?? false)) {
          return '/home';
        }
      }

      // Stage 8.1 (D-6): artisan-only screens redirect non-artisans home.
      // A UI convenience only — firestore.rules and Cloud Functions enforce
      // every artisan write independently of navigation.
      if (profile != null && !profile.isArtisan && _artisanOnly(path)) {
        return '/home';
      }

      // Dual-role users arriving at /home for the first time are sent to the
      // role selection screen so they explicitly choose their mode. Once they
      // pick a role, activeRole is persisted and they go straight to /home on
      // subsequent logins. Users navigating from within the app (switching
      // roles via profile screen) are allowed through directly.
      if (profile != null &&
          profile.hasBothRoles &&
          path == '/home' &&
          !const {'/role-select'}.contains(path)) {
        // If activeRole is already set to a valid role, no interstitial needed.
        final hasExplicitRole =
            profile.activeRole == 'customer' || profile.activeRole == 'artisan';
        if (!hasExplicitRole) return '/role-select';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (context, _) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (context, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, _) => const RegisterScreen()),
      GoRoute(path: '/register/artisan', builder: (context, _) => const ArtisanRegistrationScreen()),
      GoRoute(path: '/verify-email', builder: (context, _) => const VerifyEmailScreen()),
      GoRoute(path: '/forgot-password', builder: (context, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/suspended', builder: (context, _) => const SuspendedScreen()),
      GoRoute(path: '/role-select', builder: (context, _) => const RoleSelectionScreen()),
      // Stage 8.2: Support Centre and About (both reachable while suspended
      // via the redirect's /support allow-list for Support).
      GoRoute(path: '/support', builder: (context, _) => const SupportCentreScreen()),
      GoRoute(path: '/about', builder: (context, _) => const AboutHandyTrustScreen()),
      // Stage 8.2 Settings (reached from Profile); every option has its own
      // destination.
      GoRoute(
        path: '/settings',
        builder: (context, _) => const SettingsScreen(),
        routes: [
          GoRoute(path: 'personal', builder: (context, _) => const PersonalInfoScreen()),
          GoRoute(path: 'notifications', builder: (context, _) => const NotificationPreferencesScreen()),
          GoRoute(path: 'security', builder: (context, _) => const SecurityScreen()),
        ],
      ),
      // RumptyCloud staging media test — registered ONLY in local emulator
      // mode (never in normal or release builds).
      if (EmulatorConfig.enabled) GoRoute(path: '/staging/media', builder: (context, _) => const MediaStagingScreen()),
      // Customers: escrow payments summary (Stage 8). Artisans: Earnings tab
      // of the artisan shell (Stage 8.1).
      GoRoute(
        path: '/wallet',
        builder: (context, _) => const _RoleAware(
          customer: Scaffold(body: PaymentsScreen()),
          artisan: ArtisanShell(initialTab: ArtisanTab.earnings),
        ),
      ),

      GoRoute(path: '/home', builder: (context, _) => const HomeScreen()),
      GoRoute(
        path: '/jobs',
        builder: (context, _) => const _RoleAware(
          customer: Scaffold(body: BookingsScreen()),
          artisan: ArtisanShell(initialTab: ArtisanTab.myJobs),
        ),
      ),
      GoRoute(path: '/notifications', builder: (context, _) => const _RoleAware(customer: NotificationsScreen(), artisan: ArtisanNotificationsScreen())),
      GoRoute(
        path: '/request',
        builder: (_, state) => PostJobScreen(
          initialCategory: state.uri.queryParameters['category'],
        ),
      ),

      // Artisan browse (public, no job required)
      GoRoute(
        path: '/browse-artisans',
        // Superseded by Discovery (Stage 8); kept as a path for old links.
        builder: (_, _) => const Scaffold(body: DiscoveryScreen()),
      ),

      // Saved artisans (customer favorites)
      GoRoute(
        path: '/favorites',
        builder: (_, _) => const FavoritesScreen(),
      ),

      // Artisan discovery
      GoRoute(
        path: '/artisans/:jobId',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ArtisanListScreen(
            jobId: _paramOrEmpty(state, 'jobId'),
            category: extra['category'] as String? ?? '',
            customerLat: extra['lat'] as double?,
            customerLng: extra['lng'] as double?,
          );
        },
      ),
      GoRoute(
        path: '/artisan/:uid',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ArtisanProfileScreen(
            artisanId: _paramOrEmpty(state, 'uid'),
            jobId: extra['jobId'] as String?,
          );
        },
      ),

      // Secure Booking wizard — direct-hire entry point for a specific
      // artisan browsed without an existing job context. artisanId is a
      // path param (not `extra:`), so this survives a Flutter Web refresh.
      GoRoute(
        path: '/secure-booking/:artisanId',
        builder: (_, state) => SecureBookingRoute(
          artisanId: _paramOrEmpty(state, 'artisanId'),
        ),
      ),

      // Chat
      GoRoute(
        path: '/chat/:jobId',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ChatScreen(
            jobId: _paramOrEmpty(state, 'jobId'),
            // Stage 8.2: `?with=` names the other participant so a link can
            // open one specific conversation without route extras.
            otherUserId: extra['artisanId'] as String? ?? state.uri.queryParameters['with'] ?? '',
            otherUserName: extra['artisanName'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/my-chats',
        builder: (_, _) => const _RoleAware(customer: CustomerMessagesScreen(), artisan: ArtisanMessagesScreen()),
      ),

      // Payment
      GoRoute(
        path: '/payment/:jobId',
        builder: (_, state) => ConfirmPayScreen(jobId: _paramOrEmpty(state, 'jobId')),
      ),
      GoRoute(
        path: '/payment/:jobId/webview',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PaymentWebviewScreen(
            jobId: _paramOrEmpty(state, 'jobId'),
            url: extra['url'] as String? ?? '',
            reference: extra['reference'] as String? ?? '',
          );
        },
      ),

      // Job lifecycle
      GoRoute(
        path: '/job/:jobId',
        builder: (_, state) => _JobRoute(jobId: _paramOrEmpty(state, 'jobId')),
      ),
      GoRoute(
        path: '/job/:jobId/submit',
        builder: (_, state) => SubmitWorkScreen(jobId: _paramOrEmpty(state, 'jobId')),
      ),

      // Review & dispute
      GoRoute(
        path: '/review/:jobId',
        builder: (_, state) => ReviewScreen(jobId: _paramOrEmpty(state, 'jobId')),
      ),
      GoRoute(
        path: '/dispute/:jobId',
        builder: (_, state) => DisputeScreen(jobId: _paramOrEmpty(state, 'jobId')),
      ),

      // Admin platform — ShellRoute keeps the sidebar + top-bar (AdminShell)
      // alive across all /admin/* navigations. Only the section content is
      // swapped when the user clicks a sidebar item, so:
      //   • The isAdmin gate runs once, not on every nav click.
      //   • The sidebar never unmounts — no loading-spinner flash.
      //   • Deep-linking and browser back/forward still work because each
      //     section has its own URL.
      // '/admin' itself redirects to /admin/dashboard.
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/admin',
            redirect: (_, _) => AdminSection.dashboard.path,
          ),
          for (final section in AdminSection.values)
            GoRoute(path: section.path, builder: (_, _) => _adminSection(section)),
        ],
      ),
      GoRoute(
        path: '/verification',
        builder: (context, _) => const _RoleAware(customer: VerificationScreen(), artisan: ArtisanVerificationScreen()),
      ),
      GoRoute(
        path: '/bank-details',
        builder: (context, _) => const PayoutAccountScreen(),
      ),
      GoRoute(
        path: '/business-profile',
        builder: (context, _) => const BusinessProfileScreen(),
      ),
      GoRoute(
        path: '/portfolio',
        builder: (context, _) => const PortfolioScreen(),
      ),
      GoRoute(
        path: '/portfolio-project',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          // P0 remediation (design/P0_REMEDIATION_PLAN.md §5): artisanId
          // previously had a non-nullable cast here with no fallback —
          // state.extra is null on any direct/refreshed Flutter Web
          // navigation (this route's payload only ever arrives via an
          // in-app context.push(..., extra: {...})), which crashed the app
          // with `type 'Null' is not a subtype of type 'String'`. Both real
          // call sites (the Portfolio screen's create and edit)
          // always supply artisanId, so this null-safe branch only ever
          // triggers on direct/refreshed navigation, never on the real flow.
          final artisanId = extra['artisanId'] as String?;
          if (artisanId == null) {
            return const CannotOpenDirectlyScreen(returnPath: '/portfolio');
          }
          return PortfolioProjectScreen(
            artisanId: artisanId,
            existing: extra['existing'] as PortfolioProjectModel?,
          );
        },
      ),
      GoRoute(
        path: '/open-jobs',
        // Find Work tab of the artisan shell (category comes from the
        // artisan's own profile; customers are redirected by D-6).
        builder: (context, state) => const ArtisanShell(initialTab: ArtisanTab.findWork),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const _RoleAware(
          customer: Scaffold(body: ProfileScreen(standalone: true)),
          artisan: ArtisanShell(initialTab: ArtisanTab.profile),
        ),
      ),
    ],
  );
});

/// Stage 8.1 (D-6): artisan-only paths. `/register/artisan` is deliberately
/// absent — it is how a customer becomes an artisan.
bool _artisanOnly(String path) =>
    path == '/open-jobs' ||
    path == '/bank-details' ||
    path == '/business-profile' ||
    path == '/portfolio' ||
    path == '/portfolio-project' ||
    (path.startsWith('/job/') && path.endsWith('/submit'));

/// `/job/:jobId`: the job's own artisan gets the artisan work order
/// (Stage 8.1); everyone else gets the customer job detail.
class _JobRoute extends ConsumerWidget {
  const _JobRoute({required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateChangesProvider).asData?.value?.uid;
    final jobAsync = ref.watch(jobStreamProvider(jobId));
    if (uid == null || jobAsync.isLoading && !jobAsync.hasValue) {
      return const Scaffold(body: HtLoadingView());
    }
    final JobModel? job = jobAsync.asData?.value;
    if (job != null && job.artisanId.isNotEmpty && job.artisanId == uid) {
      return WorkOrderScreen(job: job);
    }
    return JobDetailScreen(jobId: jobId);
  }
}

/// Stage 8: picks the customer or artisan screen for a path shared by both
/// roles, from the signed-in profile's active role (F-11 rule).
class _RoleAware extends ConsumerWidget {
  const _RoleAware({required this.customer, required this.artisan});
  final Widget customer;
  final Widget artisan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProfileProvider).asData?.value;
    final artisanMode = user != null && user.isArtisan && user.activeRole == 'artisan';
    return artisanMode ? artisan : customer;
  }
}

/// Stage 8.2 admin sections (rebuilt presentation in lib/ui/admin).
Widget _adminSection(AdminSection s) => switch (s) {
      AdminSection.dashboard => const AdminDashboardSection(),
      AdminSection.analytics => const AdminAnalyticsSection(),
      AdminSection.users => const AdminUsersSection(),
      AdminSection.artisans => const AdminArtisansSection(),
      AdminSection.verifications => const AdminVerificationsSection(),
      AdminSection.jobs => const AdminJobsSection(),
      AdminSection.disputes => const AdminDisputesSection(),
      AdminSection.support => const AdminSupportSection(),
      AdminSection.reviews => const AdminReviewsSection(),
      AdminSection.deletions => const AdminDeletionsSection(),
      AdminSection.finance => const AdminFinanceSection(),
      AdminSection.auditLogs => const AdminAuditLogsSection(),
      AdminSection.settings => const AdminSettingsSection(),
    };
