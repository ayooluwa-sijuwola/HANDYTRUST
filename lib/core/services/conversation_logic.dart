import '../../models/job_model.dart';
import '../../models/message_model.dart';

/// One conversation: a job plus the two people talking about it. A job's
/// `messages` subcollection can hold several conversations before booking
/// (each interested artisan with the customer), so a conversation is
/// identified by (job, viewer, other party), never by the job alone.
class ConversationRef {
  const ConversationRef({required this.job, required this.viewerId, required this.otherPartyId});
  final JobModel job;
  final String viewerId;
  final String otherPartyId;

  bool get viewerIsCustomer => job.customerId == viewerId;
  String get id => '${job.id}|$viewerId|$otherPartyId';

  @override
  bool operator ==(Object other) => other is ConversationRef && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// A conversation with its live preview data, for the chat lists.
class ConversationView {
  const ConversationView({required this.ref, this.last, this.unread = 0});
  final ConversationRef ref;
  final MessageModel? last;
  final int unread;
  DateTime get activityAt => last?.createdAt ?? ref.job.createdAt;
}

/// Pure conversation rules (Stage 8.2). No Firestore, no BuildContext —
/// tested in test/conversation_logic_test.dart.
abstract final class ConversationLogic {
  /// Jobs whose chat is closed for good and that only appear if messages
  /// were actually exchanged.
  static bool _closed(JobModel j) => j.status == JobStatus.cancelled || j.status == JobStatus.expired;

  /// Customer side (role-separated: the viewer is the job's customer).
  /// - Booked jobs: the conversation with the assigned artisan.
  /// - Open jobs: one conversation per artisan who has exchanged messages
  ///   with the customer ([counterparts], from per-job rules-safe queries).
  static List<ConversationRef> forCustomer(String uid, Iterable<JobModel> jobs, Map<String, Set<String>> counterparts) {
    final out = <ConversationRef>[];
    for (final j in jobs) {
      if (j.customerId != uid) continue;
      final talked = counterparts[j.id] ?? const <String>{};
      if (j.status == JobStatus.requested) {
        for (final other in talked) {
          if (other.isNotEmpty && other != uid) out.add(ConversationRef(job: j, viewerId: uid, otherPartyId: other));
        }
      } else if (j.artisanId.isNotEmpty) {
        if (_closed(j) && !talked.contains(j.artisanId)) continue;
        out.add(ConversationRef(job: j, viewerId: uid, otherPartyId: j.artisanId));
      }
    }
    return out;
  }

  /// Artisan side (role-separated: the viewer is the artisan).
  /// - Jobs assigned to the artisan: the conversation with the customer.
  /// - Open jobs in the artisan's feed where they have exchanged messages
  ///   before booking.
  static List<ConversationRef> forArtisan(String uid, Iterable<JobModel> assigned, Iterable<JobModel> open, Map<String, Set<String>> counterparts) {
    final out = <ConversationRef>[];
    final seen = <String>{};
    for (final j in assigned) {
      if (j.artisanId != uid || j.customerId.isEmpty || j.customerId == uid) continue;
      final talked = counterparts[j.id] ?? const <String>{};
      if (_closed(j) && !talked.contains(j.customerId)) continue;
      if (seen.add(j.id)) out.add(ConversationRef(job: j, viewerId: uid, otherPartyId: j.customerId));
    }
    for (final j in open) {
      if (j.status != JobStatus.requested || j.customerId.isEmpty || j.customerId == uid) continue;
      final talked = counterparts[j.id] ?? const <String>{};
      if (!talked.contains(j.customerId)) continue;
      if (seen.add(j.id)) out.add(ConversationRef(job: j, viewerId: uid, otherPartyId: j.customerId));
    }
    return out;
  }

  /// Most recent activity first.
  static List<ConversationView> sorted(Iterable<ConversationView> items) =>
      items.toList()..sort((a, b) => b.activityAt.compareTo(a.activityAt));

