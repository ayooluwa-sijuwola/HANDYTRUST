import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_snackbars.dart';
import '../../widgets/user_avatar.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.asData?.value;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
            fontFamily: 'Inter',
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.colors.textPrimary, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
        children: [
          // ── Profile card ────────────────────────────────────────────────
          if (user != null) ...[
            _ProfileCard(user: user),
            const SizedBox(height: 24),

            // ── Account ─────────────────────────────────────────────────
            _SectionLabel('Account'),
            _SettingsGroup(items: [
              _SettingsItem(
                icon: Icons.badge_outlined,
                label: 'Username',
                sublabel: user.username?.isNotEmpty == true
                    ? '@${user.username}'
                    : 'Not set — tap to add',
                onTap: () => _editUsername(context, ref, user.username ?? ''),
              ),
              _SettingsItem(
                icon: Icons.person_outline_rounded,
                label: 'Display Name',
                sublabel: user.name,
                onTap: () => _editName(context, ref, user.name),
              ),
              _SettingsItem(
                icon: Icons.email_outlined,
                label: 'Email',
                sublabel: user.email ?? 'Not set',
                onTap: () => _changeEmail(context, ref),
              ),
              _SettingsItem(
                icon: Icons.lock_outline_rounded,
                label: 'Change Password',
                onTap: () => _changePassword(context, ref),
              ),
            ]),
            const SizedBox(height: 20),

            // ── Role info ────────────────────────────────────────────────
            _SectionLabel('Role & Status'),
            _SettingsGroup(items: [
              _SettingsItem(
                icon: Icons.swap_horiz_rounded,
                label: 'Active Mode',
                sublabel: user.activeRole == 'artisan'
                    ? 'Artisan mode'
                    : 'Customer mode',
                onTap: user.hasBothRoles
                    ? () => _switchRole(context, ref, user)
                    : null,
                trailing: user.hasBothRoles
                    ? Icon(Icons.chevron_right_rounded,
                        color: context.colors.textTertiary)
                    : null,
              ),
              if (user.isArtisan)
                _SettingsItem(
                  icon: Icons.verified_outlined,
                  label: 'Verification',
                  sublabel: 'Upload ID & selfie',
                  onTap: () => context.push('/verification'),
                ),
            ]),
            const SizedBox(height: 20),
          ],

          // ── Appearance ──────────────────────────────────────────────────
          _SectionLabel('Appearance'),
          _SettingsGroup(items: [
            _SettingsToggleItem(
              icon: Icons.dark_mode_outlined,
              label: 'Dark Mode',
              sublabel: isDark ? 'On' : 'Off',
              value: isDark,
              onChanged: (_) => ref.read(themeProvider.notifier).toggle(),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Notifications ───────────────────────────────────────────────
          // Previously "Push Notifications" mis-routed to /notifications
          // (the inbox, not a preferences screen — a real bug, not just
          // unstyled). Replaced with the existing UserModel.notificationsEnabled
          // field, which already gates push display in
          // notification_provider.dart's startForegroundListener — this
          // toggle is genuinely functional today, not a placeholder.
          // Dispute-related notifications are intentionally NOT covered by
          // this toggle (08-messaging-notifications.md §5.1 — due-process
          // notifications shouldn't be user-suppressible); this field only
          // gates routine push display, which is consistent with that rule
          // since dispute pushes still create their in-app record either way.
          if (user != null) ...[
            _SectionLabel('Notifications'),
            _SettingsGroup(items: [
              _SettingsToggleItem(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                sublabel: user.notificationsEnabled ? 'On' : 'Off',
                value: user.notificationsEnabled,
                onChanged: (v) => ref
                    .read(authServiceProvider)
                    .updateUserProfile(user.uid, {'notificationsEnabled': v}),
              ),
            ]),
            const SizedBox(height: 20),
          ],

          // ── Artisan ─────────────────────────────────────────────────────
          if (user != null && user.isArtisan) ...[
            _SectionLabel('Artisan'),
            _SettingsGroup(items: [
              _SettingsItem(
                icon: Icons.account_balance_outlined,
                label: 'Payout Details',
                sublabel: 'Manage bank account',
                onTap: () => context.push('/bank-details'),
              ),
              _SettingsItem(
                icon: Icons.storefront_outlined,
                label: 'Business Profile',
                sublabel: 'Edit business info',
                onTap: () => context.push('/business-profile'),
              ),
              _SettingsItem(
                icon: Icons.photo_library_outlined,
                label: 'Portfolio',
                sublabel: 'Manage work photos',
                onTap: () => context.push('/portfolio'),
              ),
            ]),
            const SizedBox(height: 20),
          ],

          // ── Support ─────────────────────────────────────────────────────
          _SectionLabel('Support'),
          _SettingsGroup(items: [
            _SettingsItem(
              icon: Icons.help_outline_rounded,
              label: 'Help & Support',
              sublabel: 'Contact our team',
              onTap: () => context.push('/support'),
            ),
          ]),
          const SizedBox(height: 20),

          _SectionLabel('About HandyTrust'),
          const _AboutHandyTrustSection(),
          const SizedBox(height: 20),

          // ── Danger zone ─────────────────────────────────────────────────
          _SectionLabel('Account Actions'),
          _SettingsGroup(items: [
            _SettingsItem(
              icon: Icons.logout_rounded,
              label: 'Sign Out',
              color: context.colors.error,
              onTap: () => _confirmSignOut(context, ref),
            ),
            if (user != null)
              _SettingsItem(
                icon: Icons.delete_outline_rounded,
                label: user.accountDeletionRequested
                    ? 'Deletion Requested'
                    : 'Request Account Deletion',
                sublabel: user.accountDeletionRequested
                    ? 'Under review by our team'
                    : 'Permanently delete your account',
                color: user.accountDeletionRequested
                    ? context.colors.textTertiary
                    : context.colors.error,
                onTap: user.accountDeletionRequested
                    ? () => _cancelDeletion(context, ref, user.uid)
                    : () => _requestDeletion(context, ref, user.uid),
              ),
          ]),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _editUsername(BuildContext context, WidgetRef ref, String current) {
    showDialog(
      context: context,
      builder: (_) => _TextEditDialog(
        title: 'Edit Username',
        label: 'Username',
        initial: current,
        hint: 'e.g. john_doe',
        maxLength: 30,
        onSave: (value) async {
          final uid = ref.read(currentUserProvider).asData?.value?.uid;
          if (uid == null) return;
          await ref.read(profileServiceProvider).updateUsername(uid, value);
          if (context.mounted) showSuccessSnackbar(context, 'Username updated!');
        },
      ),
    );
  }

  void _editName(BuildContext context, WidgetRef ref, String current) {
    showDialog(
      context: context,
      builder: (_) => _TextEditDialog(
        title: 'Edit Name',
        label: 'Full Name',
        initial: current,
        hint: 'Your full name',
        maxLength: 60,
        onSave: (value) async {
          final uid = ref.read(currentUserProvider).asData?.value?.uid;
          if (uid == null) return;
          await ref.read(profileServiceProvider).updateName(uid, value);
          if (context.mounted) showSuccessSnackbar(context, 'Name updated!');
        },
      ),
    );
  }

  void _changeEmail(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _ChangeEmailDialog(ref: ref),
    );
  }

  void _changePassword(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _ChangePasswordDialog(ref: ref),
    );
  }

  void _switchRole(BuildContext context, WidgetRef ref, dynamic user) {
    final next = user.activeRole == 'artisan' ? 'customer' : 'artisan';
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Switch to ${next[0].toUpperCase()}${next.substring(1)}'),
        content: Text(
            'Switch to ${next == 'artisan' ? 'Artisan' : 'Customer'} mode?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Switch'),
          ),
        ],
      ),
    ).then((ok) async {
      if (ok != true) return;
      final uid = ref.read(currentUserProvider).asData?.value?.uid;
      if (uid == null) return;
      await ref.read(profileServiceProvider).setActiveRole(uid, next);
      if (context.mounted) context.go('/home');
    });
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) ref.read(authNotifierProvider.notifier).signOut();
    });
  }

  void _requestDeletion(BuildContext context, WidgetRef ref, String uid) {
    final reasonCtrl = TextEditingController();
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Account Deletion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Your account will be reviewed and deleted within 7 days. '
                'Active jobs and escrow must be resolved first.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Submit Request'),
          ),
        ],
      ),
    ).then((ok) async {
      if (ok != true) return;
      try {
        await ref
            .read(profileServiceProvider)
            .requestAccountDeletion(uid, reason: reasonCtrl.text);
        if (context.mounted) {
          showSuccessSnackbar(context, 'Deletion request submitted.');
        }
      } catch (e) {
        if (context.mounted) showErrorSnackbar(context, 'Failed: $e');
      }
    });
  }

  void _cancelDeletion(BuildContext context, WidgetRef ref, String uid) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Deletion Request'),
        content: const Text('Are you sure you want to cancel your account deletion request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel Request'),
          ),
        ],
      ),
    ).then((ok) async {
      if (ok != true) return;
      try {
        await ref.read(profileServiceProvider).cancelDeletionRequest(uid);
        if (context.mounted) {
          showSuccessSnackbar(context, 'Deletion request cancelled.');
        }
      } catch (e) {
        if (context.mounted) showErrorSnackbar(context, 'Failed: $e');
      }
    });
  }
}

