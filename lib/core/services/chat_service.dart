import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../models/message_model.dart';
import 'notification_service.dart';

class ChatService {
  final FirebaseFirestore _db;

  /// The optional NotificationService parameter is kept (unused) so existing
  /// call sites compile; message notifications are server-generated since
  /// Stage 6 (onMessageCreated).
  // ignore: avoid_unused_constructor_parameters
  ChatService(this._db, [NotificationService? notifications]);

  CollectionReference<Map<String, dynamic>> _messages(String jobId) =>
      _db.collection('jobs').doc(jobId).collection('messages');

  static MessageModel _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      MessageModel.fromJson({...d.data(), 'id': d.id}).withPending(d.metadata.hasPendingWrites);

  /// In-flight read-marking batches, so repeated snapshots can't send
  /// duplicate read writes for the same conversation (Stage 8.2).
  final Set<String> _markingRead = {};

  // Firestore evaluates security-rule `read`/`list` operations against a
  // query's own `where` clauses, not per-returned-document — a query with
  // no `where` clause at all is only provably safe under firestore.rules'
  // messages read rule when the viewer is unconditionally a job party
  // (isJobParty is a static job-doc check). For a pre-match artisan (not
  // yet job.artisanId), that's never true, and an unfiltered query is
  // rejected outright with permission-denied even though that artisan's
  // own individual messages ARE readable — confirmed empirically against
  // the real rules via the Firestore emulator during this investigation.
  // Separately, an unfiltered query for the CUSTOMER (who is always
  // isJobParty for their own job) succeeds but returns every pre-match
  // artisan's separate conversation merged into one thread, since nothing
  // scopes it to one specific counterpart.
  //
  // Fixing both: every message in a job's thread is exactly between two
  // parties (senderId, receiverId), so the full, correctly-scoped thread
  // between [viewerId] and [otherPartyId] is the union of "I sent it to
  // them" and "they sent it to me" — two compound-equality queries, each
  // independently provable safe under the rules (senderId==uid or
  // receiverId==uid), merged and re-sorted client-side. This works
  // identically pre- and post-match, so there is one code path, not a
  // pre-/post-match branch.
  Stream<List<MessageModel>> _pairStream(
    String jobId, {
    required String viewerId,
    required String otherPartyId,
  }) {
    final controller = StreamController<List<MessageModel>>.broadcast();
    var sent = <MessageModel>[];
    var received = <MessageModel>[];
    var haveSent = false;
    var haveReceived = false;

    void emit() {
      if (!haveSent || !haveReceived) return;
      final combined = [...sent, ...received]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      controller.add(combined);
    }

    final subs = <StreamSubscription>[];
    subs.add(
      _messages(jobId)
          .where('senderId', isEqualTo: viewerId)
          .where('receiverId', isEqualTo: otherPartyId)
          // Stage 8.2: metadata changes so a message flips from "Sending"
          // to "Sent" only once the server has acknowledged the write.
          .snapshots(includeMetadataChanges: true)
          .listen((s) {
        sent = s.docs.map(_fromDoc).toList();
        haveSent = true;
        emit();
      }, onError: (Object e) {
        debugPrint('[ChatService] _pairStream (sent) error for job $jobId: $e');
        haveSent = true;
        emit();
      }),
    );
    subs.add(
      _messages(jobId)
          .where('senderId', isEqualTo: otherPartyId)
          .where('receiverId', isEqualTo: viewerId)
          .snapshots()
          .listen((s) {
        received = s.docs.map(_fromDoc).toList();
        haveReceived = true;
        emit();
      }, onError: (Object e) {
        debugPrint('[ChatService] _pairStream (received) error for job $jobId: $e');
        haveReceived = true;
        emit();
      }),
    );

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return controller.stream;
  }

  /// Real-time message stream between [viewerId] and [otherPartyId] on a
  /// job's thread — ordered oldest-first. See [_pairStream] for why this
  /// must be two compound-scoped queries rather than one unfiltered one.
  Stream<List<MessageModel>> messagesStream(
    String jobId, {
    required String viewerId,
    required String otherPartyId,
  }) =>
      _pairStream(jobId, viewerId: viewerId, otherPartyId: otherPartyId);

  /// Confirms a job-linked chat thread is usable and returns its identifier
  /// for navigation. There is no separate "chat" document in this app's
  /// data model — a job's `messages` subcollection IS its chat thread,
  /// already keyed 1:1 by jobId, so there is nothing to create and no
  /// duplicate-chat risk to guard against. This exists purely to fail
  /// fast and clearly — missing/deleted job, mismatched customer — before
  /// the UI navigates to a chat screen that would otherwise show a
  /// confusing empty state. Read-only, so trivially race-safe.
  Future<String> getOrCreateJobChat({
    required String jobId,
    required String customerId,
    required String artisanId,
  }) async {
    final snap = await _db.collection('jobs').doc(jobId).get();
    if (!snap.exists) {
      throw StateError('This job no longer exists.');
    }
    final data = snap.data()!;
    if ((data['customerId'] as String? ?? '') != customerId) {
      throw StateError('This chat is no longer valid for this job.');
    }
    return jobId;
  }

  /// Most recent message between [viewerId] and [otherPartyId] on a job's
  /// thread, or null for an empty thread — drives the "My Chats" list
  /// preview. Same pair-scoping as [messagesStream] and for the same
  /// reason (an unfiltered query is rejected outright for a pre-match
  /// artisan, confirmed against the real rules via the emulator).
  Stream<MessageModel?> watchLastMessage(
    String jobId, {
    required String viewerId,
    required String otherPartyId,
  }) =>
      _pairStream(jobId, viewerId: viewerId, otherPartyId: otherPartyId)
          .map((list) => list.isEmpty ? null : list.last);

