import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/customer_booking_logic.dart';
import '../../core/services/workflow_gate_service.dart';
import '../../models/audit_log_model.dart';
import '../../models/job_model.dart';
import '../../models/message_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/escrow_provider.dart';
import '../components/ht_components.dart';
import '../../core/services/conversation_logic.dart';
import '../../core/services/artisan_work_logic.dart';
import '../artisan/components/pro_components.dart';
import '../components/ht_format.dart';
import '../theme/ht_theme.dart';

/// Job chat (references 11 dark, 20 light). Data: messagesStreamProvider,
/// jobStreamProvider; sending via chatNotifierProvider (text, image,
/// price proposal). The other party is derived from the job when the route
/// carries no extras. Reference items without backend support (voice call,
/// material receipts, preparation checklist, "Release 20% Deposit", gate
/// code, location pin) are not shown; the quick-action row carries the
/// job's real next workflow step instead.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.jobId, this.otherUserId = '', this.otherUserName});
  final String jobId;
  final String otherUserId;
  final String? otherUserName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  late final AppLifecycleListener _lifecycle;

  /// The conversation currently on screen, for read-marking on resume.
  ({String jobId, String other})? _open;

  @override
  void initState() {
    super.initState();
    // Stage 8.2: messages that arrived while the app was in the background
    // are marked read when the user returns to this conversation.
    _lifecycle = AppLifecycleListener(onResume: () {
      final o = _open;
      final uid = _uid;
      if (o == null || uid.isEmpty || o.other.isEmpty) return;
      ref.read(chatServiceProvider).markAllAsRead(o.jobId, viewerId: uid, otherPartyId: o.other).catchError((Object _) {});
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _uid => ref.read(authStateChangesProvider).asData?.value?.uid ?? '';

  String _otherId(JobModel job) {
    if (widget.otherUserId.isNotEmpty) return widget.otherUserId;
    return job.customerId == _uid ? job.artisanId : job.customerId;
  }

  ChatNotifierParams _params(JobModel job) => ChatNotifierParams(
        jobId: widget.jobId,
        senderId: _uid,
        receiverId: _otherId(job),
        senderRole: job.customerId == _uid ? ActorRole.customer : ActorRole.artisan,
      );

  Future<void> _sendText(JobModel job) async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    setState(() => _sending = true);
    await ref.read(chatNotifierProvider(_params(job)).notifier).sendText(t);
    if (!mounted) return;
    setState(() => _sending = false);
    final s = ref.read(chatNotifierProvider(_params(job)));
    if (s.hasError) htSnack(context, 'Message not sent: ${s.error}', error: true);
  }

  Future<void> _sendImage(JobModel job, ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 2560);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    setState(() => _sending = true);
    // StorageService strips photo metadata before upload (Stage 7.1).
    await ref.read(chatNotifierProvider(_params(job)).notifier).sendImageBytes(bytes);
    if (!mounted) return;
    setState(() => _sending = false);
    final s = ref.read(chatNotifierProvider(_params(job)));
    if (s.hasError) htSnack(context, 'Photo not sent: ${s.error}', error: true);
  }

  Future<void> _proposePrice(JobModel job) async {
    final p = context.ht;
    final controller = TextEditingController();
    final amount = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: p.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(HtRadius.card))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Propose a price', style: HtType.sectionTitle(p.textPrimary)),
            const SizedBox(height: 6),
            Text('The agreed price is confirmed in the job agreement before payment.', style: HtType.small(p.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: HtType.amount(p.textPrimary, size: 20.5),
              decoration: htInputDecoration(ctx, hint: 'Amount in naira').copyWith(prefixText: '₦'),
            ),
            const SizedBox(height: 16),
            HtPrimaryButton(
              label: 'Send proposal',
              onPressed: () {
                final v = double.tryParse(controller.text.trim());
                if (v != null && v > 0) Navigator.of(ctx).pop(v);
              },
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;
    await ref.read(chatNotifierProvider(_params(job)).notifier).sendNegotiation(amount);
    if (!mounted) return;
    final s = ref.read(chatNotifierProvider(_params(job)));
    if (s.hasError) htSnack(context, 'Proposal not sent: ${s.error}', error: true);
  }

  void _attachMenu(JobModel job) {
    final p = context.ht;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(HtRadius.card))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HtMenuRow(
              icon: Icons.photo_library_outlined,
              title: 'Photo from gallery',
              onTap: () {
                Navigator.of(ctx).pop();
                _sendImage(job, ImageSource.gallery);
              },
            ),
            if (job.status == JobStatus.inChat)
              HtMenuRow(
                icon: Icons.payments_outlined,
                title: 'Propose a price',
                onTap: () {
                  Navigator.of(ctx).pop();
                  _proposePrice(job);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final jobAsync = ref.watch(jobStreamProvider(widget.jobId));
    final signedIn = ref.watch(authStateChangesProvider).asData?.value?.uid;
    return Scaffold(
      backgroundColor: p.background,
      body: HtBackground(
        glow: false,
        child: SafeArea(
          child: signedIn == null
              ? const HtLoadingView()
              : jobAsync.when(
            loading: () => const HtLoadingView(),
            error: (e, _) => Column(children: [
              const HtScreenHeader(title: 'Chat'),
              HtErrorView(message: 'This chat could not be loaded.', onRetry: () => ref.invalidate(jobStreamProvider(widget.jobId))),
            ]),
            data: (job) {
              if (job == null) return const Column(children: [HtScreenHeader(title: 'Chat'), HtEmptyView(icon: Icons.search_off_rounded, title: 'Job not found')]);
              final other = _otherId(job);
              if (other.isEmpty) {
                // A customer's open job can have several artisan
                // conversations; without a counterpart we can't pick one.
                return Column(children: [
                  const HtScreenHeader(title: 'Chat'),
                  HtEmptyView(
                    icon: Icons.forum_outlined,
                    title: 'Choose a conversation',
                    message: 'This job has no booked artisan yet. Open your messages to pick the artisan you’re talking to.',
                    action: HtSmallPrimaryButton(label: 'Open messages', onPressed: () => context.go('/my-chats')),
                  ),
                ]);
              }
              _open = (jobId: job.id, other: other);
              return _ChatBody(
                job: job,
                viewerId: _uid,
                otherId: other,
                otherName: widget.otherUserName,
                text: _text,
                scroll: _scroll,
                onSend: () => _sendText(job),
                onAttach: () => _attachMenu(job),
                onCamera: () => _sendImage(job, ImageSource.camera),
                sending: _sending,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ChatBody extends ConsumerWidget {
  const _ChatBody({
    required this.job,
    required this.viewerId,
    required this.otherId,
    required this.otherName,
    required this.text,
    required this.scroll,
    required this.onSend,
    required this.onAttach,
    required this.onCamera,
    required this.sending,
  });
  final JobModel job;
  final String viewerId;
  final String otherId;
  final String? otherName;
  final TextEditingController text;
  final ScrollController scroll;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onCamera;
  final bool sending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ht;
    final viewerIsCustomer = job.customerId == viewerId;
    final otherArtisan = viewerIsCustomer ? ref.watch(artisanProfileProvider(otherId)).asData?.value : null;
    final name = otherArtisan?.displayName ?? otherName ?? (viewerIsCustomer ? 'Artisan' : 'Customer');
    final funded = CustomerBookingLogic.isFunded(job);
    final key = ChatThreadKey(jobId: job.id, viewerId: viewerId, otherPartyId: otherId);
    final messagesAsync = ref.watch(messagesStreamProvider(key));

    ref.listen(messagesStreamProvider(key), (_, next) {
      // Stage 8.2: read receipts are written only for THIS conversation and
      // only while the app is in the foreground (a chat left open behind
      // the lock screen must not report messages as read).
      final list = next.asData?.value ?? const <MessageModel>[];
      final state = WidgetsBinding.instance.lifecycleState;
      if (ReadReceipts.shouldMarkRead(
        appInForeground: state == null || state == AppLifecycleState.resumed,
        viewerId: viewerId,
        otherPartyId: otherId,
        messages: list,
      )) {
        ref.read(chatServiceProvider).markAllAsRead(job.id, viewerId: viewerId, otherPartyId: otherId).catchError((Object _) {});
      }
    });

    final title = job.description.trim().split('\n').first;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, HtSpace.gutter, 6),
          child: Row(
            children: [
              IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: p.textPrimary), tooltip: 'Back'),
              HtAvatar(name: name, imageUrl: otherArtisan?.profileImageUrl, size: 50, online: otherArtisan?.isAvailable ?? false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(name, style: HtType.cardTitle(p.textPrimary).copyWith(fontSize: 16.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (otherArtisan != null && (otherArtisan.verificationStatus == 'id_verified' || otherArtisan.verificationStatus == 'trusted')) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.verified_outlined, size: 18, color: p.success),
                      ],
                    ]),
                    Text(funded ? 'Escrow Active' : CustomerBookingLogic.statusLabel(job),
                        style: HtType.smallStrong(funded ? p.success : p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (funded && job.agreedAmount != null) HtStatusPill(label: HtFormat.naira(job.agreedAmount), tone: HtTone.accent, icon: Icons.lock_outline_rounded),
            ],
          ),
        ),
        // Stage 8.1: the job's artisan sees a work-order strip (job,
        // price, six-step work stepper) that opens the work order.
        if (!viewerIsCustomer)
          _ArtisanWorkStrip(job: job, title: title)
        else if (!p.isDark && funded)
          _EscrowOrderCard(job: job, title: title)
        else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HtSpace.gutter),
          child: InkWell(
            borderRadius: BorderRadius.circular(HtRadius.pill),
            onTap: () => context.push('/job/${job.id}'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(HtRadius.pill), border: Border.all(color: p.border)),
              child: Row(
                children: [
                  Icon(Icons.work_outline_rounded, size: 18, color: p.isDark ? p.accent : p.accentStrong),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${title.isEmpty ? job.category : title} (Job #${HtFormat.bookingRef(job.id)})', style: HtType.smallStrong(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Text('Details', style: HtType.smallStrong(p.isDark ? p.accent : p.accentStrong)),
                  Icon(Icons.chevron_right_rounded, size: 18, color: p.isDark ? p.accent : p.accentStrong),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: messagesAsync.when(
            loading: () => const HtLoadingView(),
            error: (e, _) => HtErrorView(message: 'Messages could not be loaded.', onRetry: () => ref.invalidate(messagesStreamProvider(key))),
            data: (messages) {
              final items = <Widget>[];
              if (funded && p.isDark) {
                items.add(Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: HtInfoBanner(
                    icon: Icons.verified_user_outlined,
                    title: 'HandyTrust SafeGuard Active',
                    text: viewerIsCustomer
                        ? 'Your payment of ${HtFormat.naira(job.agreedAmount)} is secured in escrow. Funds are released to $name only after you approve the completed work.'
                        : "The customer's payment of ${HtFormat.naira(job.agreedAmount)} is secured in escrow and released to you after they approve the completed work.",
                    tone: p.isDark ? HtTone.neutral : HtTone.accent,
                  ),
                ));
              }
              String? lastDay;
              for (final m in messages) {
                final day = HtFormat.dayLabel(m.createdAt);
                if (day != lastDay) {
                  lastDay = day;
                  items.add(Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.pill)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.calendar_today_outlined, size: 14, color: p.textSecondary),
                        const SizedBox(width: 6),
                        Text('$day • ${HtFormat.clock(m.createdAt)}', style: HtType.smallStrong(p.textSecondary)),
                      ]),
                    ),
                  ));
                }
                items.add(_Bubble(message: m, mine: m.senderId == viewerId, otherName: name));
              }
              if (messages.isEmpty) {
                items.add(HtEmptyView(icon: Icons.forum_outlined, title: 'Start the conversation', message: 'Agree the scope, price and a time with $name.'));
              }
              // Reversed so the newest message sits at the bottom and new
              // messages stay in view without manual scrolling.
              return ListView(
                controller: scroll,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 16, HtSpace.gutter, 8),
                children: items.reversed.toList(),
              );
            },
          ),
        ),
        _WorkflowChips(job: job, viewerIsCustomer: viewerIsCustomer),
        Padding(
          padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 6, HtSpace.gutter, 10),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(HtRadius.pill),
              border: Border.all(color: p.border),
              boxShadow: p.cardShadow,
            ),
            child: Row(
              children: [
                HtIconCircle(icon: Icons.add_rounded, tooltip: 'Attach', fill: p.surfaceRaised, onTap: onAttach),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: text,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    style: HtType.body(p.textPrimary),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Message ${name.split(' ').first}…',
                      hintStyle: HtType.body(p.textMuted),
                    ),
                  ),
                ),
                IconButton(onPressed: onCamera, tooltip: 'Take a photo', icon: Icon(Icons.photo_camera_outlined, color: p.textSecondary)),
                GestureDetector(
                  onTap: sending ? null : onSend,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(gradient: p.primary, shape: BoxShape.circle),
                    child: sending
                        ? Padding(padding: const EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2, color: p.onPrimary))
                        : Icon(Icons.arrow_upward_rounded, color: p.onPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The job's real next step, rendered in the reference's quick-action chip style.
class _WorkflowChips extends StatelessWidget {
  const _WorkflowChips({required this.job, required this.viewerIsCustomer});
  final JobModel job;
  final bool viewerIsCustomer;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    final chips = <(IconData, String, String)>[];
    if (WorkflowGateService.isAgreementRequired(job)) chips.add((Icons.handshake_outlined, 'Review agreement', '/job/${job.id}'));
    if (WorkflowGateService.isSchedulingRequired(job)) chips.add((Icons.event_outlined, 'Confirm schedule', '/job/${job.id}'));
    if (viewerIsCustomer && WorkflowGateService.isReadyForPayment(job)) chips.add((Icons.lock_outline_rounded, 'Pay into escrow', '/payment/${job.id}'));
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(HtSpace.gutter, 6, HtSpace.gutter, 0),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => ActionChip(
          avatar: Icon(chips[i].$1, size: 18, color: p.isDark ? p.accent : p.accentStrong),
          label: Text(chips[i].$2, style: HtType.smallStrong(p.textPrimary).copyWith(fontSize: 12)),
          backgroundColor: p.surface,
          side: BorderSide(color: p.border),
          shape: const StadiumBorder(),
          onPressed: () => context.push(chips[i].$3),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.otherName});
  final MessageModel message;
  final bool mine;
  final String otherName;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    if (message.type == MessageType.system) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: HtStatusPill(label: message.text, tone: HtTone.neutral, icon: Icons.info_outline_rounded),
        ),
      );
    }
    final maxW = MediaQuery.sizeOf(context).width * 0.76;
    final fg = mine ? p.onOutgoingBubble : p.textPrimary;
    Widget content;
    if (message.type == MessageType.image && (message.imageUrl ?? '').isNotEmpty) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(message.imageUrl!, width: maxW, height: maxW * 0.7, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(width: maxW, height: 120, color: p.surfaceRaised, child: Icon(Icons.broken_image_outlined, color: p.textMuted))),
      );
    } else if (message.type == MessageType.negotiation) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PRICE PROPOSAL', style: HtType.caps(fg.withValues(alpha: 0.8))),
          const SizedBox(height: 4),
          Text(HtFormat.naira(message.proposedAmount), style: HtType.amount(fg, size: 20.5)),
          if (message.text.trim().isNotEmpty) Text(message.text, style: HtType.small(fg.withValues(alpha: 0.85))),
        ],
      );
    } else {
      content = Text(message.text, style: HtType.body(fg).copyWith(fontSize: 14, height: 1.5));
    }
    final isImage = message.type == MessageType.image;
    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(HtFormat.clock(message.createdAt), style: HtType.small(mine ? fg.withValues(alpha: 0.85) : p.textMuted).copyWith(fontSize: 10.5)),
        if (mine) ...[
          const SizedBox(width: 4),
          _ReceiptIcon(state: ReadReceipts.of(message), color: fg),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!mine && !p.isDark)
            Padding(
              padding: const EdgeInsets.only(left: 40, bottom: 4),
              child: Text(otherName, style: HtType.small(p.textSecondary)),
            ),
          Row(
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) ...[HtAvatar(name: otherName, size: 32), const SizedBox(width: 8)],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(maxWidth: maxW),
                  padding: isImage ? const EdgeInsets.all(6) : const EdgeInsets.fromLTRB(16, 13, 16, 9),
                  decoration: BoxDecoration(
                    gradient: mine ? LinearGradient(colors: p.outgoingBubble, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
                    color: mine ? null : p.incomingBubble,
                    border: mine ? null : Border.all(color: p.border),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(mine ? 20 : 6),
                      bottomRight: Radius.circular(mine ? 6 : 20),
                    ),
                    boxShadow: mine ? null : p.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(alignment: Alignment.centerLeft, widthFactor: 1, child: content),
                      if (!isImage) ...[const SizedBox(height: 6), meta],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (isImage) Padding(padding: EdgeInsets.only(top: 4, left: mine ? 0 : 40), child: meta),
        ],
      ),
    );
  }
}

