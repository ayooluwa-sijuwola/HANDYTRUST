import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/auth_service.dart';
import '../../core/validation/password_policy.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_kit.dart';
import '../theme/ht_theme.dart';

/// Stage 8.2 Settings (reached from Profile). Every row opens its own
/// destination; nothing routes back to this hub. Account writes go through
/// the existing services with their existing payloads.

// ─── Shared frame ───────────────────────────────────────────────────────────

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children, this.subtitle});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Scaffold(
      backgroundColor: p.background,
      body: HtBackground(
        glow: false,
        child: SafeArea(
          child: Column(children: [
            HtScreenHeader(title: title, subtitle: subtitle, onBack: () => context.canPop() ? context.pop() : context.go('/profile')),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 6, HtSpace.gutter, 32), children: children),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.label, required this.children});
  final String label;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(label.toUpperCase(), style: HtType.caps(p.textMuted))),
        HtCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: children)),
      ]),
    );
  }
}

Future<String?> _editTextSheet(BuildContext context, {required String title, required String label, required String initial, required String? Function(String) validate, String? help}) {
  final ctrl = TextEditingController(text: initial);
  final form = GlobalKey<FormState>();
  return htShowSheet<String>(context, builder: (ctx) {
    final p = ctx.ht;
    return Padding(
      padding: EdgeInsets.fromLTRB(HtSpace.gutter, 4, HtSpace.gutter, 20 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: HtType.sectionTitle(p.textPrimary)),
          if (help != null) ...[const SizedBox(height: 4), Text(help, style: HtType.small(p.textSecondary))],
          HtTextField(label: label, controller: ctrl, validator: (v) => validate(v ?? '')),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: HtSecondaryButton(label: 'Cancel', height: 48, onPressed: () => Navigator.of(ctx).pop())),
            const SizedBox(width: 10),
            Expanded(child: HtPrimaryButton(label: 'Save', height: 48, onPressed: () {
              if (form.currentState?.validate() ?? false) Navigator.of(ctx).pop(ctrl.text.trim());
            })),
          ]),
        ]),
      ),
    );
  });
}

String _authMessage(Object e) {
  if (e is! FirebaseAuthException) return 'Something went wrong. Please try again.';
  // Only the current password is checked on these forms.
  if (e.code == 'wrong-password' || e.code == 'invalid-credential') return 'Your current password is incorrect.';
  return AuthService.friendlyError(e);
}

