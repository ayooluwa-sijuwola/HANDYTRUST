import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/firebase/firebase_initializer.dart';
import 'firebase/messaging/local_notification_service.dart';
import 'providers/init_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/theme_provider.dart';
import 'routes/router.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/startup_error_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase must be fully initialized before any Firebase service is
  // touched. LocalNotificationService's constructor reads
  // FirebaseMessaging.instance and its init() calls
  // FirebaseMessaging.onBackgroundMessage — both throw [core/no-app] if
  // Firebase.initializeApp() hasn't completed yet.
  try {
    await initializeFirebase();
  } catch (e) {
    // Swallowed here — firebaseInitializationProvider retries this same
    // call inside the widget tree and surfaces the existing "Failed to
    // initialize the app" error screen if it fails again.
    debugPrint('[main] initial Firebase init failed, deferring to firebaseInitializationProvider: $e');
  }

  // Background FCM handler + local-notifications plugin setup. Must run
  // after Firebase is initialized, before runApp().
  try {
    await LocalNotificationService.instance.init();
  } catch (e) {
    debugPrint('[main] LocalNotificationService.init failed: $e');
  }

  runApp(const ProviderScope(child: HandyTrustApp()));
}

class HandyTrustApp extends ConsumerWidget {
  const HandyTrustApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initialization = ref.watch(firebaseInitializationProvider);

    return initialization.when(
      data: (_) => const _AuthResolutionGate(),
      loading: () => const MaterialApp(home: _InitializationScreen()),
      error: (error, stack) {
        debugPrint('[HandyTrustApp] Firebase initialization failed: $error');
        return MaterialApp(
          home: StartupErrorScreen(
            onRetry: () => ref.invalidate(firebaseInitializationProvider),
          ),
        );
      },
    );
  }
}

/// Second startup gate, after Firebase itself has initialized: waits for
/// the FIRST auth-state resolution (see authResolutionProvider's doc
/// comment for the exact failure mode this closes — the "infinite spinner
/// on Safari" root cause identified in
/// design/V2_IOS_SAFARI_RELIABILITY_REPORT.md).
class _AuthResolutionGate extends ConsumerWidget {
  const _AuthResolutionGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authResolution = ref.watch(authResolutionProvider);

    return authResolution.when(
      data: (_) => const _HandyTrustRouterApp(),
      loading: () => const MaterialApp(home: _InitializationScreen()),
      error: (error, stack) {
        debugPrint('[HandyTrustApp] auth-state resolution failed: $error');
        return MaterialApp(
          home: StartupErrorScreen(
            onRetry: () => ref.invalidate(authResolutionProvider),
          ),
        );
      },
    );
  }
}

class _HandyTrustRouterApp extends ConsumerWidget {
  const _HandyTrustRouterApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    ref.watch(notificationInitProvider);
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'HandyTrust',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

class _InitializationScreen extends StatelessWidget {
  const _InitializationScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.handyman_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  'HandyTrust',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFamily: 'Inter',
                    letterSpacing: -0.5,
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