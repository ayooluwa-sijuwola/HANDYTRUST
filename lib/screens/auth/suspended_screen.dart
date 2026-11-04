import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

/// Shown instead of any app content when the signed-in account's
/// accountStatus is 'suspended'. Stage 5 (D9): the user can still open their
/// existing jobs (restricted mode, enforced server-side) — but cannot start
/// any new marketplace activity.
class SuspendedScreen extends ConsumerWidget {
  const SuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    final restricted = profile?.hasRestrictedSuspension ?? false;
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_rounded, size: 56, color: context.colors.error),
                const SizedBox(height: 16),
                Text(
                  'Account Suspended',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  restricted
                      ? "Your account has been suspended. You can still complete your existing jobs, but you can't post jobs, quote or take new bookings. Contact support if you believe this is a mistake."
                      : 'Your account is suspended pending review. Your existing jobs are paused and any payments stay protected in escrow. You can still view your jobs and take part in disputes. Contact support if you believe this is a mistake.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => context.go('/jobs'),
                  child: const Text('View My Existing Jobs'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
