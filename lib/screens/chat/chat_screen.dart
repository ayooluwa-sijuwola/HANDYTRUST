import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../core/services/artisan_eligibility.dart';
import '../../core/services/workflow_gate_service.dart';
import '../../models/audit_log_model.dart';
import '../../models/job_model.dart';
import '../../models/message_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/web_content_wrapper.dart';
import '../../widgets/workflow_status_card.dart';
import 'my_chats_screen.dart';

/// AppBar title — pixel-matched to the reference (avatar, name + a small
/// green verified checkmark badge, "Verified Pro" subtitle beneath).
/// Verified status/photo can only be shown when the other party is
/// confirmably the artisan on this job (checked against job.artisanId) —
/// there's no by-id lookup for a customer's photo anywhere in this app
/// (job_booking_card.dart's own comment notes the same gap), so a customer
/// counterpart falls back to a plain initial avatar with no badge/subtitle
/// rather than a fabricated one.
class _ChatTitleHeader extends ConsumerWidget {
  final String otherUserId;
  final String otherUserName;
  final bool isOtherPartyArtisan;

  const _ChatTitleHeader({
    required this.otherUserId,
    required this.otherUserName,
    required this.isOtherPartyArtisan,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artisan = isOtherPartyArtisan
        ? ref.watch(artisanProfileProvider(otherUserId)).asData?.value
        : null;
    final verified = artisan != null && ArtisanEligibility.isReallyVerified(artisan);

    return Row(
      children: [
        UserAvatar(
          photoUrl: artisan?.profileImageUrl,
          displayName: otherUserName,
          size: 36,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      otherUserName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_circle_rounded,
                        size: 15, color: context.colors.accent),
                  ],
                ],
              ),
              if (verified)
                Text(
                  'Verified Pro',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  final String jobId;
  final String otherUserId;
  final String otherUserName;

  const ChatScreen({
    super.key,
    required this.jobId,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _showNegotiation = false;
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String get _currentUserId =>
      ref.read(authStateChangesProvider).value?.uid ?? '';

  ChatNotifierParams get _params {
    final uid = _currentUserId;
    final job = ref.read(jobStreamProvider(widget.jobId)).asData?.value;
    final role = job?.customerId == uid ? ActorRole.customer : ActorRole.artisan;
    return ChatNotifierParams(
      jobId: widget.jobId,
      senderId: uid,
      receiverId: widget.otherUserId,
      senderRole: role,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.otherUserId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Chat is not available until an artisan has been selected for this job.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
        ),
      );
    }

    final threadKey =
        ChatThreadKey(jobId: widget.jobId, viewerId: _currentUserId, otherPartyId: widget.otherUserId);
    final messages = ref.watch(messagesStreamProvider(threadKey));

    // The actual fix for "unread badge never clears" (ChatService.markAsRead
    // existed but had zero call sites anywhere in the app). Fires whenever
    // the thread emits new data — covers both "opened chat with existing
    // unread messages" and "a new message arrived while this screen is
    // already open." Best-effort: a failed mark-as-read must not disrupt
    // the chat screen itself.
    ref.listen(messagesStreamProvider(threadKey), (previous, next) {
      final list = next.asData?.value;
      if (list == null || list.isEmpty || _currentUserId.isEmpty) return;
      final hasUnread = list.any((m) => m.receiverId == _currentUserId && !m.isRead);
      if (hasUnread) {
        ref.read(chatServiceProvider).markAllAsRead(widget.jobId, viewerId: _currentUserId).catchError(
              (Object e) => debugPrint('[ChatScreen] markAllAsRead failed: $e'),
            );
      }
    });
    final jobAsync = ref.watch(jobStreamProvider(widget.jobId));
    final sending = ref.watch(chatNotifierProvider(_params));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: jobAsync.when(
          data: (job) => _ChatTitleHeader(
            otherUserId: widget.otherUserId,
            otherUserName: widget.otherUserName,
            isOtherPartyArtisan: job?.artisanId == widget.otherUserId,
          ),
          loading: () => _ChatTitleHeader(
            otherUserId: widget.otherUserId,
            otherUserName: widget.otherUserName,
            isOtherPartyArtisan: false,
          ),
          error: (e, st) => _ChatTitleHeader(
            otherUserId: widget.otherUserId,
            otherUserName: widget.otherUserName,
            isOtherPartyArtisan: false,
          ),
        ),
        actions: [
          jobAsync.when(
            data: (job) {
              if (job == null || job.status != JobStatus.inChat) {
                return const SizedBox.shrink();
              }
              // Previously this only checked job.status == inChat — no
              // awareness of the Agreement Confirmation checkpoint added
              // later, so a customer could tap through to the payment
              // screen and only find out it was blocked once they got
              // there. Now reads WorkflowGateService — the same decision
              // job_detail_screen.dart's action-buttons area reads, not a
              // second independent derivation of "is agreement required."
              if (WorkflowGateService.isAgreementRequired(job)) {
                return TextButton.icon(
                  onPressed: () => _showAgreementRequiredSheet(context),
                  icon: Icon(Icons.lock_clock_outlined,
                      size: 16, color: context.colors.textSecondary),
                  label: Text('Agreement Required',
                      style: TextStyle(color: context.colors.textSecondary)),
                );
              }
              // Same source as the agreement pill above — reads the
              // existing WorkflowGateService.isSchedulingRequired boolean
              // job_detail_screen.dart's _AppointmentSection already acts
              // on, rather than a chat-only re-derivation of "is scheduling
              // done."
              if (WorkflowGateService.isSchedulingRequired(job)) {
                return TextButton.icon(
                  onPressed: () => context.push('/job/${widget.jobId}'),
                  icon: Icon(Icons.event_outlined,
                      size: 16, color: context.colors.textSecondary),
                  label: Text('Schedule Required',
                      style: TextStyle(color: context.colors.textSecondary)),
                );
              }
              return TextButton(
                onPressed: () => context.push('/payment/${widget.jobId}'),
                child: Text('Pay Into Escrow',
                    style: TextStyle(color: context.colors.primary)),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (e, st) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: _buildBody(context, jobAsync, messages, sending),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncValue<JobModel?> jobAsync,
    AsyncValue<List<MessageModel>> messages,
    AsyncValue<void> sending,
  ) {
    final messageColumn = Column(
      children: [
        jobAsync.when(
          data: (job) => job == null
              ? const SizedBox.shrink()
              : _JobSummaryBar(
                  job: job,
                  viewerIsCustomer: job.customerId == _currentUserId,
                ),
          loading: () => const SizedBox.shrink(),
          error: (e, st) => const SizedBox.shrink(),
        ),
        Expanded(
          child: messages.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (msgs) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController.jumpTo(
                        _scrollController.position.maxScrollExtent,
                      );
                    }
                  });
                  if (msgs.isEmpty) {
                    return Center(
                      child: Text(
                        'No messages yet.\nSay hello!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.textTertiary,
                          fontSize: 14,
                          fontFamily: 'Inter',
                        ),
                      ),
                    );
                  }
                  // Date dividers — matches the Stitch chat reference's
                  // "Today, 9:41 AM"-style day grouping. Purely
                  // presentational: groups the same real message stream by
                  // calendar day, no new data/provider involved.
                  final items = <Object>[];
                  DateTime? lastDay;
                  for (final m in msgs) {
                    final day = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
                    if (lastDay == null || day != lastDay) {
                      items.add(day);
                      lastDay = day;
                    }
                    items.add(m);
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final item = items[i];
                      if (item is DateTime) {
                        return _DateDivider(date: item);
                      }
                      final message = item as MessageModel;
                      return _MessageBubble(
                        message: message,
                        isMine: message.senderId == _currentUserId,
                      );
                    },
                  );
                },
              ),
            ),
        if (_showNegotiation) _negotiationBar(),
        _inputBar(sending),
      ],
    );

