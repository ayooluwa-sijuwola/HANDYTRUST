import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/conversation_logic.dart';
import '../../core/services/customer_booking_logic.dart';
import '../../models/job_model.dart';
import '../../models/message_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/escrow_provider.dart';
import '../components/ht_components.dart';
import '../components/ht_format.dart';
import '../components/ht_kit.dart';
import '../theme/ht_theme.dart';

/// CU-MC My Chats (customer), Stage 8.2 rebuild. Lists the customer's real
/// conversations: one per booked job, and one per artisan who has written
/// about a still-open job. Last message, time, per-conversation unread
/// count, search and an Unread filter over the loaded conversations.
class CustomerMessagesScreen extends ConsumerStatefulWidget {
  const CustomerMessagesScreen({super.key});
  @override
  ConsumerState<CustomerMessagesScreen> createState() => _CustomerMessagesScreenState();
}

class _CustomerMessagesScreenState extends ConsumerState<CustomerMessagesScreen> {
  final _search = TextEditingController();
  bool _unreadOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _nameOf(ConversationRef c) => ref.read(artisanProfileProvider(c.otherPartyId)).asData?.value?.displayName ?? 'Artisan';

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final user = ref.watch(currentUserProvider).asData?.value;
    final online = ref.watch(isOnlineProvider).asData?.value ?? true;
    return Scaffold(
      backgroundColor: p.background,
      body: HtBackground(
        glow: false,
        child: SafeArea(
          child: Column(children: [
            HtScreenHeader(title: 'My Chats', subtitle: 'Conversations about your jobs', onBack: () => context.canPop() ? context.pop() : context.go('/home')),
            if (user == null)
              const Expanded(child: HtLoadingView())
            else
              Expanded(child: _body(context, user.uid, online)),
          ]),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, String uid, bool online) {
    final p = context.ht;
    final viewsAsync = ref.watch(conversationViewsProvider((uid: uid, asArtisan: false)));
    return viewsAsync.when(
      loading: () => const _ChatsSkeleton(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(HtSpace.gutter),
        child: HtCard(child: HtErrorView(message: 'We couldn’t load your chats. Check your connection and try again.', onRetry: () => ref.invalidate(customerJobsProvider(uid)))),
      ),
      data: (views) {
        final unreadTotal = ConversationLogic.totalUnread(views.map((v) => v.unread));
        var list = ConversationLogic.search(views, _search.text, nameOf: _nameOf);
        if (_unreadOnly) list = list.where((v) => v.unread > 0).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 4, HtSpace.gutter, 28),
          children: [
            if (!online) ...[
              const HtInfoBanner(icon: Icons.cloud_off_rounded, tone: HtTone.warning, text: 'You’re offline. Showing saved messages; new ones arrive when you reconnect.'),
              const SizedBox(height: 12),
            ],
            if (views.isNotEmpty) ...[
              HtSearchField(controller: _search, hint: 'Search artisans, jobs or messages', onChanged: (_) => setState(() {})),
              const SizedBox(height: 10),
              Row(children: [
                HtChip(label: 'All', count: views.length, selected: !_unreadOnly, onTap: () => setState(() => _unreadOnly = false)),
                const SizedBox(width: 8),
                HtChip(label: 'Unread', count: unreadTotal, selected: _unreadOnly, onTap: () => setState(() => _unreadOnly = true)),
              ]),
              const SizedBox(height: 12),
            ],
            if (views.isEmpty)
              HtCard(
                child: HtEmptyView(
                  icon: Icons.forum_outlined,
                  title: 'No chats yet',
                  message: 'When an artisan messages you about a job, or you book one, your conversation appears here.',
                  action: HtSmallPrimaryButton(label: 'Post a job', onPressed: () => context.push('/request')),
                ),
              )
            else if (list.isEmpty)
              HtCard(child: HtEmptyView(icon: Icons.search_off_rounded, title: _unreadOnly ? 'All caught up' : 'No matches', message: _unreadOnly ? 'You have no unread messages.' : 'Try a different search.'))
            else
              HtCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: p.border, indent: 76),
                    _ConversationTile(view: list[i]),
                  ],
                ]),
              ),
          ],
        );
      },
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.view});
  final ConversationView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final c = view.ref;
    final artisan = ref.watch(artisanProfileProvider(c.otherPartyId)).asData?.value;
    final name = artisan?.displayName ?? 'Artisan';
    final job = c.job;
    final last = view.last;
    final mine = last != null && last.senderId == c.viewerId;
    final preview = last == null
        ? 'No messages yet'
        : '${mine ? 'You: ' : ''}${last.type == MessageType.image ? 'Photo' : last.text}';
    final unread = view.unread;
    final title = job.description.trim().split('\n').first;
    final (stage, tone) = _stage(job);
    return Semantics(
      button: true,
      label: '$name, $title${unread > 0 ? ', $unread unread' : ''}',
      child: InkWell(
        onTap: () => context.push('/chat/${job.id}?with=${c.otherPartyId}', extra: {'artisanId': c.otherPartyId, 'artisanName': name}),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HtAvatar(name: name, imageUrl: artisan?.profileImageUrl, size: 48, online: artisan?.isAvailable ?? false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(name, style: HtType.bodyStrong(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (last != null) Text(HtFormat.timeAgo(last.createdAt, now: clock.now()), style: HtType.small(unread > 0 ? p.accentStrong : p.textMuted).copyWith(fontSize: 11.5)),
                ]),
                const SizedBox(height: 1),
                Text(title, style: HtType.small(p.textSecondary).copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  if (mine) ...[
                    Icon(switch (ReadReceipts.of(last)) {
                      ReceiptState.sending => Icons.schedule_rounded,
                      ReceiptState.sent => Icons.done_rounded,
                      ReceiptState.read => Icons.done_all_rounded,
                    }, size: 14, color: last.isRead ? p.accentStrong : p.textMuted),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(preview,
                        style: HtType.small(unread > 0 ? p.textPrimary : p.textSecondary).copyWith(fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (unread > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: p.accentStrong, borderRadius: BorderRadius.circular(HtRadius.pill)),
                      child: Text('$unread', textAlign: TextAlign.center, style: HtType.smallStrong(p.onPrimary).copyWith(fontSize: 11)),
                    ),
                  ],
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  HtStatusPill(label: stage, tone: tone),
                  const SizedBox(width: 6),
                  Flexible(child: Text('#${HtFormat.bookingRef(job.id)}', style: HtType.small(p.textMuted).copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  static (String, HtTone) _stage(JobModel job) {
    if (job.artisanId.isEmpty) return ('Open job · quoting', HtTone.neutral);
    final s = CustomerBookingLogic.statusLabel(job);
    final tone = CustomerBookingLogic.isFunded(job) ? HtTone.success : HtTone.accent;
    return (s, tone);
  }
}

class _ChatsSkeleton extends StatelessWidget {
  const _ChatsSkeleton();
  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    Widget bar(double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(6)));
    return Semantics(
      label: 'Loading your chats',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 12, HtSpace.gutter, 28),
        children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(children: [
                Container(width: 48, height: 48, decoration: BoxDecoration(color: p.surfaceRaised, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(140, 12), const SizedBox(height: 8), bar(220, 10), const SizedBox(height: 6), bar(90, 10)])),
              ]),
            ),
        ],
      ),
    );
  }
}
