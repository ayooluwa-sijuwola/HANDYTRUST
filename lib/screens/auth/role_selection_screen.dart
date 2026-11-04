import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_scaffold.dart';

/// Shown after login when the user holds BOTH customer and artisan roles.
/// Writes activeRole to Firestore and routes to /home — the router then
/// renders the correct dashboard based on activeRole.
class RoleSelectionScreen extends ConsumerStatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  String? _selected;
  bool _loading = false;

  Future<void> _confirm() async {
    if (_selected == null) return;
    final user = ref.read(currentUserProvider).asData?.value;
    if (user == null) return;

    setState(() => _loading = true);
    try {
      await ref
          .read(profileServiceProvider)
          .setActiveRole(user.uid, _selected!);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not switch role: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.asData?.value;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              const AuthBrandHeader(),
              const SizedBox(height: 40),
              Text(
                'How are you using\nHandyTrust today?',
                style: AppTextStyles.pageHeadline.copyWith(
                  fontSize: 28,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                user != null
                    ? 'Welcome back, ${user.displayUsername}. Choose your mode.'
                    : 'Choose your mode to continue.',
                style: AppTextStyles.pageSubtitle.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 40),
              _RoleTile(
                role: 'customer',
                title: 'Continue as Customer',
                subtitle: 'Post jobs, hire artisans, manage payments.',
                icon: Icons.home_repair_service_rounded,
                selected: _selected == 'customer',
                onTap: () => setState(() => _selected = 'customer'),
              ),
              const SizedBox(height: 16),
              _RoleTile(
                role: 'artisan',
                title: 'Continue as Artisan',
                subtitle: 'Browse open jobs, submit quotes, track earnings.',
                icon: Icons.construction_rounded,
                selected: _selected == 'artisan',
                onTap: () => setState(() => _selected = 'artisan'),
              ),
              const Spacer(),
              AuthButton(
                label: 'Continue',
                loading: _loading,
                onPressed: _selected == null ? null : _confirm,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final String role;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.role,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppAnimations.normal,
        curve: AppAnimations.defaultCurve,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.primary.withValues(alpha: isDark ? 0.12 : 0.07)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color:
                selected ? context.colors.primary : context.colors.border,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected ? AppShadows.button : null,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: selected
                    ? context.colors.primary.withValues(alpha: 0.15)
                    : context.colors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(
                icon,
                size: 26,
                color: selected
                    ? context.colors.primary
                    : context.colors.textSecondary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? context.colors.primary
                          : context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: AppAnimations.fast,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    selected ? context.colors.primary : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? context.colors.primary
                      : context.colors.border,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