    if (!context.isDesktop) {
      return WebContentWrapper(maxWidth: 720, child: messageColumn);
    }

    // Desktop 3-column layout: conversation list | message thread | job
    // summary panel. Reuses ChatListPanel/CustomerChatListPanel — the same
    // list-rendering widgets my_chats_screen.dart's own inbox uses — rather
    // than a second copy of that query/filter logic; the right panel
    // reuses WorkflowStatusCard + WorkflowGateService.describeStep, the
    // same phase/description decision every other screen in this app
    // reads. Tapping a different conversation in the left list still
    // pushes a new /chat/:jobId route (ChatListPanel's existing behavior,
    // unchanged) rather than switching in place — a disclosed, real
    // limitation, not a broken interaction.
    final uid = _currentUserId;
    final userJobAsync = jobAsync;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: context.colors.borderLight)),
            ),
            child: userJobAsync.when(
              data: (job) => job == null
                  ? const SizedBox()
                  : job.customerId == uid
                      ? CustomerChatListPanel(customerId: uid, search: '')
                      : ChatListPanel(artisanId: uid, search: ''),
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, st) => const SizedBox(),
            ),
          ),
        ),
        Expanded(child: messageColumn),
        SizedBox(
          width: 300,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: context.colors.borderLight)),
            ),
            child: jobAsync.when(
              data: (job) => job == null
                  ? const SizedBox()
                  : _JobSummaryPanel(job: job, viewerIsCustomer: job.customerId == uid),
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, st) => const SizedBox(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _negotiationBar() => Container(
        color: context.colors.warningSurface,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            const Text('₦', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Propose a price',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                final amount = double.tryParse(_amountController.text);
                if (amount == null || amount <= 0) return;
                ref
                    .read(chatNotifierProvider(_params).notifier)
                    .sendNegotiation(amount);
                _amountController.clear();
                setState(() => _showNegotiation = false);
              },
              child: const Text('Send'),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _showNegotiation = false),
            ),
          ],
        ),
      );

  Widget _inputBar(AsyncValue<void> sending) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            border: Border(top: BorderSide(color: context.colors.borderLight)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.attach_money_rounded,
                    color: context.colors.textSecondary),
                onPressed: () =>
                    setState(() => _showNegotiation = !_showNegotiation),
                tooltip: 'Propose price',
              ),
              IconButton(
                icon: Icon(Icons.image_outlined,
                    color: context.colors.textSecondary),
                onPressed: sending.isLoading ? null : _pickAndSendImage,
                tooltip: 'Send image',
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Type a message…',
                    filled: true,
                    fillColor: context.colors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  minLines: 1,
                  maxLines: 4,
                ),
              ),
              const SizedBox(width: 8),
              sending.isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  // Solid black circular send button — matches the Stitch
                  // chat reference's "commitment" send affordance, same
                  // ink/onInk fixed-tone pattern as CommitButton elsewhere.
                  : Material(
                      color: context.colors.ink,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sendText,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(Icons.arrow_upward_rounded,
                              size: 20, color: context.colors.onInk),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      );

  void _showAgreementRequiredSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_clock_outlined,
                    color: context.colors.textSecondary),
                const SizedBox(width: 10),
                Text(
                  'Agreement Required',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Confirm the job terms before proceeding to payment.',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                context.push('/job/${widget.jobId}');
              },
              child: const Text('View Agreement'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Continue Negotiation'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await ref.read(chatNotifierProvider(_params).notifier).sendText(text);
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final raw = await picked.readAsBytes();
    Uint8List bytes = raw;
    if (raw.lengthInBytes > 500 * 1024) {
      final compressed = await FlutterImageCompress.compressWithList(
        raw,
        quality: 70,
      );
      bytes = Uint8List.fromList(compressed);
    }
    await ref
        .read(chatNotifierProvider(_params).notifier)
        .sendImageBytes(bytes);
  }
}

