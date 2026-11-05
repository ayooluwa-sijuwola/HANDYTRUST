import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/notification_category.dart';
import '../../models/notification_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../theme/ht_theme.dart';

/// Notifications (references 12 dark, 24 light). Data: userNotificationsProvider
/// (server-generated, Stage 6). Taps mark the item read and follow the
/// server deep link through the safeNotificationRoute allow-list.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  NotificationCategory? _filter;
  bool _markingAll = false;

  Future<void> _markAll(String uid) async {
    setState(() => _markingAll = true);
    try {
      await ref.read(notificationServiceProvider).markAllRead(uid);
    } catch (e) {
      if (mounted) htSnack(context, 'Could not mark notifications as read', error: true);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _open(NotificationModel n) async {
    if (!n.isRead) {
      try {
        await ref.read(notificationServiceProvider).markRead(n.id);
      } catch (_) {
        // Read state is cosmetic; navigation still proceeds.
      }
    }
    if (!mounted) return;
    // Stage 8.2: same destination rules as push taps (a new-message
    // notification opens the conversation, not the job page).
    context.push(notificationDestination(n));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final user = ref.watch(currentUserProvider).asData?.value;
    final async = ref.watch(userNotificationsProvider);

    return Scaffold(
      backgroundColor: p.background,
      body: HtBackground(
        glow: !p.isDark,
        child: SafeArea(
          child: async.when(
            loading: () => Column(children: [_header(user?.name), const Expanded(child: HtLoadingView())]),
            error: (e, _) => Column(children: [
              _header(user?.name),
              HtErrorView(message: 'Notifications could not be loaded.', onRetry: () => ref.invalidate(userNotificationsProvider)),
            ]),
            data: (all) {
              final unread = all.where((n) => !n.isRead).length;
              final list = _filter == null ? all : all.where((n) => NotificationCategories.of(n) == _filter).toList();
              final today = list.where((n) => HtFormat.dayLabel(n.createdAt) == 'Today').toList();
              final earlier = list.where((n) => HtFormat.dayLabel(n.createdAt) != 'Today').toList();
              return ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  _header(user?.name),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 10, HtSpace.gutter, 0),
                    child: Row(
                      children: [
                        if (p.isDark) ...[
                          Flexible(child: Text('Notifications', style: HtType.screenTitle(p.textPrimary).copyWith(fontSize: 26), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 10),
                          if (unread > 0) _CountBubble(unread),
                        ] else ...[
                          _CountBubble(unread),
                          const SizedBox(width: 10),
                          Flexible(child: Text('Unread alerts', style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                        const SizedBox(width: 8),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: unread == 0 || _markingAll || user == null ? null : () => _markAll(user.uid),
                          icon: Icon(Icons.done_all_rounded, size: 18, color: p.accent),
                          label: Text(p.isDark ? 'Mark all read' : 'Mark all as read', style: HtType.smallStrong(p.accent).copyWith(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  if (!p.isDark)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 4, HtSpace.gutter, 0),
                      child: Text('Recent updates regarding your jobs, escrow and account.', style: HtType.body(p.textSecondary)),
                    ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: HtSpace.gutter),
                    child: Row(
                      children: [
                        HtChip(label: 'All', count: all.isEmpty ? null : all.length, selected: _filter == null, onTap: () => setState(() => _filter = null)),
                        const SizedBox(width: 10),
                        HtChip(label: 'Escrow & Pay', icon: Icons.shield_outlined, selected: _filter == NotificationCategory.escrow, onTap: () => setState(() => _filter = NotificationCategory.escrow)),
                        const SizedBox(width: 10),
                        HtChip(label: 'Jobs', icon: Icons.handshake_outlined, selected: _filter == NotificationCategory.jobs, onTap: () => setState(() => _filter = NotificationCategory.jobs)),
                        const SizedBox(width: 10),
                        HtChip(label: 'Account', selected: _filter == NotificationCategory.account, onTap: () => setState(() => _filter = NotificationCategory.account)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (list.isEmpty)
                    const HtEmptyView(icon: Icons.notifications_none_rounded, title: 'No notifications', message: 'Updates about your jobs and payments will appear here.')
                  else ...[
                    if (today.isNotEmpty) _group('TODAY', '${today.where((n) => !n.isRead).length} new', today),
                    if (earlier.isNotEmpty) _group('EARLIER', null, earlier),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 18, HtSpace.gutter, 0),
                    child: HtCard(
                      padding: EdgeInsets.zero,
                      child: HtMenuRow(
                        icon: Icons.tune_rounded,
                        title: 'Manage Notification Settings',
                        subtitle: 'Push alerts and preferences',
                        onTap: () => context.push('/settings/notifications'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(String? name) {
    final p = context.ht;
    return HtScreenHeader(
      title: p.isDark ? '' : 'Notifications',
      center: false,
      trailing: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: p.headerAvatarFill, shape: BoxShape.circle),
        child: Icon(Icons.person_outline_rounded, color: p.onHeaderAvatar),
      ),
    );
  }

  Widget _group(String label, String? trailing, List<NotificationModel> items) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 6, HtSpace.gutter, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p.isDark)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 12, top: 6),
              child: Row(
                children: [
                  Text(label, style: HtType.caps(p.textSecondary).copyWith(fontSize: 11)),
                  const Spacer(),
                  if (trailing != null) Text(trailing, style: HtType.small(p.textMuted)),
                ],
              ),
            ),
          HtCard(
            radius: 30,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.border, indent: 18, endIndent: 18),
                  _NotificationTile(n: items[i], onTap: () => _open(items[i])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBubble extends StatelessWidget {
  const _CountBubble(this.count);
  final int count;
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Container(
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.isDark ? p.accentSoft : const Color(0xFFDCE8A8), shape: BoxShape.circle),
      child: Text('$count', style: HtType.bodyStrong(p.isDark ? p.accent : p.accentStrong)),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});
  final NotificationModel n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final cat = NotificationCategories.of(n);
    final icon = switch (cat) {
      NotificationCategory.escrow => Icons.lock_outline_rounded,
      NotificationCategory.account => Icons.badge_outlined,
      NotificationCategory.jobs => Icons.handshake_outlined,
    };
    final unread = !n.isRead;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: unread ? (p.isDark ? p.accentSoft : const Color(0xFFDCE8A8)) : p.surfaceRaised,
                borderRadius: BorderRadius.circular(p.isDark ? 12 : 28),
              ),
              child: Icon(icon, color: unread ? (p.isDark ? p.accent : p.accentStrong) : p.textSecondary, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(n.title, style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (unread) ...[
                        const SizedBox(width: 6),
                        Container(margin: const EdgeInsets.only(top: 7), width: 9, height: 9, decoration: BoxDecoration(color: p.isDark ? p.accent : p.accentStrong, shape: BoxShape.circle)),
                      ],
                      const SizedBox(width: 8),
                      Text(HtFormat.timeAgo(n.createdAt), style: HtType.small(p.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(n.body, style: HtType.body(p.textSecondary).copyWith(fontSize: 12.5), maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  HtStatusPill(
                    label: NotificationCategories.chipLabel(n),
                    tone: unread ? HtTone.accent : HtTone.neutral,
                    dot: unread,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