/// Light reference 20: active escrow order card above the conversation.
class _EscrowOrderCard extends StatelessWidget {
  const _EscrowOrderCard({required this.job, required this.title});
  final JobModel job;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HtSpace.gutter),
      child: HtCard(
        radius: 26,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: p.accentSoft, shape: BoxShape.circle),
                  child: Icon(Icons.format_paint_outlined, size: 20, color: p.accentStrong),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ACTIVE ESCROW ORDER', style: HtType.caps(p.textPrimary).copyWith(fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(title.isEmpty ? job.category : title, style: HtType.cardTitle(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                HtStatusPill(label: '${HtFormat.naira(job.agreedAmount)} Safe', tone: HtTone.neutral, icon: Icons.lock_outline_rounded),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(HtRadius.pill),
              onTap: () => context.push('/job/${job.id}'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: p.surfaceRaised, borderRadius: BorderRadius.circular(HtRadius.pill)),
                child: Row(
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: p.success, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Funds locked in HandyTrust escrow', style: HtType.small(p.textPrimary))),
                    Text('Details', style: HtType.smallStrong(p.accentStrong)),
                    Icon(Icons.arrow_forward_rounded, size: 16, color: p.accentStrong),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Artisan view: compact work order above the conversation.
class _ArtisanWorkStrip extends StatelessWidget {
  const _ArtisanWorkStrip({required this.job, required this.title});
  final JobModel job;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.ht;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HtSpace.gutter),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HtRadius.tile + 2), side: BorderSide(color: p.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(HtRadius.tile + 2),
          onTap: () => context.push('/job/${job.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text('#${HtFormat.bookingRef(job.id)} · $title', style: HtType.smallStrong(p.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (job.agreedAmount != null) Text(HtFormat.naira(job.agreedAmount), style: HtType.smallStrong(p.textPrimary)),
                Icon(Icons.chevron_right_rounded, size: 18, color: p.textMuted),
              ]),
              const SizedBox(height: 8),
              ProWorkStepper(current: ArtisanWorkLogic.workStep(job), labels: ArtisanWorkLogic.workStepLabels),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Sender-side read receipt: a clock while the write is pending, one tick
/// once the server has the message, two ticks once the recipient opened
/// the conversation. There is no "delivered" state: nothing in the data
/// model records delivery (see design/STAGE8_2_NOTIFICATION_AUDIT.md).
class _ReceiptIcon extends StatelessWidget {
  const _ReceiptIcon({required this.state, required this.color});
  final ReceiptState state;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final (icon, alpha) = switch (state) {
      ReceiptState.sending => (Icons.schedule_rounded, 0.7),
      ReceiptState.sent => (Icons.done_rounded, 0.75),
      ReceiptState.read => (Icons.done_all_rounded, 1.0),
    };
    return Semantics(
      label: ReadReceipts.label(state),
      child: Tooltip(message: ReadReceipts.label(state), child: Icon(icon, size: 14, color: color.withValues(alpha: alpha))),
    );
  }
}