  // Stage 6 (HT-015): the "new message" notification is generated
  // server-side by the onMessageCreated trigger (functions/index.js).

  Future<void> sendText({
    required String jobId,
    required String senderId,
    required String receiverId,
    required String text,
  }) async {
    final id = _messages(jobId).doc().id;
    final msg = MessageModel(
      id: id,
      jobId: jobId,
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      type: MessageType.text,
      createdAt: DateTime.now(),
    );
    await _messages(jobId).doc(id).set(msg.toJson());
  }

  Future<void> sendImage({
    required String jobId,
    required String senderId,
    required String receiverId,
    required String imageUrl,
  }) async {
    final id = _messages(jobId).doc().id;
    final msg = MessageModel(
      id: id,
      jobId: jobId,
      senderId: senderId,
      receiverId: receiverId,
      text: '📷 Image',
      type: MessageType.image,
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
    );
    await _messages(jobId).doc(id).set(msg.toJson());
  }

  Future<void> sendNegotiation({
    required String jobId,
    required String senderId,
    required String receiverId,
    required double proposedAmount,
  }) async {
    final id = _messages(jobId).doc().id;
    final msg = MessageModel(
      id: id,
      jobId: jobId,
      senderId: senderId,
      receiverId: receiverId,
      text: '💰 Price proposal: ₦${proposedAmount.toStringAsFixed(0)}',
      type: MessageType.negotiation,
      proposedAmount: proposedAmount,
      createdAt: DateTime.now(),
    );
    await _messages(jobId).doc(id).set(msg.toJson());
  }

  Future<void> sendSystemMessage({
    required String jobId,
    required String text,
  }) async {
    final id = _messages(jobId).doc().id;
    final msg = MessageModel(
      id: id,
      jobId: jobId,
      senderId: 'system',
      receiverId: 'all',
      text: text,
      type: MessageType.system,
      createdAt: DateTime.now(),
    );
    await _messages(jobId).doc(id).set(msg.toJson());
  }

  Future<void> markAsRead(String jobId, String messageId) =>
      _messages(jobId).doc(messageId).update({'isRead': true});

  /// Marks every unread message addressed to [viewerId] in this job's
  /// thread as read — the actual fix for the "unread badge never clears"
  /// bug: [markAsRead] above already existed and is correctly shaped
  /// against firestore.rules' `messages` update rule, but had zero call
  /// sites anywhere in the app (confirmed by an exhaustive search during
  /// this investigation) — nothing ever invoked it. Called from
  /// ChatScreen when a conversation is opened/new messages arrive.
  Future<void> markAllAsRead(String jobId, {required String viewerId, String? otherPartyId}) async {
    // Stage 8.2: scoped to ONE conversation. On an open job several
    // artisans can message the same customer; marking by receiver alone
    // cleared the other artisans' unread messages too.
    final key = '$jobId|$viewerId|${otherPartyId ?? '*'}';
    if (!_markingRead.add(key)) return;
    try {
      var q = _messages(jobId).where('receiverId', isEqualTo: viewerId);
      if (otherPartyId != null) q = q.where('senderId', isEqualTo: otherPartyId);
      final snap = await q.where('isRead', isEqualTo: false).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } finally {
      _markingRead.remove(key);
    }
  }

  /// Live unread count in ONE conversation (messages from [otherPartyId]
  /// to [viewerId] not yet read). Per-job, rules-safe query: the
  /// collection-group alternative is denied by firestore.rules.
  Stream<int> watchPairUnreadCount(String jobId, {required String viewerId, required String otherPartyId}) => _messages(jobId)
      .where('receiverId', isEqualTo: viewerId)
      .where('senderId', isEqualTo: otherPartyId)
      .where('isRead', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.length)
      .transform(StreamTransformer<int, int>.fromHandlers(handleError: (Object e, StackTrace st, sink) {
        debugPrint('[ChatService] watchPairUnreadCount error for job $jobId: $e');
        sink.addError(e, st);
      }));

  /// Everyone [viewerId] has exchanged messages with on a job, for jobs the
  /// viewer may query by sender/receiver (job parties, and pre-booking
  /// artisans for their own messages). Two rules-safe queries, merged.
  Stream<Set<String>> watchCounterparts(String jobId, {required String viewerId}) {
    final controller = StreamController<Set<String>>.broadcast();
    var fromMe = <String>{};
    var toMe = <String>{};
    var haveFrom = false, haveTo = false;
    void emit() {
      if (haveFrom && haveTo) controller.add({...fromMe, ...toMe}..remove(viewerId)..remove(''));
    }
    final subs = <StreamSubscription>[
      _messages(jobId).where('senderId', isEqualTo: viewerId).snapshots().listen((s) {
        fromMe = s.docs.map((d) => d.data()['receiverId'] as String? ?? '').toSet();
        haveFrom = true;
        emit();
      }, onError: controller.addError),
      _messages(jobId).where('receiverId', isEqualTo: viewerId).snapshots().listen((s) {
        toMe = s.docs.map((d) => d.data()['senderId'] as String? ?? '').toSet();
        haveTo = true;
        emit();
      }, onError: controller.addError),
    ];
    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return controller.stream;
  }

  Future<int> unreadCount(String jobId, String userId) async {
    final snap = await _messages(jobId)
        .where('receiverId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .count()
        .get();
    return snap.count ?? 0;
  }
}