// ─── Settings hub ───────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _requestDeletion(BuildContext context, WidgetRef ref, UserModel user) async {
    final reason = TextEditingController();
    final ok = await htShowSheet<bool>(context, builder: (ctx) {
      final p = ctx.ht;
      return Padding(
        padding: EdgeInsets.fromLTRB(HtSpace.gutter, 4, HtSpace.gutter, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Request account deletion', style: HtType.sectionTitle(p.textPrimary)),
          const SizedBox(height: 6),
          // U-1 wording: matches what the admin process actually does.
          Text('An administrator will review your request. Your job history, payments and reviews are kept.', style: HtType.body(p.textSecondary)),
          HtTextField(label: 'Reason (optional)', controller: reason, hint: 'e.g. I no longer use the app', lines: 2, maxLength: 300),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: HtSecondaryButton(label: 'Cancel', height: 48, onPressed: () => Navigator.of(ctx).pop(false))),
            const SizedBox(width: 10),
            Expanded(child: HtDangerButton(label: 'Submit request', onPressed: () => Navigator.of(ctx).pop(true))),
          ]),
        ]),
      );
    });
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(profileServiceProvider).requestAccountDeletion(user.uid, reason: reason.text);
      if (context.mounted) htSnack(context, 'Deletion request sent. An administrator will review it.');
    } catch (_) {
      if (context.mounted) htSnack(context, 'Could not send your request. Please try again.', error: true);
    }
  }

  Future<void> _cancelDeletion(BuildContext context, WidgetRef ref, UserModel user) async {
    final ok = await htConfirm(context, title: 'Cancel your deletion request?', message: 'Your account stays as it is.', confirmLabel: 'Cancel request');
    if (!ok || !context.mounted) return;
    try {
      await ref.read(profileServiceProvider).cancelDeletionRequest(user.uid);
      if (context.mounted) htSnack(context, 'Deletion request cancelled.');
    } catch (_) {
      if (context.mounted) htSnack(context, 'Could not cancel the request. Please try again.', error: true);
    }
  }

  Future<void> _switchMode(BuildContext context, WidgetRef ref, UserModel user) async {
    final toArtisan = user.activeRole != 'artisan';
    final ok = await htConfirm(
      context,
      title: toArtisan ? 'Switch to Artisan mode?' : 'Switch to Customer mode?',
      message: toArtisan ? 'You’ll see your artisan work: requests, jobs and earnings.' : 'You’ll see your customer bookings, payments and chats.',
      confirmLabel: 'Switch',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(profileServiceProvider).setActiveRole(user.uid, toArtisan ? 'artisan' : 'customer');
      if (context.mounted) context.go('/home');
    } catch (_) {
      if (context.mounted) htSnack(context, 'Could not switch mode. Please try again.', error: true);
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await htConfirm(context, title: 'Sign out of HandyTrust?', message: 'You can sign back in at any time.', confirmLabel: 'Sign out');
    if (!ok) return;
    await ref.read(authNotifierProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).asData?.value;
    final dark = ref.watch(themeProvider) == ThemeMode.dark;
    if (user == null) return const SettingsPage(title: 'Settings', children: [SizedBox(height: 80), HtLoadingView()]);
    final dual = user.hasBothRoles;
    return SettingsPage(
      title: 'Settings',
      children: [
        SettingsGroup(label: 'Account', children: [
          HtMenuRow(icon: Icons.badge_outlined, title: 'Personal information', subtitle: 'Name, username and email', onTap: () => context.push('/settings/personal')),
          HtMenuRow(icon: Icons.lock_outline_rounded, title: 'Security and password', subtitle: 'Change or reset your password', onTap: () => context.push('/settings/security')),
        ]),
        SettingsGroup(label: 'Preferences', children: [
          HtMenuRow(
            icon: Icons.notifications_none_rounded,
            title: 'Notification preferences',
            subtitle: user.notificationsEnabled ? 'Push notifications on' : 'Push notifications off',
            onTap: () => context.push('/settings/notifications'),
          ),
          HtMenuRow(
            icon: dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
            title: 'Dark mode',
            subtitle: dark ? 'On' : 'Off',
            showChevron: false,
            trailing: Switch(value: dark, onChanged: (_) => ref.read(themeProvider.notifier).toggle()),
            onTap: () => ref.read(themeProvider.notifier).toggle(),
          ),
          if (dual)
            HtMenuRow(
              icon: Icons.swap_horiz_rounded,
              title: 'Active mode',
              subtitle: user.activeRole == 'artisan' ? 'Artisan mode' : 'Customer mode',
              onTap: () => _switchMode(context, ref, user),
            ),
        ]),
        SettingsGroup(label: 'Help', children: [
          HtMenuRow(icon: Icons.support_agent_rounded, title: 'Support Centre', subtitle: 'Help topics and contact support', onTap: () => context.push('/support')),
          HtMenuRow(icon: Icons.info_outline_rounded, title: 'About HandyTrust', onTap: () => context.push('/about')),
        ]),
        SettingsGroup(label: 'Account actions', children: [
          if (user.accountDeletionRequested)
            HtMenuRow(icon: Icons.restore_rounded, title: 'Cancel deletion request', subtitle: 'Your request is waiting for review', onTap: () => _cancelDeletion(context, ref, user))
          else
            HtMenuRow(icon: Icons.delete_outline_rounded, title: 'Request account deletion', subtitle: 'Reviewed by an administrator', destructive: true, onTap: () => _requestDeletion(context, ref, user)),
          HtMenuRow(icon: Icons.logout_rounded, title: 'Sign out', destructive: true, showChevron: false, onTap: () => _signOut(context, ref)),
        ]),
      ],
    );
  }
}

// ─── Personal information ───────────────────────────────────────────────────

class PersonalInfoScreen extends ConsumerWidget {
  const PersonalInfoScreen({super.key});

  Future<void> _editName(BuildContext context, WidgetRef ref, UserModel user) async {
    final v = await _editTextSheet(context, title: 'Display name', label: 'Full name', initial: user.name,
        help: 'Shown to the people you work with.', validate: (s) => s.trim().length < 2 ? 'Enter at least 2 characters' : null);
    if (v == null || v == user.name || !context.mounted) return;
    try {
      await ref.read(profileServiceProvider).updateName(user.uid, v);
      if (context.mounted) htSnack(context, 'Name updated');
    } catch (_) {
      if (context.mounted) htSnack(context, 'Could not update your name. Please try again.', error: true);
    }
  }