// ─── Profile Card ──────────────────────────────────────────────────────────────

class _ProfileCard extends ConsumerStatefulWidget {
  final dynamic user;
  const _ProfileCard({required this.user});

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  bool _uploadingPhoto = false;

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      await ref
          .read(profileServiceProvider)
          .uploadAvatar(widget.user.uid, Uint8List.fromList(bytes));
      if (mounted) showSuccessSnackbar(context, 'Profile photo updated!');
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Photo'),
        content: const Text('Remove your profile photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(profileServiceProvider)
          .removeAvatar(widget.user.uid);
      if (mounted) showSuccessSnackbar(context, 'Photo removed.');
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              UserAvatar(
                photoUrl: user.photoUrl as String?,
                displayName: user.displayUsername as String,
                size: 64,
                borderWidth: 2,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: context.colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: context.colors.surface, width: 2),
                    ),
                    child: _uploadingPhoto
                        ? const Padding(
                            padding: EdgeInsets.all(4),
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: Colors.white),
                          )
                        : const Icon(Icons.camera_alt_rounded,
                            size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayUsername as String,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    fontFamily: 'Inter',
                  ),
                ),
                if (user.username != null && user.username!.isNotEmpty)
                  Text(
                    '@${user.username}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.primary,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  user.email as String? ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _RolePill(label: user.activeRole as String),
                  ],
                ),
              ],
            ),
          ),
          if ((user.photoUrl as String?)?.isNotEmpty == true)
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: context.colors.error, size: 20),
              onPressed: _removePhoto,
              tooltip: 'Remove photo',
            ),
        ],
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  final String label;
  const _RolePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label[0].toUpperCase() + label.substring(1),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: context.colors.primary,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