/// Sticky job-summary strip above the message list — title, workflow
/// phase, price, and an expandable "View Job Details" link. Reads
/// WorkflowGateService for the phase text, same source every other
/// redesigned screen this pass uses — never job.status directly.
/// Desktop right-panel counterpart to [_JobSummaryBar] — a fuller vertical
/// job summary instead of a compact horizontal bar, built from the same
/// WorkflowGateService.describeStep decision and the same WorkflowStatusCard
/// every other screen in this app renders job phase/status through.
class _JobSummaryPanel extends StatelessWidget {
  final JobModel job;
  final bool viewerIsCustomer;

  const _JobSummaryPanel({required this.job, required this.viewerIsCustomer});

  @override
  Widget build(BuildContext context) {
    final step = WorkflowGateService.describeStep(job, viewerIsCustomer: viewerIsCustomer);
    final price = job.agreedAmount ?? job.budgetMin;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Job Summary',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'Inter',
              color: context.colors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            job.category,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter',
              color: context.colors.textPrimary,
            ),
          ),
          if (price != null) ...[
            const SizedBox(height: 4),
            Text(
              '₦${price.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
                color: context.colors.primary,
              ),
            ),
          ],
          const SizedBox(height: 18),
          WorkflowStatusCard(
            phase: step.phase,
            description: step.description,
            waitingOn: switch (step.waitingOn) {
              WorkflowActor.customer => 'the customer',
              WorkflowActor.artisan => 'the artisan',
              WorkflowActor.system => 'HandyTrust',
              null => null,
            },
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () => context.push('/job/${job.id}'),
            child: const Text('View Full Job Details'),
          ),
        ],
      ),
    );
  }
}

