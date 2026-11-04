import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/chat_service.dart';
import '../core/services/job_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/storage_service.dart';
import '../core/utils/safe_firestore.dart';
import '../models/audit_log_model.dart';
import '../models/job_model.dart';
import '../models/job_mutation_context.dart';
import '../models/message_model.dart';
import 'escrow_provider.dart';
import 'job_service_provider.dart';

final chatServiceProvider = Provider<ChatService>(
  (ref) => ChatService(FirebaseFirestore.instance, NotificationService(FirebaseFirestore.instance)),
);

/// Live total unread messages across all jobs for a user (collectionGroup).
final messagesUnreadCountProvider = StreamProvider.family<int, String>((ref, userId) {
  try {
    return FirebaseFirestore.instance
        .collectionGroup('messages')
        .where('receiverId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length)
        .handleError((e) {
      debugPrint('[chat_provider] messagesUnreadCount stream error: $e');
    });
  } catch (e) {
    debugPrint('[chat_provider] messagesUnreadCount failed to create stream: $e');
    return Stream.value(0);
  }
});

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

/// Live unread count for [userId] in a job's thread.
final chatUnreadCountProvider = StreamProvider.family<int,
    ({String jobId, String userId})>((ref, key) {
  return ref.watch(chatServiceProvider).watchUnreadCount(key.jobId, key.userId);
});

/// Distinct job IDs this artisan has personally sent at least one message
/// on — captures pre-match "interested" chats (started from the Open Jobs
/// Feed) that may never result in a match. Matched jobs are already
/// covered by [artisanJobsProvider]; this only adds jobs not yet matched
/// to this artisan. A single equality filter on a collectionGroup query
/// needs no composite index.
final _artisanMessagedJobIdsProvider =
    StreamProvider.family<Set<String>, String>((ref, artisanId) {
  return safeStream(
    FirebaseFirestore.instance
        .collectionGroup('messages')
        .where('senderId', isEqualTo: artisanId),
    (d) => d.data()['jobId'] as String? ?? '',
    debugLabel: 'artisanMessagedJobIds:$artisanId',
  ).map((ids) => ids.where((id) => id.isNotEmpty).toSet());
});

/// Fetches job docs for a fixed set of ids — used to hydrate pre-match
/// chat jobs not already covered by [artisanJobsProvider]. Keyed by a
/// sorted, joined id string so Riverpod caches repeat lookups for the
/// same set instead of refetching on every snapshot tick (same pattern as
/// admin_dashboard_screen.dart's `_jobPeopleNamesProvider`).
final _jobsByIdsProvider =
    FutureProvider.family<List<JobModel>, String>((ref, idsKey) async {
  if (idsKey.isEmpty) return const [];
  final ids = idsKey.split(',');
  final snap = await FirebaseFirestore.instance
      .collection('jobs')
      .where(FieldPath.documentId, whereIn: ids)
      .get();
  return snap.docs.map((d) => JobModel.fromJson({...d.data(), 'id': d.id})).toList();
});

/// Every job this artisan has a chat thread on: matched jobs (post-
/// acceptance, via [artisanJobsProvider]) plus any still-open job they
/// personally messaged about pre-match. Combined client-side from two
/// independent signals — matched jobs come from `jobs.artisanId`,
/// pre-match chats from `messages.senderId` — rather than one query,
/// because nothing in this data model links them otherwise. Degrades
/// gracefully: if the pre-match signal errors or is still loading, the
/// matched-jobs list is shown on its own rather than blocking the whole
/// screen on a secondary signal.
final artisanChatJobsProvider =
    Provider.family<AsyncValue<List<JobModel>>, String>((ref, artisanId) {
  final matchedAsync = ref.watch(artisanJobsProvider(artisanId));

  return matchedAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (matched) {
      final messagedIdsAsync = ref.watch(_artisanMessagedJobIdsProvider(artisanId));
      return messagedIdsAsync.when(
        loading: () => AsyncValue.data(matched),
        error: (_, _) => AsyncValue.data(matched),
        data: (messagedIds) {
          final matchedIds = matched.map((j) => j.id).toSet();
          final extraIds = messagedIds.difference(matchedIds);
          if (extraIds.isEmpty) return AsyncValue.data(matched);

          final extraKey = (extraIds.toList()..sort()).join(',');
          final extraAsync = ref.watch(_jobsByIdsProvider(extraKey));
          return extraAsync.when(
            loading: () => AsyncValue.data(matched),
            error: (_, _) => AsyncValue.data(matched),
            data: (extraJobs) => AsyncValue.data([...matched, ...extraJobs]),
          );
        },
      );
    },
  );
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
