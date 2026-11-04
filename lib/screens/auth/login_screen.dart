import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(authNotifierProvider.notifier).signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    if (!ok && mounted) {
      final err = ref.read(authNotifierProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Sign-in failed.'), backgroundColor: context.colors.error),
      );
    }
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
              const AuthBrandHeader(),
              const SizedBox(height: 28),
              AuthCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: AuthLogoBadge(size: 64)),
                      const SizedBox(height: 20),
                      Text(
                        'Welcome Back',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: context.colors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your details to access your account',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: context.colors.textSecondary),
                      ),
                      const SizedBox(height: 32),

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
                        label: 'Password',
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        hintText: '••••••••',
                        prefixIcon: Icons.lock_outline,
                        autofillHints: const [AutofillHints.password],
                        labelTrailing: TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => context.push('/forgot-password'),
                          child: const Text('Forgot Password?'),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Password is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      AuthButton(
                        label: 'Login to Account',
                        loading: authState.isLoading,
                        onPressed: _signIn,
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
                          Text(
                            "Don't have an account? ",
                            style: TextStyle(color: context.colors.textSecondary),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            onPressed: () => context.push('/register'),
                            child: const Text('Sign Up', style: TextStyle(fontWeight: FontWeight.w700)),
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
