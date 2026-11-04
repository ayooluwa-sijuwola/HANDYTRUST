import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/artisan_registration_screen.dart';
import '../screens/auth/verify_email_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/service_request_screen.dart';
import '../screens/artisan/artisan_list_screen.dart';
import '../screens/artisan/artisan_profile_screen.dart';
import '../screens/artisan/secure_booking_screen.dart';
import '../screens/artisan/browse_artisans_screen.dart';
import '../screens/artisan/favorites_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/chat/my_chats_screen.dart';
import '../screens/payment/demo_escrow_screen.dart';
import '../screens/payment/payment_screen.dart';
import '../screens/payment/payment_webview_screen.dart';
import '../screens/job/job_detail_screen.dart';
import '../screens/job/job_completion_screen.dart';
import '../screens/review/review_screen.dart';
import '../screens/dispute/dispute_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart'
    show AdminDashboardScreen, AdminShell;
import '../screens/admin/admin_sidebar.dart' show AdminSection;
import '../screens/home/all_jobs_screen.dart';
import '../screens/verification/verification_upload_screen.dart';
import '../screens/artisan/bank_details_screen.dart';
import '../screens/artisan/business_profile_screen.dart';
import '../screens/artisan/open_jobs_feed_screen.dart';
import '../screens/artisan/portfolio_manager_screen.dart';
import '../screens/artisan/portfolio_project_screen.dart';
import '../models/portfolio_project_model.dart';
import '../widgets/cannot_open_directly_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/support/contact_support_screen.dart';
import '../screens/support/about_screen.dart';
import '../screens/wallet/wallet_screen.dart';
import '../screens/auth/suspended_screen.dart';
import '../screens/auth/role_selection_screen.dart';
import '../screens/profile/profile_screen.dart';

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

      const publicPaths = {'/login', '/register', '/register/artisan', '/forgot-password'};
      final isPublic = publicPaths.any((p) => path == p || path.startsWith('$p/'));

      if (!isRealUser) {
        // The isLoading guard above already keeps splash ('/') showing
        // while Firebase resolves. Once auth state is known — including
        // "definitely signed out" — every non-public path, '/' included,
        // must redirect to /login. (Previously '/' was special-cased to
        // never redirect, which parked signed-out users on splash forever.)
        if (!isPublic) return '/login';
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
      GoRoute(path: '/login', builder: (context, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, _) => const RegisterScreen()),
      GoRoute(path: '/register/artisan', builder: (context, _) => const ArtisanRegistrationScreen()),
      GoRoute(path: '/verify-email', builder: (context, _) => const VerifyEmailScreen()),
      GoRoute(path: '/forgot-password', builder: (context, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/suspended', builder: (context, _) => const SuspendedScreen()),
      GoRoute(path: '/role-select', builder: (context, _) => const RoleSelectionScreen()),
      GoRoute(path: '/support', builder: (context, _) => const ContactSupportScreen()),
      GoRoute(path: '/about', builder: (context, _) => const AboutScreen()),
      GoRoute(path: '/settings', builder: (context, _) => const SettingsScreen()),
      GoRoute(path: '/wallet', builder: (context, _) => const WalletScreen()),

      GoRoute(path: '/home', builder: (context, _) => const HomeScreen()),
      GoRoute(path: '/jobs', builder: (context, _) => const AllJobsScreen()),
      GoRoute(path: '/notifications', builder: (context, _) => const NotificationsScreen()),
      GoRoute(
        path: '/request',
        builder: (_, state) => ServiceRequestScreen(
          initialCategory: state.uri.queryParameters['category'],
        ),
      ),

      // Artisan browse (public, no job required)
      GoRoute(
        path: '/browse-artisans',
        builder: (_, _) => const BrowseArtisansScreen(),
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
            otherUserId: extra['artisanId'] as String? ?? '',
            otherUserName: extra['artisanName'] as String? ?? 'Artisan',
          );
        },
      ),
      GoRoute(
        path: '/my-chats',
        builder: (_, _) => const MyChatsScreen(),
      ),

      // Payment
      GoRoute(
        path: '/payment/:jobId',
        builder: (_, state) => PaymentScreen(jobId: _paramOrEmpty(state, 'jobId')),
      ),
      GoRoute(
        path: '/demo-payment/:jobId',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return DemoEscrowScreen(
            jobId: _paramOrEmpty(state, 'jobId'),
            autoStart: extra['autoStart'] as bool? ?? false,
          );
        },
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
        builder: (_, state) => JobDetailScreen(jobId: _paramOrEmpty(state, 'jobId')),
      ),
      GoRoute(
        path: '/job/:jobId/submit',
        builder: (_, state) => JobCompletionScreen(jobId: _paramOrEmpty(state, 'jobId')),
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
          GoRoute(
            path: AdminSection.dashboard.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.dashboard),
          ),
          GoRoute(
            path: AdminSection.users.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.users),
          ),
          GoRoute(
            path: AdminSection.artisans.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.artisans),
          ),
          GoRoute(
            path: AdminSection.jobs.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.jobs),
          ),
          GoRoute(
            path: AdminSection.verifications.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.verifications),
          ),
          GoRoute(
            path: AdminSection.disputes.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.disputes),
          ),
          GoRoute(
            path: AdminSection.reviews.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.reviews),
          ),
          GoRoute(
            path: AdminSection.support.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.support),
          ),
          GoRoute(
            path: AdminSection.deletions.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.deletions),
          ),
          GoRoute(
            path: AdminSection.auditLogs.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.auditLogs),
          ),
          GoRoute(
            path: AdminSection.analytics.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.analytics),
          ),
          GoRoute(
            path: AdminSection.settings.path,
            builder: (_, _) =>
                const AdminDashboardScreen(section: AdminSection.settings),
          ),
        ],
      ),
      GoRoute(
        path: '/verification',
        builder: (context, _) => const VerificationUploadScreen(),
      ),
      GoRoute(
        path: '/bank-details',
        builder: (context, _) => const BankDetailsScreen(),
      ),
      GoRoute(
        path: '/business-profile',
        builder: (context, _) => const BusinessProfileScreen(),
      ),
      GoRoute(
        path: '/portfolio',
        builder: (context, _) => const PortfolioManagerScreen(),
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
          // call sites (portfolio_manager_screen.dart, create and edit)
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
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return OpenJobsFeedScreen(category: extra['category'] as String? ?? '');
        },
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: const ProfileTabContent(),
        ),
      ),
    ],
  );
});