  Future<void> _editUsername(BuildContext context, WidgetRef ref, UserModel user) async {
    final v = await _editTextSheet(context, title: 'Username', label: 'Username', initial: user.username ?? '',
        validate: (s) => s.trim().isEmpty ? 'Enter a username' : null);
    if (v == null || v == user.username || !context.mounted) return;
    try {
      await ref.read(profileServiceProvider).updateUsername(user.uid, v);
      if (context.mounted) htSnack(context, 'Username updated');
    } catch (_) {
      if (context.mounted) htSnack(context, 'Could not update your username. Please try again.', error: true);
    }
  }

  Future<void> _changeEmail(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    final pw = TextEditingController();
    final form = GlobalKey<FormState>();
    final done = await htShowSheet<bool>(context, builder: (ctx) {
      var busy = false;
      String? error;
      return StatefulBuilder(builder: (ctx, setState) {
        final p = ctx.ht;
        return Padding(
          padding: EdgeInsets.fromLTRB(HtSpace.gutter, 4, HtSpace.gutter, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Change email', style: HtType.sectionTitle(p.textPrimary)),
              const SizedBox(height: 4),
              Text('We’ll send a link to the new address. Your email changes once you open it.', style: HtType.small(p.textSecondary)),
              HtTextField(label: 'New email', controller: email, keyboard: TextInputType.emailAddress,
                  validator: (v) => RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z.]{2,}$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email'),
              _PasswordField(label: 'Current password', controller: pw, validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null),
              if (error != null) ...[const SizedBox(height: 8), Text(error!, style: HtType.small(p.danger))],
              const SizedBox(height: 14),
              HtPrimaryButton(
                label: 'Send verification link',
                loading: busy,
                onPressed: busy
                    ? null
                    : () async {
                        if (!(form.currentState?.validate() ?? false)) return;
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await ref.read(profileServiceProvider).updateEmail(currentPassword: pw.text, newEmail: email.text.trim());
                          if (ctx.mounted) Navigator.of(ctx).pop(true);
                        } catch (e) {
                          setState(() {
                            busy = false;
                            error = _authMessage(e);
                          });
                        }
                      },
              ),
            ]),
          ),
        );
      });
    });
    if (done == true && context.mounted) htSnack(context, 'Check ${email.text.trim()} for a verification link.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).asData?.value;
    if (user == null) return const SettingsPage(title: 'Personal information', children: [SizedBox(height: 80), HtLoadingView()]);
    return SettingsPage(
      title: 'Personal information',
      children: [
        SettingsGroup(label: 'Profile', children: [
          HtMenuRow(icon: Icons.person_outline_rounded, title: 'Display name', subtitle: user.name, onTap: () => _editName(context, ref, user)),
          HtMenuRow(icon: Icons.alternate_email_rounded, title: 'Username', subtitle: (user.username?.isNotEmpty ?? false) ? '@${user.username}' : 'Not set', onTap: () => _editUsername(context, ref, user)),
        ]),
        SettingsGroup(label: 'Contact', children: [
          HtMenuRow(icon: Icons.mail_outline_rounded, title: 'Email', subtitle: user.email ?? 'Not set', onTap: () => _changeEmail(context, ref)),
          if (user.phoneNumber?.isNotEmpty ?? false) HtMenuRow(icon: Icons.phone_outlined, title: 'Phone', subtitle: user.phoneNumber, showChevron: false),
        ]),
        const SizedBox(height: 14),
        const HtInfoBanner(icon: Icons.photo_camera_outlined, tone: HtTone.neutral, text: 'Change your profile photo from your Profile page.'),
      ],
    );
  }
}

// ─── Notification preferences ───────────────────────────────────────────────

