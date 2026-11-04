import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/startup_error_screen.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);
    debugPrint('[SplashScreen] build authState=$authState');

    // SplashScreen is shown while determining auth state
    // Once auth state is known, router will redirect to /login or /home
    final brandMark = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: context.colors.primary),
        const SizedBox(height: 20),
        Text(
          'HandyTrust',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: context.colors.primary,
            fontFamily: 'Inter',
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: authState.when(
          data: (_) => brandMark,
          loading: () => brandMark,
          // In practice this branch is now rarely reached — the app-level
          // _AuthResolutionGate (main.dart) already catches a stuck/failed
          // initial auth resolution before the router ever mounts. Kept as
          // a defense-in-depth fallback for a LATER auth-stream error (e.g.
          // a dropped connection after a successful initial resolution),
          // and fixed to never render the raw error object per this app's
          // error-handling standard.
          error: (error, _) {
            debugPrint('[SplashScreen] authState error: $error');
            return StartupErrorScreen(
              onRetry: () => ref.invalidate(authStateChangesProvider),
            );
          },
        ),
      ),
    );
  }
}