  /// Text search over what the list actually shows: job description,
  /// category, area, the other party's name, and the last message text.
  static List<ConversationView> search(Iterable<ConversationView> items, String query, {String Function(ConversationRef)? nameOf}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items.toList();
    return items.where((v) {
      final j = v.ref.job;
      final hay = [j.description, j.category, j.areaLabel ?? '', nameOf?.call(v.ref) ?? '', v.last?.text ?? ''].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  static int totalUnread(Iterable<int> counts) => counts.fold(0, (a, b) => a + b);
}

/// What the sender sees under their own message (Stage 8.2):
/// - sending: the write is only in the local cache (not yet accepted);
/// - sent: the server stored the message;
/// - delivered: the recipient's app received it from the server and
///   stamped `deliveredAt` (recipient-only, set once — firestore.rules);
/// - read: the recipient opened the conversation in the foreground and the
///   server accepted `isRead` (recipient-only, false → true once).
/// FCM acceptance or a sent push never counts as delivery.
enum ReceiptState { sending, sent, delivered, read }

abstract final class ReadReceipts {
  static ReceiptState of(MessageModel m) {
    if (m.isPending) return ReceiptState.sending;
    if (m.isRead) return ReceiptState.read;
    return m.deliveredAt != null ? ReceiptState.delivered : ReceiptState.sent;
  }

  static String label(ReceiptState s) => switch (s) {
        ReceiptState.sending => 'Sending',
        ReceiptState.sent => 'Sent',
        ReceiptState.delivered => 'Delivered',
        ReceiptState.read => 'Read',
      };

  /// Whether opening the conversation should mark incoming messages read:
  /// only while the app is in the foreground and only when something from
  /// the other party is actually unread.
  static bool shouldMarkRead({required bool appInForeground, required String viewerId, required String otherPartyId, required Iterable<MessageModel> messages}) =>
      appInForeground && messages.any((m) => m.receiverId == viewerId && m.senderId == otherPartyId && !m.isRead && !m.isPending);
}

/// Stage 8.2 F-3: incoming unread messages of one conversation, and whether
/// the snapshot came only from the device's local cache (not yet confirmed
/// by the server in a live listener).
class IncomingSnapshot {
  const IncomingSnapshot(this.messages, {required this.fromCache});
  final List<MessageModel> messages;
  final bool fromCache;
}

/// Stage 8.2 delivery acknowledgement: incoming, server-confirmed messages
/// on this device that have no `deliveredAt` yet. A cache-only snapshot
/// (cold start, offline) never produces an acknowledgement (F-3).
abstract final class DeliveryReceipts {
  static List<MessageModel> toAcknowledge(Iterable<MessageModel> incoming, {required String viewerId, required bool fromCache}) =>
      fromCache ? const [] : incoming.where((m) => m.receiverId == viewerId && !m.isPending && m.deliveredAt == null && !m.isRead).toList();
}

/// Stage 8.2 F-10: pacing for receipt writes the server refused. A refused
/// write is rolled back locally, which fires the listener again; without a
/// pause a permanently refused write would be retried in a tight loop.
/// The first retry waits [initial], each further failure doubles the wait
/// up to [max]; a success clears it.
class ReceiptBackoff {
  ReceiptBackoff({this.initial = const Duration(seconds: 60), this.max = const Duration(minutes: 30)});
  final Duration initial;
  final Duration max;
  final _next = <String, ({DateTime at, Duration delay})>{};

  bool ready(String key, DateTime now) {
    final e = _next[key];
    return e == null || !now.isBefore(e.at);
  }

  void failed(String key, DateTime now) {
    final prev = _next[key]?.delay;
    final d = prev == null ? initial : (prev * 2 > max ? max : prev * 2);
    _next[key] = (at: now.add(d), delay: d);
  }

  void succeeded(String key) => _next.remove(key);
}

/// Splits [items] into consecutive lists of at most [size] items (Firestore
/// write batches are capped at 500 operations).
List<List<T>> chunked<T>(List<T> items, int size) => [
      for (var i = 0; i < items.length; i += size) items.sublist(i, i + size > items.length ? items.length : i + size),
    ];
