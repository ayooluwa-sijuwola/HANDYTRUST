import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/chat_service.dart';
import '../core/services/conversation_logic.dart';
import '../core/services/job_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/storage_service.dart';
import '../models/audit_log_model.dart';
import '../models/job_model.dart';
import '../models/job_mutation_context.dart';
import '../models/message_model.dart';
import 'artisan_provider.dart';
import 'escrow_provider.dart';
import 'quote_provider.dart';
import 'job_service_provider.dart';

final chatServiceProvider = Provider<ChatService>(
  (ref) => ChatService(FirebaseFirestore.instance, NotificationService(FirebaseFirestore.instance)),
);

/// Real-time message stream for a job, scoped to one specific counterpart
/// — see ChatService.messagesStream's doc comment for why an unscoped
/// query is unsafe/incorrect both pre- and post-match.
final messagesStreamProvider =
    StreamProvider.family<List<MessageModel>, ChatThreadKey>((ref, key) {
  return ref.watch(chatServiceProvider).messagesStream(
        key.jobId,
        viewerId: key.viewerId,
        otherPartyId: key.otherPartyId,
      );
});

class ChatThreadKey {
  final String jobId;
  final String viewerId;
  final String otherPartyId;
  const ChatThreadKey({required this.jobId, required this.viewerId, required this.otherPartyId});

  @override
  bool operator ==(Object other) =>
      other is ChatThreadKey &&
      other.jobId == jobId &&
      other.viewerId == viewerId &&
      other.otherPartyId == otherPartyId;

  @override
  int get hashCode => Object.hash(jobId, viewerId, otherPartyId);
}

/// One-shot "does this job have any chat messages at all" check — drives
/// the admin job detail sheet's "Chat Exists" indicator. Deliberately a
/// single bounded read (not a stream) since the admin list doesn't need
/// this to update live, and a stream-per-job-tile would mean one
/// always-on listener per row in the Jobs tab.
final jobHasChatProvider = FutureProvider.family<bool, String>((ref, jobId) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('jobs')
        .doc(jobId)
        .collection('messages')
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  } catch (e) {
    debugPrint('[jobHasChatProvider] check failed for $jobId: $e');
    return false;
  }
});

/// Most recent message between two specific parties on a job's thread —
/// drives the "My Chats" preview.
final lastMessageProvider =
    StreamProvider.family<MessageModel?, ChatThreadKey>((ref, key) {
  return ref.watch(chatServiceProvider).watchLastMessage(
        key.jobId,
        viewerId: key.viewerId,
        otherPartyId: key.otherPartyId,
      );
});

// ─── Conversations (Stage 8.2) ──────────────────────────────────────────────
// Conversation discovery and unread totals use per-job, rules-safe queries.
// The previous collectionGroup('messages') queries are denied by
// firestore.rules (no recursive `{path=**}/messages` rule; verified on the
// emulator), so header badges always read 0 and artisans' pre-booking
// threads never appeared.

/// Everyone [viewerId] has exchanged messages with on one job.
final jobCounterpartsProvider = StreamProvider.family<Set<String>, ({String jobId, String viewerId})>(
  (ref, k) => ref.watch(chatServiceProvider).watchCounterparts(k.jobId, viewerId: k.viewerId),
);

/// Unread messages in ONE conversation.
final pairUnreadCountProvider = StreamProvider.family<int, ChatThreadKey>(
  (ref, k) => ref.watch(chatServiceProvider).watchPairUnreadCount(k.jobId, viewerId: k.viewerId, otherPartyId: k.otherPartyId),
);

Map<String, Set<String>> _counterpartsFor(Ref ref, Iterable<JobModel> jobs, String uid) => {
      for (final j in jobs) j.id: ref.watch(jobCounterpartsProvider((jobId: j.id, viewerId: uid))).asData?.value ?? const <String>{},
    };

bool _needsDiscovery(JobModel j) =>
    j.status == JobStatus.requested || j.status == JobStatus.cancelled || j.status == JobStatus.expired;

