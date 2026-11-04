import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/notification_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(userNotificationsProvider);
    final user = ref.watch(currentUserProvider).asData?.value;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: user?.notificationsEnabled == false
                ? 'Notifications muted — tap to enable'
                : 'Mute notifications',
            icon: Icon(
              user?.notificationsEnabled == false
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_active_outlined,
            ),
            onPressed: user == null
                ? null
                : () => ref.read(authServiceProvider).updateUserProfile(
                      user.uid,
                      {'notificationsEnabled': !user.notificationsEnabled},
                    ),
          ),
          TextButton(
            onPressed: user == null
                ? null
                : () => _markAllRead(context, ref, user.uid),
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(message: '$e'),
        data: (notifications) {
          if (notifications.isEmpty) return const _EmptyState();

          final unread = notifications.where((n) => !n.isRead).toList();
          final read = notifications.where((n) => n.isRead).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (unread.isNotEmpty) ...[
                _SectionLabel('Unread (${unread.length})'),
                const SizedBox(height: 10),
                ...unread.map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _NotificationTile(notification: n),
                    )),
                const SizedBox(height: 20),
              ],
              if (read.isNotEmpty) ...[
                _SectionLabel(unread.isEmpty ? 'All' : 'Earlier'),
                const SizedBox(height: 10),
                ...read.map((n) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _NotificationTile(notification: n),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _markAllRead(BuildContext context, WidgetRef ref, String uid) async {
    try {
      await ref.read(notificationServiceProvider).markAllRead(uid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not mark notifications read: $e'),
            backgroundColor: context.colors.error,
          ),
        );
      }
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: context.colors.textSecondary,
          fontFamily: 'Inter',
          letterSpacing: 0.2,
        ),
      );
}

class _NotificationTile extends ConsumerStatefulWidget {
  final NotificationModel notification;

  const _NotificationTile({required this.notification});

  @override
  ConsumerState<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends ConsumerState<_NotificationTile> {
  bool _marking = false;

  IconData get _icon => switch (widget.notification.type) {
        'dispute_raised' || 'dispute_resolved' => Icons.gavel_rounded,
        'quote_received' => Icons.request_quote_rounded,
        'quote_accepted' => Icons.handshake_rounded,
        'quote_rejected' || 'quote_withdrawn' => Icons.block_outlined,
        'verification_approved' => Icons.verified_user_rounded,
        'verification_rejected' => Icons.gpp_bad_outlined,
        'job_assigned' => Icons.work_outline_rounded,
        'job_status_update' => Icons.update_rounded,
        'appointment_scheduled' => Icons.calendar_today_outlined,
        'message_received' => Icons.chat_bubble_outline_rounded,
        'review_received' => Icons.star_outline_rounded,
        'payout_completed' => Icons.account_balance_wallet_outlined,
        'payout_blocked' => Icons.error_outline_rounded,
        _ when widget.notification.type.startsWith('dispute') => Icons.gavel_rounded,
        _ when widget.notification.type.startsWith('quote') => Icons.request_quote_rounded,
        _ when widget.notification.type.startsWith('verification') => Icons.verified_user_rounded,
        _ when widget.notification.type.startsWith('payout') => Icons.account_balance_wallet_outlined,
        _ => Icons.notifications_rounded,
      };

  Future<void> _handleTap() async {
    final n = widget.notification;
    if (!n.isRead && !_marking) {
      setState(() => _marking = true);
      try {
        await ref.read(notificationServiceProvider).markRead(n.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not mark as read: $e'),
              backgroundColor: context.colors.error,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _marking = false);
      }
    }
    // Stage 6: follow the server-set deep link (validated), falling back to
    // the job page for older notifications that only carry a jobId.
    if (!mounted) return;
    if (n.route != null) {
      context.push(safeNotificationRoute(n.route));
    } else if (n.jobId != null) {
      context.push('/job/${n.jobId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: n.isRead ? context.colors.surface : context.colors.primarySurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, color: context.colors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                      color: context.colors.textPrimary,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n.body,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        DateFormat('MMM d, h:mm a').format(n.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.textTertiary,
                          fontFamily: 'Inter',
                        ),
                      ),
                      // Action indicator — this notification links to a
                      // job, tapping it navigates there. Real data (jobId
                      // presence), not a fabricated affordance.
                      if (n.jobId != null) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right_rounded,
                            size: 14, color: context.colors.textTertiary),
                        Text(
                          'View job',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.colors.primary,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (_marking)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: context.colors.primary),
              )
            else if (!n.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded, size: 56, color: context.colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No notifications yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "We'll let you know when there's something new.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: context.colors.error),
            const SizedBox(height: 12),
            Text(
              "Couldn't load notifications",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: context.colors.textSecondary, fontFamily: 'Inter'),
            ),
          ],
        ),
      ),
    );
  }
}
