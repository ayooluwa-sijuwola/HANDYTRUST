import '../../core/validation/password_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_scaffold.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _locationController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _selectedRole = 'customer';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final profile = UserModel(
      uid: '',
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      roles: [_selectedRole],
      activeRole: _selectedRole,
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
    );

    final ok = await ref.read(authNotifierProvider.notifier).signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          profile: profile,
        );

    if (!ok && mounted) {
      final err = ref.read(authNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Registration failed.'), backgroundColor: context.colors.error),
      );
    }
    // Router will redirect to /verify-email once Firebase user is created
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: AuthWebLayout(
          child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 4),
                  const AuthBrandHeader(),
                ],
              ),
              const SizedBox(height: 20),
              AuthCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Create Your Account',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: context.colors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Join HandyTrust — Nigeria's trusted service marketplace",
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: context.colors.textSecondary),
                      ),
                      const SizedBox(height: 28),

                      // Role selection
                      Row(
                        children: [
                          Expanded(child: _RoleTile(
                            label: 'I need services',
                            sublabel: 'Customer',
                            icon: Icons.person_search_outlined,
                            selected: _selectedRole == 'customer',
                            onTap: () => setState(() => _selectedRole = 'customer'),
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _RoleTile(
                            label: 'I offer services',
                            sublabel: 'Artisan',
                            icon: Icons.handyman_outlined,
                            selected: _selectedRole == 'artisan',
                            onTap: () => setState(() => _selectedRole = 'artisan'),
                          )),
                        ],
                      ),
                      const SizedBox(height: 24),

                      AuthTextField(
                        label: 'Full Name',
                        controller: _nameController,
                        hintText: 'Your full name',
                        prefixIcon: Icons.person_outline,
                        textCapitalization: TextCapitalization.words,
                        validator: (v) {
                          if (v == null || v.trim().length < 2) return 'Enter your full name';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      AuthTextField(
                        label: 'Email Address',
                        controller: _emailController,
                        hintText: 'name@company.com',
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Email is required';
                          final re = RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$');
                          if (!re.hasMatch(v.trim())) return 'Enter a valid email address';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      AuthTextField(
                        label: 'City / Area (optional)',
                        controller: _locationController,
                        hintText: 'e.g. Lekki, Lagos',
                        prefixIcon: Icons.location_on_outlined,
                      ),
                      const SizedBox(height: 20),

                      AuthTextField(
                        label: 'Password',
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        hintText: '••••••••',
                        prefixIcon: Icons.lock_outline,
                        autofillHints: const [AutofillHints.newPassword],
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        validator: (v) {
                          // Q-3: the shared policy for every new or changed password.
                          final problem = PasswordPolicy.validate(v);
                          if (problem != null) return problem;
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      AuthTextField(
                        label: 'Confirm Password',
                        controller: _confirmController,
                        obscureText: _obscureConfirm,
                        hintText: '••••••••',
                        prefixIcon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                        validator: (v) {
                          if (v != _passwordController.text) return 'Passwords do not match';
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      AuthButton(
                        label: 'Create Account',
                        loading: authState.isLoading,
                        onPressed: _register,
                        trailingIcon: Icons.arrow_forward_rounded,
                      ),
                      const SizedBox(height: 24),

                      const AuthDivider(),
                      const SizedBox(height: 20),
                      const SocialSignInRow(),
                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Already have an account? ',
                              style: TextStyle(color: context.colors.textSecondary)),
                          TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            onPressed: () => context.go('/login'),
                            child: const Text('Sign In', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ],
                  ),
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

class _RoleTile extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? context.colors.primary.withValues(alpha: 0.08) : context.colors.surfaceVariant,
          border: Border.all(
            color: selected ? context.colors.primary : context.colors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? context.colors.primary : context.colors.textSecondary, size: 28),
            const SizedBox(height: 6),
            Text(sublabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? context.colors.primary : context.colors.textPrimary,
                )),
            Text(label,
                style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