// ─── Section Label / Group / Item ─────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: context.colors.textTertiary,
          fontFamily: 'Inter',
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> items;
  const _SettingsGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              item,
              if (i < items.length - 1)
                Divider(height: 1, indent: 56, color: context.colors.border),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? trailing;

  const _SettingsItem({
    required this.icon,
    required this.label,
    this.sublabel,
    this.onTap,
    this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.colors.textPrimary;
    final iconColor = color ?? context.colors.primary;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: fg,
          fontFamily: 'Inter',
        ),
      ),
      subtitle: sublabel != null
          ? Text(
              sublabel!,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            )
          : null,
      trailing: trailing ??
          (color == null && onTap != null
              ? Icon(Icons.chevron_right_rounded,
                  color: context.colors.textTertiary, size: 20)
              : null),
    );
  }
}

class _SettingsToggleItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleItem({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: context.colors.primary, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: context.colors.textPrimary,
          fontFamily: 'Inter',
        ),
      ),
      subtitle: sublabel != null
          ? Text(
              sublabel!,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            )
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: context.colors.primary,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ─── Dialogs ──────────────────────────────────────────────────────────────────

class _TextEditDialog extends StatefulWidget {
  final String title;
  final String label;
  final String initial;
  final String hint;
  final int maxLength;
  final Future<void> Function(String) onSave;

  const _TextEditDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.hint,
    required this.maxLength,
    required this.onSave,
  });

  @override
  State<_TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<_TextEditDialog> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: widget.maxLength,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    await widget.onSave(_ctrl.text.trim());
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _ChangeEmailDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _ChangeEmailDialog({required this.ref});

  @override
  ConsumerState<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends ConsumerState<_ChangeEmailDialog> {
  final _passwordCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Email'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter your current password and the new email. '
            'A verification link will be sent to the new address.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Current Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'New Email',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    await ref.read(profileServiceProvider).updateEmail(
                          currentPassword: _passwordCtrl.text,
                          newEmail: _emailCtrl.text.trim(),
                        );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      showSuccessSnackbar(
                          context, 'Verification sent to ${_emailCtrl.text.trim()}');
                    }
                  } catch (e) {
                    if (context.mounted) showErrorSnackbar(context, 'Failed: $e');
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Update'),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _ChangePasswordDialog({required this.ref});

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState
    extends ConsumerState<_ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _currentCtrl,
            obscureText: _obscureCurrent,
            decoration: InputDecoration(
              labelText: 'Current Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureCurrent
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newCtrl,
            obscureText: _obscureNew,
            decoration: InputDecoration(
              labelText: 'New Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureNew ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscureNew = !_obscureNew),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm New Password',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  if (_newCtrl.text != _confirmCtrl.text) {
                    showErrorSnackbar(context, 'Passwords do not match.');
                    return;
                  }
                  if (_newCtrl.text.length < 6) {
                    showErrorSnackbar(
                        context, 'Password must be at least 6 characters.');
                    return;
                  }
                  setState(() => _saving = true);
                  try {
                    await ref.read(profileServiceProvider).updatePassword(
                          currentPassword: _currentCtrl.text,
                          newPassword: _newCtrl.text,
                        );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      showSuccessSnackbar(context, 'Password updated!');
                    }
                  } catch (e) {
                    if (context.mounted) showErrorSnackbar(context, 'Failed: $e');
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Update'),
        ),
      ],
    );
  }
}