/// The customer's conversations (viewer = the job's customer).
final customerConversationsProvider = Provider.family<AsyncValue<List<ConversationRef>>, String>((ref, uid) {
  return ref.watch(customerJobsProvider(uid)).whenData((jobs) {
    final counterparts = _counterpartsFor(ref, jobs.where(_needsDiscovery), uid);
    return ConversationLogic.forCustomer(uid, jobs, counterparts);
  });
});

/// The artisan's conversations (viewer = the artisan): assigned jobs, plus
/// open jobs in their feed where they have exchanged messages.
final artisanConversationsProvider = Provider.family<AsyncValue<List<ConversationRef>>, String>((ref, uid) {
  final category = ref.watch(artisanProfileProvider(uid)).asData?.value?.category;
  final open = (category == null || category.isEmpty)
      ? const <JobModel>[]
      : ref.watch(openJobsFeedProvider(category)).asData?.value ?? const <JobModel>[];
  return ref.watch(artisanJobsProvider(uid)).whenData((assigned) {
    final counterparts = _counterpartsFor(ref, [...assigned.where(_needsDiscovery), ...open], uid);
    return ConversationLogic.forArtisan(uid, assigned, open, counterparts);
  });
});

/// Conversations with their last message and unread count, newest first.
/// Role-separated: [asArtisan] picks which side of the user's account.
final conversationViewsProvider = Provider.family<AsyncValue<List<ConversationView>>, ({String uid, bool asArtisan})>((ref, k) {
  final refs = k.asArtisan ? ref.watch(artisanConversationsProvider(k.uid)) : ref.watch(customerConversationsProvider(k.uid));
  return refs.whenData((list) => ConversationLogic.sorted([
        for (final c in list)
          ConversationView(
            ref: c,
            last: ref.watch(lastMessageProvider(ChatThreadKey(jobId: c.job.id, viewerId: c.viewerId, otherPartyId: c.otherPartyId))).asData?.value,
            unread: ref.watch(pairUnreadCountProvider(ChatThreadKey(jobId: c.job.id, viewerId: c.viewerId, otherPartyId: c.otherPartyId))).asData?.value ?? 0,
          ),
      ]));
});

/// Total unread messages for one side of the account (header badge).
final unreadMessagesTotalProvider = Provider.family<int, ({String uid, bool asArtisan})>((ref, k) {
  final refs = (k.asArtisan ? ref.watch(artisanConversationsProvider(k.uid)) : ref.watch(customerConversationsProvider(k.uid))).asData?.value ?? const [];
  return ConversationLogic.totalUnread([
    for (final c in refs)
      ref.watch(pairUnreadCountProvider(ChatThreadKey(jobId: c.job.id, viewerId: c.viewerId, otherPartyId: c.otherPartyId))).asData?.value ?? 0,
  ]);
});

/// Send-state notifier — tracks in-flight send operations.
///
/// [sendNegotiation] routes through [JobService], which writes the negotiation
/// message AND updates job.agreedAmount atomically in a single Firestore
/// transaction. No split-write race condition is possible.
class ChatNotifier extends StateNotifier<AsyncValue<void>> {
  final ChatService _chat;
  final StorageService _storage;
  final JobService _jobService;
  final String jobId;
  final String senderId;
  final String receiverId;
  final ActorRole senderRole;