class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});
  @override
  ConsumerState<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends ConsumerState<NotificationPreferencesScreen> {
  bool _saving = false;

  Future<void> _set(UserModel user, bool v) async {
    setState(() => _saving = true);
    try {
      // Same write as before (users/{uid}.notificationsEnabled). The push
      // layer reacts to it: off → this device's push registration is
      // removed; on → it registers again (notification_provider.dart).
      await ref.read(authServiceProvider).updateUserProfile(user.uid, {'notificationsEnabled': v});
      if (mounted) htSnack(context, v ? 'Push notifications turned on' : 'Push notifications turned off');
    } catch (_) {
      if (mounted) htSnack(context, 'Could not save your preference. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).asData?.value;
    if (user == null) return const SettingsPage(title: 'Notification preferences', children: [SizedBox(height: 80), HtLoadingView()]);
    return SettingsPage(
      title: 'Notification preferences',
      children: [
        const SizedBox(height: 8),
        HtCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: HtToggleRow(
            icon: Icons.notifications_active_outlined,
            title: 'Push notifications',
            subtitle: 'Bookings, payments, disputes and new messages on this account’s devices',
            value: user.notificationsEnabled,
            busy: _saving,
            onChanged: (v) => _set(user, v),
          ),
        ),
        const SizedBox(height: 14),
        const HtInfoBanner(
          icon: Icons.inbox_outlined,
          tone: HtTone.neutral,
          text: 'Updates are always kept in your in-app notifications, whichever you choose here.',
        ),
        const SizedBox(height: 10),
        HtCard(
          onTap: () => context.push('/notifications'),
          child: Row(children: [
            htIconTile(context, Icons.notifications_none_rounded),
            const SizedBox(width: 12),
            Expanded(child: Text('Open notifications', style: HtType.bodyStrong(context.ht.textPrimary))),
            Icon(Icons.chevron_right_rounded, color: context.ht.textMuted),
          ]),
        ),
      ],
    );
  }
}

// ─── Security and password ──────────────────────────────────────────────────

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});
  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _sendingReset = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Re-authenticates with the current password, then updates it.
      await ref.read(profileServiceProvider).updatePassword(currentPassword: _current.text, newPassword: _next.text);
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _confirm.clear();
      htSnack(context, 'Password changed');
    } catch (e) {
      if (mounted) setState(() => _error = _authMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendReset(String email) async {
    setState(() => _sendingReset = true);
    try {
      // The existing Firebase-hosted recovery flow (Q-2).
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (mounted) htSnack(context, 'We sent a password reset link to $email.');
    } catch (e) {
      if (mounted) htSnack(context, _authMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final email = ref.watch(currentUserProvider).asData?.value?.email ?? ref.watch(authStateChangesProvider).asData?.value?.email;
    return SettingsPage(
      title: 'Security and password',
      children: [
        const SizedBox(height: 8),
        if (email != null) HtInfoBanner(icon: Icons.verified_user_outlined, tone: HtTone.neutral, text: 'Signed in with email and password as $email.'),
        SettingsGroup(label: 'Change password', children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _PasswordField(label: 'Current password', controller: _current, validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null),
                _PasswordField(label: 'New password', controller: _next, validator: PasswordPolicy.validate, onChanged: (_) => setState(() {})),
                const SizedBox(height: 8),
                for (final (rule, met) in PasswordPolicy.checklist(_next.text))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(children: [
                      Icon(met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 15, color: met ? p.success : p.textMuted),
                      const SizedBox(width: 6),
                      Text(rule, style: HtType.small(met ? p.textPrimary : p.textMuted)),
                    ]),
                  ),
                _PasswordField(
                  label: 'Confirm new password',
                  controller: _confirm,
                  validator: (v) => v != _next.text ? 'Passwords don’t match' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Semantics(liveRegion: true, child: Text(_error!, style: HtType.small(p.danger))),
                ],
                const SizedBox(height: 14),
                HtPrimaryButton(label: 'Update password', loading: _busy, onPressed: _busy ? null : _change),
              ]),
            ),
          ),
        ]),
        SettingsGroup(label: 'Forgot your password?', children: [
          HtMenuRow(
            icon: Icons.mark_email_read_outlined,
            title: 'Email me a reset link',
            subtitle: email == null ? 'No email on this account' : 'Sent to $email',
            trailing: _sendingReset ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)) : null,
            onTap: email == null || _sendingReset ? null : () => _sendReset(email),
          ),
        ]),
      ],
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.label, required this.controller, this.validator, this.onChanged});
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HtFieldLabel(widget.label),
      TextFormField(
        controller: widget.controller,
        obscureText: _hidden,
        autocorrect: false,
        enableSuggestions: false,
        style: HtType.body(p.textPrimary),
        validator: widget.validator,
        onChanged: widget.onChanged,
        decoration: htInputDecoration(
          context,
          suffix: IconButton(
            tooltip: _hidden ? 'Show password' : 'Hide password',
            icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: p.textMuted),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
      ),
    ]);
  }
}
