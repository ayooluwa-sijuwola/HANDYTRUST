import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_scaffold.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  Timer? _pollTimer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Poll Firebase every 4 seconds to detect email verification
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkVerified());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkVerified() async {
    if (_checking) return;
    _checking = true;
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      // No manual navigation here. authStateChangesProvider is backed by
      // userChanges() (see AuthService.authStateChanges), which emits after
      // reload() — so this triggers AuthChangeNotifier, which triggers the
      // router's refreshListenable, which re-runs redirect and sends a
      // verified user from /verify-email to /home on its own. GoRouter's
      // redirect is the single source of truth for navigation; this screen
      // only needs to confirm verification, not decide where to go.
    } finally {
      _checking = false;
    }
  }

  Future<void> _resend() async {
    await ref.read(authNotifierProvider.notifier).resendVerificationEmail();
    if (!mounted) return;
    // resendVerificationEmail() sets authNotifierProvider's isLoading/error
    // itself (same pattern as signIn/signUp) — read the real outcome here
    // instead of assuming success, so a failure isn't reported as "sent."
    final error = ref.read(authNotifierProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Verification email sent. Check your inbox.'),
        backgroundColor: error != null ? context.colors.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    final resending = ref.watch(authNotifierProvider).isLoading;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: AuthWebLayout(
          child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AuthBrandHeader(),
              const SizedBox(height: 28),
              AuthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.mark_email_unread_outlined, size: 64, color: context.colors.primary),
                    const SizedBox(height: 20),
                    Text(
                      'Verify your email',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: context.colors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We sent a verification link to\n$email\n\nOpen your email and tap the link to activate your account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colors.textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    AuthButton(
                      label: 'Resend verification email',
                      loading: resending,
                      onPressed: _resend,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _checkVerified,
                      child: const Text("I've verified — continue"),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () async {
                        await ref.read(authNotifierProvider.notifier).signOut();
                        // Router redirect handles navigation after signOut
                      },
                      child: Text(
                        'Use a different account',
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const AuthFooter(),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