  ChatNotifier({
    required ChatService chat,
    required StorageService storage,
    required JobService jobService,
    required this.jobId,
    required this.senderId,
    required this.receiverId,
    required this.senderRole,
  })  : _chat = chat,
        _storage = storage,
        _jobService = jobService,
        super(const AsyncData(null));

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _chat.sendText(
          jobId: jobId,
          senderId: senderId,
          receiverId: receiverId,
          text: text.trim(),
        ));
  }

  Future<void> sendImageBytes(Uint8List bytes) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final url = await _storage.uploadJobImageBytes(
        jobId: jobId,
        userId: senderId,
        index: DateTime.now().millisecondsSinceEpoch,
        bytes: bytes,
      );
      await _chat.sendImage(
        jobId: jobId,
        senderId: senderId,
        receiverId: receiverId,
        imageUrl: url,
      );
    });
  }

  /// Atomically sends a negotiation message and records [amount] on the job.
  /// Delegates entirely to [JobService.sendNegotiation] — one transaction,
  /// all three writes (message, agreedAmount, audit log) commit together or
  /// are all rolled back.
  Future<void> sendNegotiation(double amount) async {
    state = const AsyncLoading();
    final ctx = JobMutationContext(
      actorId: senderId,
      actorRole: senderRole,
      actionType: JobActionType.negotiationProposal,
    );
    state = await AsyncValue.guard(
        () => _jobService.sendNegotiation(ctx, jobId, receiverId, amount));
  }
}

final storageServiceProvider = Provider<StorageService>(
  (_) => StorageService(),
);

final chatNotifierProvider = StateNotifierProvider.family<ChatNotifier,
    AsyncValue<void>, ChatNotifierParams>((ref, params) {
  return ChatNotifier(
    chat: ref.watch(chatServiceProvider),
    storage: ref.watch(storageServiceProvider),
    jobService: ref.watch(jobServiceProvider),
    jobId: params.jobId,
    senderId: params.senderId,
    receiverId: params.receiverId,
    senderRole: params.senderRole,
  );
});

class ChatNotifierParams {
  final String jobId;
  final String senderId;
  final String receiverId;
  final ActorRole senderRole;

  const ChatNotifierParams({
    required this.jobId,
    required this.senderId,
    required this.receiverId,
    required this.senderRole,
  });

  @override
  bool operator ==(Object other) =>
      other is ChatNotifierParams &&
      other.jobId == jobId &&
      other.senderId == senderId &&
      other.receiverId == receiverId &&
      other.senderRole == senderRole;

  @override
  int get hashCode => Object.hash(jobId, senderId, receiverId, senderRole);
}

/// Stage 8.2: incoming unread messages in one conversation, with whether
/// the snapshot is server-confirmed (F-3). autoDispose (F-4): the Firestore
/// listener ends as soon as nothing watches it, e.g. after sign-out.
final incomingUnreadProvider = StreamProvider.autoDispose.family<IncomingSnapshot, ChatThreadKey>(
  (ref, k) => ref.watch(chatServiceProvider).watchIncomingForAck(k.jobId, viewerId: k.viewerId, otherPartyId: k.otherPartyId),
);

/// Stage 8.2 delivery receipts. Watched at the app root while signed in:
/// for every conversation on BOTH sides of the account, messages that
/// reached this device from the server get `deliveredAt` stamped once.
/// Only the recipient's own app can do this (firestore.rules), so
/// "Delivered" means the recipient's device really has the message.
/// - F-3: cache-only snapshots never produce a receipt.
/// - F-4: autoDispose, so when the root stops watching (sign-out) every
///   per-conversation listener of that account is cancelled instead of
///   running on under the next account.
final deliveryAckProvider = Provider.autoDispose.family<void, String>((ref, uid) {
  final refs = [
    ...?ref.watch(customerConversationsProvider(uid)).asData?.value,
    ...?ref.watch(artisanConversationsProvider(uid)).asData?.value,
  ];
  final service = ref.watch(chatServiceProvider);
  for (final c in refs) {
    final key = ChatThreadKey(jobId: c.job.id, viewerId: c.viewerId, otherPartyId: c.otherPartyId);
    ref.listen<AsyncValue<IncomingSnapshot>>(incomingUnreadProvider(key), (_, next) {
      final snap = next.asData?.value;
      if (snap == null) return;
      final todo = DeliveryReceipts.toAcknowledge(snap.messages, viewerId: uid, fromCache: snap.fromCache);
      if (todo.isEmpty) return;
      service.markDelivered(c.job.id, todo.map((m) => m.id)).catchError((Object e) {
        debugPrint('[chat_provider] markDelivered failed for ${c.job.id}: $e');
        return 0;
      });
    }, fireImmediately: true);
  }
});