// ─── About HandyTrust Accordions ──────────────────────────────────────────────

class _AboutHandyTrustSection extends StatelessWidget {
  const _AboutHandyTrustSection();

  static const _items = [
    (
      icon: Icons.info_outline_rounded,
      title: 'What is HandyTrust?',
      body:
          'HandyTrust is a platform that connects homeowners and businesses with '
          'skilled, verified artisans. Every artisan goes through an approval '
          'process and builds a trust score based on job performance, reviews, '
          'and reliability — so you can hire with confidence.',
    ),
    (
      icon: Icons.person_outline_rounded,
      title: 'How customers use HandyTrust',
      body:
          'Post a job describing what you need. Artisans in your category will '
          'send quotes. Review their trust score, ratings, and portfolio before '
          'hiring. Once you accept a quote, your payment is held safely in escrow '
          'and only released when the job is done.',
    ),
    (
      icon: Icons.handyman_outlined,
      title: 'How artisans use HandyTrust',
      body:
          'Register as an artisan, complete your profile, and submit your ID for '
          'verification. Once approved, you\'ll appear in the artisan directory '
          'and receive job requests. Deliver quality work to build your trust '
          'score and attract more customers.',
    ),
    (
      icon: Icons.verified_user_outlined,
      title: 'Verification process',
      body:
          'Artisans must submit a government-issued ID and a selfie for identity '
          'verification. You are notified when the review is complete. '
          'Verified artisans display a badge and can unlock higher trust tiers '
          'as they accumulate successful jobs.',
    ),
    (
      icon: Icons.shield_outlined,
      title: 'Trust score explained',
      body:
          'The trust score (0–100) is calculated from multiple signals: job '
          'completion rate, average rating, response time, dispute history, and '
          'verification status. Scores of 70+ are "Trusted" and 90+ are "Elite". '
          'A higher score leads to more visibility in search results.',
    ),
    (
      icon: Icons.star_outline_rounded,
      title: 'Reviews & ratings',
      body:
          'After every completed job, both the customer and artisan can leave a '
          'review. Ratings are on a 1–5 star scale. Reviews are publicly visible '
          'on the artisan\'s profile and directly influence their trust score. '
          'Fake or abusive reviews can be reported to our support team.',
    ),
    (
      icon: Icons.security_outlined,
      title: 'Safety guidelines',
      body:
          'Never share passwords or make payments outside the app. All legitimate '
          'payments go through the in-app escrow system. If an artisan asks for '
          'cash upfront before starting, report them. HandyTrust never contacts '
          'you asking for login credentials.',
    ),
    (
      icon: Icons.help_outline_rounded,
      title: 'Frequently asked questions',
      body:
          'Q: Is HandyTrust available outside Nigeria?\n'
          'A: Currently Nigeria only, with expansion planned.\n\n'
          'Q: What happens if I\'m unhappy with the work?\n'
          'A: Raise a dispute before releasing payment — our team will mediate.\n\n'
          'Q: How long does escrow hold the payment?\n'
          'A: Until you confirm the work, or until the 14-day review period after the artisan submits it ends.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        children: _items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color:
                          context.colors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(item.icon,
                        size: 18, color: context.colors.primary),
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  iconColor: context.colors.textTertiary,
                  collapsedIconColor: context.colors.textTertiary,
                  children: [
                    Text(
                      item.body,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.6,
                        color: context.colors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
              if (i < _items.length - 1)
                Divider(
                    height: 1,
                    indent: 56,
                    color: context.colors.border),
            ],
          );
        }).toList(),
      ),
    );
  }
}
