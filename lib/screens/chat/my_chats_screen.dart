import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/services/workflow_gate_service.dart';
import '../../models/job_model.dart';
import '../../models/message_model.dart';
import '../../providers/artisan_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../theme/app_design_system.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_snackbar.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/user_avatar.dart';

/// Chat inbox — role-aware. Artisans see every job they have an active
/// chat thread on (including open jobs they've messaged about but aren't
/// matched to yet — see artisanChatJobsProvider). Customers see every job
/// past 'requested' (i.e. a real artisan is attached, so a chat exists).
///
/// This split fixes a real bug found while redesigning this screen: the
/// route previously always rendered the artisan-only list regardless of
/// who was signed in, so a customer tapping the chat icon on Home landed
/// on a screen that could never show their own chats (it watched
/// artisanChatJobsProvider keyed by their own uid, which never matches any
/// job's artisanId) and saw artisan-oriented empty-state copy.
class MyChatsScreen extends ConsumerStatefulWidget {
  const MyChatsScreen({super.key});

  @override
  ConsumerState<MyChatsScreen> createState() => _MyChatsScreenState();
}

class _MyChatsScreenState extends ConsumerState<MyChatsScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProfileProvider);
    final user = userAsync.value;
    final isArtisan = user != null && user.isArtisan && !user.isCustomer;

    // MyChatsScreen is both a bottom-nav tab (artisan "Inbox" — nothing to
    // pop, no back arrow) and reachable as the standalone /my-chats route
    // (pushed from Home, Profile, My Bookings, and the Artisan Dashboard —
    // something to pop, needs one). Same canPop-conditional pattern as
    // WalletScreen/ProfileTabContent, since this screen has no real AppBar
    // to get the equivalent behavior automatically.
    final canPop = Navigator.canPop(context);
    // Dark mode on this screen specifically reads as solid near-black per
    // the Stitch dark-mode reference for Messages (confirmed canonical,
    // superseding the app's regular dark navy-slate background) — a
    // deliberate one-screen deviation, not a new global token, since no
    // other screen has a dedicated dark-mode mockup to match.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  if (canPop)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(Icons.arrow_back_rounded,
                          color: context.colors.textPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else
                    userAsync.maybeWhen(
                      data: (u) => UserAvatar(
                        photoUrl: u?.photoUrl,
                        displayName: u?.displayUsername ?? '',
                        size: 32,
                      ),
                      orElse: () => const SizedBox(width: 32, height: 32),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Inter',
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                  const NotificationBell(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: isArtisan ? 'Search customers or jobs...' : 'Search artisans or jobs...',
                    prefixIcon: Icon(Icons.search_rounded, color: context.colors.textTertiary, size: 20),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: user == null
                  ? const Center(child: CircularProgressIndicator())
                  : isArtisan
                      ? ChatListPanel(artisanId: user.uid, search: _search)
                      : CustomerChatListPanel(customerId: user.uid, search: _search),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatListPanel extends ConsumerWidget {
  final String artisanId;
  final String search;
  const ChatListPanel({super.key, required this.artisanId, required this.search});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(artisanChatJobsProvider(artisanId));

    return jobsAsync.when(
      loading: () => _ChatLoadingSkeleton(),
      error: (e, st) {
        debugPrint('[MyChats] stream error: $e');
        return _ChatLoadError(message: '$e');
      },
      data: (jobs) {
        if (jobs.isEmpty) return const _EmptyChats(isArtisan: true);

        final sorted = [...jobs]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final filtered = search.isEmpty
            ? sorted
            : sorted.where((j) => j.category.toLowerCase().contains(search)).toList();
        if (filtered.isEmpty) return const _EmptyChats(isArtisan: true);

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          itemCount: filtered.length,
          separatorBuilder: (_, i) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) =>
              _ChatListTile(job: filtered[i], viewerId: artisanId, viewerIsArtisan: true),
        );
      },
    );
  }
}