class _JobSummaryBar extends StatefulWidget {
  final JobModel job;
  final bool viewerIsCustomer;

  const _JobSummaryBar({required this.job, required this.viewerIsCustomer});

  @override
  State<_JobSummaryBar> createState() => _JobSummaryBarState();
}

class _JobSummaryBarState extends State<_JobSummaryBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final phase =
        WorkflowGateService.describeStep(job, viewerIsCustomer: widget.viewerIsCustomer).phase;
    final price = job.agreedAmount ?? job.budgetMin;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(bottom: BorderSide(color: context.colors.borderLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.category,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              if (price != null)
                Text(
                  '₦${price.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                    color: context.colors.textPrimary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              AppBadge(
                label: phase,
                color: context.colors.primary,
                backgroundColor: context.colors.primarySurface,
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View Job Details',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                        color: context.colors.textSecondary,
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18,
                      color: context.colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Text(
              job.description,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.push('/job/${job.id}'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text('Open Full Job Details'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// "Today" / "Yesterday" / weekday-or-date divider between message groups —
// matches the Stitch chat reference's date-grouped thread.
class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (date == today) return 'Today';
    if (date == yesterday) return 'Yesterday';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    // Within the last week, weekday name reads better than a full date.
    if (today.difference(date).inDays < 7) return weekdays[date.weekday - 1];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: context.colors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              _label(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ),
      );
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;

  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    if (message.type == MessageType.system) {
      return _systemBubble(context);
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMine ? context.colors.bubbleSent : context.colors.bubbleReceived,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.type == MessageType.image && message.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  message.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, err, stack) => Icon(
                      Icons.broken_image_outlined,
                      color: context.colors.textTertiary),
                ),
              )
            else if (message.type == MessageType.negotiation)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attach_money_rounded,
                      size: 16,
                      color: isMine ? Colors.white70 : context.colors.warning),
                  const SizedBox(width: 4),
                  Text(
                    message.text,
                    style: TextStyle(
                      color: isMine ? Colors.white : context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              )
            else
              Text(
                message.text,
                style: TextStyle(
                  color: isMine ? Colors.white : context.colors.textPrimary,
                  fontSize: 14,
                  fontFamily: 'Inter',
                ),
              ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: isMine ? Colors.white60 : context.colors.textTertiary,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _systemBubble(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: context.colors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            message.text,
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textSecondary,
              fontFamily: 'Inter',
            ),
          ),
        ),
      );

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
