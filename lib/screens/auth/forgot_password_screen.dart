import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_scaffold.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _sent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // P0 remediation (design/P0_REMEDIATION_PLAN.md §6.2 scenario f): the
    // "Send Reset Link" button already disables itself while _loading, but
    // onFieldSubmitted (Enter key) below was not gated the same way,
    // allowing a rapid double-submit that the button alone couldn't stop.
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // P0 remediation (design/P0_REMEDIATION_PLAN.md §6): sendPasswordReset
      // now returns whether it actually succeeded — previously this screen
      // set _sent = true unconditionally whenever the await didn't throw,
      // which was ALWAYS the case for a FirebaseAuthException, since the
      // notifier caught and stored it without rethrowing. The success
      // screen must only ever render after a real, confirmed send.
      final ok = await ref
          .read(authNotifierProvider.notifier)
          .sendPasswordReset(_emailCtrl.text.trim());
      if (!mounted) return;
      if (ok) {
        setState(() => _sent = true);
      } else {
        setState(() => _error = ref.read(authNotifierProvider).error);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                child: _sent ? _successState(context) : _formState(context),
              ),
              const AuthFooter(),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _formState(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reset Password',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            "Enter your email and we'll send a reset link.",
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: context.colors.textSecondary),
          ),
          const SizedBox(height: 28),

          AuthTextField(
            label: 'Email Address',
            controller: _emailCtrl,
            hintText: 'name@company.com',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter your email';
              if (!RegExp(r'^[\w.+\-]+@[\w\-]+\.\w+$').hasMatch(v.trim())) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                color: context.colors.error,
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
          ],
          const SizedBox(height: 24),

          AuthButton(
            label: 'Send Reset Link',
            loading: _loading,
            onPressed: _submit,
            trailingIcon: Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }

  Widget _successState(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 64, color: context.colors.primary),
        const SizedBox(height: 20),
        Text(
          'Check your inbox',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: context.colors.textPrimary,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          'We sent a password reset link to\n${_emailCtrl.text.trim()}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: context.colors.textSecondary,
            fontFamily: 'Inter',
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        OutlinedButton(
          onPressed: () => context.go('/login'),
          child: const Text('Back to Login'),
        ),
      ],
    );
  }
}