/// Customer-side chat list — every job past 'requested' (an artisan is
/// attached, so a chat thread exists). customerJobsProvider already
/// fetches everything the customer owns; this just filters to the ones a
/// chat makes sense for, client-side, same pattern as the Active/Completed
/// filtering already done in My Bookings.
class CustomerChatListPanel extends ConsumerWidget {
  final String customerId;
  final String search;
  const CustomerChatListPanel({super.key, required this.customerId, required this.search});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(customerJobsProvider(customerId));

    return jobsAsync.when(
      loading: () => _ChatLoadingSkeleton(),
      error: (e, st) {
        debugPrint('[MyChats] customer stream error: $e');
        return _ChatLoadError(message: '$e');
      },
      data: (jobs) {
        final withChat = jobs.where((j) => j.status != JobStatus.requested).toList()
          ..sort((a, b) => (b.lastUpdatedAt ?? b.createdAt).compareTo(a.lastUpdatedAt ?? a.createdAt));
        if (withChat.isEmpty) return const _EmptyChats(isArtisan: false);
        final filtered = search.isEmpty
            ? withChat
            : withChat.where((j) => j.category.toLowerCase().contains(search)).toList();
        if (filtered.isEmpty) return const _EmptyChats(isArtisan: false);

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          itemCount: filtered.length,
          separatorBuilder: (_, i) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) =>
              _ChatListTile(job: filtered[i], viewerId: customerId, viewerIsArtisan: false),
        );
      },
    );
  }
}

class _ChatLoadError extends StatelessWidget {
  final String message;
  const _ChatLoadError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: context.colors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'Could not load your chats.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pull down to retry.',
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

class _ChatListTile extends ConsumerWidget {
  final JobModel job;
  final String viewerId;
  final bool viewerIsArtisan;

