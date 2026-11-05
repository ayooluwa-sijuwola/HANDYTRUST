import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/artisan_work_logic.dart';
import '../../../core/services/notification_category.dart';
import '../../../models/job_model.dart';
import '../../../models/message_model.dart';
import '../../../models/notification_model.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/escrow_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../components/ht_components.dart';
import '../../components/ht_format.dart';
import '../../components/ht_kit.dart';
import '../../theme/ht_theme.dart';
import '../artisan_shell.dart';
import '../components/pro_components.dart';
import 'work_ui.dart';

/// SH-03 (artisan) Messages: conversations by job, with the job's stage,
/// last message and unread count. Same data as the previous chat list
/// (`artisanChatJobsProvider`, `lastMessageProvider`, `chatUnreadCountProvider`).
class ArtisanMessagesScreen extends ConsumerStatefulWidget {
  const ArtisanMessagesScreen({super.key});
  @override
  ConsumerState<ArtisanMessagesScreen> createState() => _ArtisanMessagesScreenState();
}

class _ArtisanMessagesScreenState extends ConsumerState<ArtisanMessagesScreen> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(artisanContextProvider).asData?.value;
    if (ctx == null) return const ArtisanPage(title: 'Messages', children: [SizedBox(height: 80), HtLoadingView()]);
    final jobsAsync = ref.watch(artisanChatJobsProvider(ctx.uid));
    return ArtisanPage(
      title: 'Messages',
      children: [
        HtSearchField(controller: _search, hint: 'Search jobs or areas', onChanged: (_) => setState(() {})),
        const SizedBox(height: 6),
        jobsAsync.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 40), child: HtLoadingView(label: 'Loading conversations…')),
          error: (e, _) => ArtisanState.error(e, onRetry: () => ref.invalidate(artisanJobsProvider(ctx.uid))),
          data: (jobs) {
            final q = _search.text.trim().toLowerCase();
            final list = jobs
                .where((j) => j.status != JobStatus.requested)
                .where((j) => q.isEmpty || j.description.toLowerCase().contains(q) || j.category.toLowerCase().contains(q) || (j.areaLabel ?? '').toLowerCase().contains(q))
                .toList();
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(top: 18),
                child: HtCard(child: HtEmptyView(icon: Icons.forum_outlined, title: 'No conversations yet', message: 'Chats with customers appear here once you’re booked or message about a job.')),
              );
            }
            final rows = [for (final j in list) (j, ref.watch(lastMessageProvider(ChatThreadKey(jobId: j.id, viewerId: ctx.uid, otherPartyId: j.customerId))).asData?.value)];
            rows.sort((a, b) => (b.$2?.createdAt ?? b.$1.createdAt).compareTo(a.$2?.createdAt ?? a.$1.createdAt));
            return Column(children: [for (final (j, m) in rows) _ConversationRow(job: j, last: m, viewerId: ctx.uid)]);
          },
        ),
      ],
    );
  }
}

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({required this.job, required this.last, required this.viewerId});
  final JobModel job;
  final MessageModel? last;
  final String viewerId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final unread = ref.watch(chatUnreadCountProvider((jobId: job.id, userId: viewerId))).asData?.value ?? 0;
    final stage = ArtisanWorkLogic.stageOf(job);
    final preview = last == null ? 'No messages yet' : (last!.type == MessageType.image ? 'Photo' : last!.text);
    return InkWell(
      onTap: () => context.push('/chat/${job.id}', extra: {'artisanId': job.customerId, 'artisanName': 'Customer'}),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
        child: Row(children: [
          htIconTile(context, categoryIcon(job.category), size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(workTitle(job), style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (last != null) Text(HtFormat.timeAgo(last!.createdAt), style: HtType.small(p.textMuted).copyWith(fontSize: 11)),
              ]),
              Text(preview, style: HtType.small(unread > 0 ? p.textPrimary : p.textSecondary).copyWith(fontWeight: unread > 0 ? FontWeight.w600 : null), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Row(children: [
                HtStatusPill(label: ArtisanWorkLogic.stageLabel(job), tone: stageTone(stage)),
                const SizedBox(width: 6),
                Expanded(child: Text('${job.areaLabel ?? job.category} · #${HtFormat.bookingRef(job.id)}', style: HtType.small(p.textMuted).copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (unread > 0)
                  Semantics(
                    label: '$unread unread',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: proAccent(p), borderRadius: BorderRadius.circular(HtRadius.pill)),
                      child: Text('$unread', style: HtType.smallStrong(proOnAccent(p)).copyWith(fontSize: 11)),
                    ),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// SH-04 (artisan) Notifications: categories, today/earlier, mark read,
/// open the allow-listed destination.
class ArtisanNotificationsScreen extends ConsumerStatefulWidget {
  const ArtisanNotificationsScreen({super.key});
  @override
  ConsumerState<ArtisanNotificationsScreen> createState() => _ArtisanNotificationsScreenState();
}

class _ArtisanNotificationsScreenState extends ConsumerState<ArtisanNotificationsScreen> {
  NotificationCategory? _filter;

  (IconData, HtTone) _look(NotificationModel n) {
    final chip = NotificationCategories.chipLabel(n);
    return switch (chip) {
      'Booking' => (Icons.mark_email_unread_outlined, HtTone.danger),
      'Quote' => (Icons.request_quote_outlined, HtTone.accent),
      'Payout' => (Icons.payments_outlined, HtTone.success),
      'Escrow' => (Icons.lock_outline_rounded, HtTone.warning),
      'Dispute' => (Icons.gavel_rounded, HtTone.danger),
      'Agreement' => (Icons.handshake_outlined, HtTone.warning),
      'Review' => (Icons.star_outline_rounded, HtTone.accent),
      'Verification' => (Icons.verified_user_outlined, HtTone.accent),
      'Message' => (Icons.forum_outlined, HtTone.neutral),
      'Refund' => (Icons.undo_rounded, HtTone.warning),
      _ => (Icons.work_outline_rounded, HtTone.neutral),
    };
  }

  Future<void> _open(NotificationModel n) async {
    if (!n.isRead) {
      try {
        await ref.read(notificationServiceProvider).markRead(n.id);
      } catch (_) {
        // Navigation still works if marking read fails.
      }
    }
    if (!mounted) return;
    final route = n.route ?? (n.jobId != null ? '/job/${n.jobId}' : null);
    if (route != null) context.push(safeNotificationRoute(route));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final listAsync = ref.watch(userNotificationsProvider);
    final uid = ref.watch(artisanContextProvider).asData?.value?.uid;
    final all = listAsync.asData?.value ?? const <NotificationModel>[];
    final unread = all.where((n) => !n.isRead).length;
    return ArtisanPage(
      title: 'Notifications',
      sub: unread == 0 ? 'All caught up' : '$unread unread',
      children: [
        Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (c, label) in const [(null, 'All'), (NotificationCategory.jobs, 'Jobs'), (NotificationCategory.escrow, 'Escrow & Pay'), (NotificationCategory.account, 'Account')]) ...[
                  HtChip(label: label, selected: _filter == c, onTap: () => setState(() => _filter = c)),
                  const SizedBox(width: 8),
                ],
              ]),
            ),
          ),
          TextButton(
            onPressed: unread == 0 || uid == null
                ? null
                : () async {
                    try {
                      await ref.read(notificationServiceProvider).markAllRead(uid);
                    } catch (_) {
                      if (context.mounted) htSnack(context, 'Could not mark all as read.', error: true);
                    }
                  },
            child: Text('Mark all read', style: HtType.smallStrong(unread == 0 ? p.textMuted : proAccent(p))),
          ),
        ]),
        listAsync.when(
          loading: () => const Padding(padding: EdgeInsets.only(top: 40), child: HtLoadingView(label: 'Loading notifications…')),
          error: (e, _) => ArtisanState.error(e, onRetry: () => ref.invalidate(userNotificationsProvider)),
          data: (list) {
            final shown = _filter == null ? list : list.where((n) => NotificationCategories.of(n) == _filter).toList();
            if (shown.isEmpty) {
              return const Padding(padding: EdgeInsets.only(top: 18), child: HtCard(child: HtEmptyView(icon: Icons.notifications_none_rounded, title: 'No notifications', message: 'Booking requests, quote updates and payouts appear here.')));
            }
            final now = clock.now();
            final today = shown.where((n) => n.createdAt.toLocal().year == now.year && n.createdAt.toLocal().month == now.month && n.createdAt.toLocal().day == now.day).toList();
            final earlier = shown.where((n) => !today.contains(n)).toList();
            Widget row(NotificationModel n) {
              final (icon, tone) = _look(n);
              return InkWell(
                onTap: () => _open(n),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    htIconTile(context, icon, tone: tone, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(n.title, style: HtType.bodyStrong(p.textPrimary).copyWith(fontSize: 13.5)),
                        Text(n.body, style: HtType.small(p.textSecondary), maxLines: 3, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Column(children: [
                      Text(HtFormat.timeAgo(n.createdAt), style: HtType.small(p.textMuted).copyWith(fontSize: 11)),
                      if (!n.isRead) Semantics(label: 'Unread', child: Container(margin: const EdgeInsets.only(top: 6), width: 8, height: 8, decoration: BoxDecoration(color: proAccent(p), shape: BoxShape.circle))),
                    ]),
                  ]),
                ),
              );
            }

            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (today.isNotEmpty) ...[const ProSection('Today'), for (final n in today) row(n)],
              if (earlier.isNotEmpty) ...[const ProSection('Earlier'), for (final n in earlier) row(n)],
              const SizedBox(height: 14),
              HtSecondaryButton(label: 'Notification settings', icon: Icons.tune_rounded, onPressed: () => context.push('/settings')),
            ]);
          },
        ),
      ],
    );
  }
}