  const _ChatListTile({
    required this.job,
    required this.viewerId,
    required this.viewerIsArtisan,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Other party for pair-scoping: unambiguous once matched (the job's
    // other role). For a customer viewing a still-open job with no
    // artisan assigned yet, there is no single well-defined counterpart
    // here (multiple pre-match artisans could each be messaging this
    // customer about the same job) — falling back to the customer's own
    // id degrades to "my sent + my received" within this job, which for
    // an unmatched job (viewed only by its own customer in this list) is
    // exactly the full merged preview, matching this screen's prior
    // behavior for that specific, narrower edge case rather than
    // guessing a single wrong artisan.
    final otherPartyId = viewerIsArtisan
        ? job.customerId
        : (job.artisanId.isNotEmpty ? job.artisanId : job.customerId);
    final lastMessageAsync = ref.watch(lastMessageProvider(
      ChatThreadKey(jobId: job.id, viewerId: viewerId, otherPartyId: otherPartyId),
    ));
    final unreadAsync = ref.watch(
      chatUnreadCountProvider((jobId: job.id, userId: viewerId)),
    );
    final unread = unreadAsync.value ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Phase text comes from WorkflowGateService, not a raw job.status
    // label — same source Home/My Bookings/Dashboard read. Tone/icon
    // mirror the exact same derivation _BookingCardTile (My Bookings)
    // already uses — one rule for "what color/icon does this phase get,"
    // not a second one invented for this screen.
    final step = WorkflowGateService.describeStep(job, viewerIsCustomer: !viewerIsArtisan);
    final phase = step.phase;
    final needsAction = step.primaryAction != WorkflowAction.none;
    final (badgeColor, badgeBg, badgeIcon) = needsAction
        ? (context.colors.warning, context.colors.warningSurface, Icons.hourglass_empty_rounded)
        : job.status.isActive
            ? (context.colors.primary, context.colors.primarySurface, Icons.check_circle_rounded)
            : (context.colors.textSecondary, context.colors.surfaceVariant, Icons.schedule_rounded);

    final artisan = viewerIsArtisan
        ? null
        : ref.watch(artisanProfileProvider(job.artisanId)).value;
    final title = viewerIsArtisan
        // No customer-name lookup — /users/{uid} is owner/admin-only by
        // design, so the artisan sees the job category instead of a name.
        ? 'Customer · ${job.category}'
        : (artisan?.displayName ?? job.category);
    final avatarLabel = viewerIsArtisan ? job.category : (artisan?.displayName ?? job.category);
    final avatarInitial = avatarLabel.isNotEmpty ? avatarLabel[0].toUpperCase() : 'J';

    return GestureDetector(
      onTap: () => _openChat(context, ref),
      child: AnimatedContainer(
        duration: AppAnimations.fast,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: isDark ? AppShadows.cardDark : AppShadows.card,
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: AppGradients.glassDark,
                    color: context.colors.primarySurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.colors.primary.withValues(alpha: 0.3),
                    ),
                    image: !viewerIsArtisan && artisan?.profileImageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(artisan!.profileImageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: (viewerIsArtisan || artisan?.profileImageUrl == null)
                      ? Center(
                          child: Text(
                            avatarInitial,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: context.colors.primary,
                              fontFamily: 'Inter',
                            ),
                          ),
                        )
                      : null,
                ),
                if (unread > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: context.colors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: context.colors.background, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: unread > 0
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: context.colors.textPrimary,
                            fontFamily: 'Inter',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      lastMessageAsync.maybeWhen(
                        data: (msg) => msg == null
                            ? const SizedBox.shrink()
                            : Text(
                                timeago.format(msg.createdAt, locale: 'en_short'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.colors.textTertiary,
                                  fontFamily: 'Inter',
                                ),
                              ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  AppBadge(
                    label: phase,
                    color: badgeColor,
                    backgroundColor: badgeBg,
                    icon: badgeIcon,
                  ),
                  const SizedBox(height: 5),
                  lastMessageAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (e, st) => Text(
                      'Could not load preview',
                      style: TextStyle(
                          fontSize: 12, color: context.colors.textTertiary),
                    ),
                    data: (msg) => Text(
                      _previewText(msg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: unread > 0
                            ? context.colors.textPrimary
                            : context.colors.textSecondary,
                        fontWeight: unread > 0
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: context.colors.textTertiary),
            ],
          ],
        ),
      ),
    );
  }

  String _previewText(MessageModel? msg) {
    if (msg == null) return 'No messages yet — say hello!';
    return switch (msg.type) {
      MessageType.image => '📷 Image',
      MessageType.negotiation => '💰 ${msg.text}',
      MessageType.system => '• ${msg.text}',
      MessageType.text => msg.text,
    };
  }

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    try {
      final chatId = await ref.read(chatServiceProvider).getOrCreateJobChat(
            jobId: job.id,
            customerId: job.customerId,
            artisanId: job.artisanId,
          );
      if (!context.mounted) return;
      context.push(
        '/chat/$chatId',
        extra: viewerIsArtisan
            ? {'artisanId': job.customerId, 'artisanName': 'Customer'}
            : {'artisanId': job.artisanId},
      );
    } catch (e) {
      debugPrint('[MyChats] getOrCreateJobChat failed for job ${job.id}: $e');
      if (context.mounted) {
        showErrorSnackbar(context, 'Could not open chat: $e');
      }
    }
  }
}

class _EmptyChats extends StatelessWidget {
  final bool isArtisan;
  const _EmptyChats({required this.isArtisan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.colors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 36,
                color: context.colors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No chats yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isArtisan
                  ? 'Chat with a customer from the Open Jobs Feed, or once '
                    "you're matched to a job."
                  : 'Once you hire an artisan, your conversation with them '
                    'shows up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
                fontFamily: 'Inter',
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatLoadingSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: 6,
      separatorBuilder: (_, i) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => Container(
        height: 82,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: context.colors.borderLight),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            CircleAvatar(
              radius: 25,
              backgroundColor: context.colors.shimmerBase,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 12,
                    width: 140,
                    decoration: BoxDecoration(
                      color: context.colors.shimmerBase,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 200,
                    decoration: BoxDecoration(
                      color: context.colors.shimmerBase,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}
