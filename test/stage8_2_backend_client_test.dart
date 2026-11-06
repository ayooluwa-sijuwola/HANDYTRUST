// Stage 8.2 backend work — client side: delivered/read receipt states,
// delivery acknowledgement, exact conversation routes, per-device push
// registration and the pre-sign-out hook, plus the A1 corrections from
// design/STAGE8_2_NOTIFICATION_FINAL_CODE_REVIEW.md (F-1 … F-6, F-10, F-11).
// Fakes only; no Firebase.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/auth_service.dart';
import 'package:handy_trust/core/services/chat_service.dart';
import 'package:handy_trust/core/services/conversation_logic.dart';
import 'package:handy_trust/core/services/push_logic.dart';
import 'package:handy_trust/models/artisan_model.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/message_model.dart';
import 'package:handy_trust/models/notification_model.dart';
import 'package:handy_trust/models/user_model.dart';
import 'package:handy_trust/providers/artisan_provider.dart';
import 'package:handy_trust/providers/auth_provider.dart';
import 'package:handy_trust/providers/chat_provider.dart';
import 'package:handy_trust/providers/connectivity_provider.dart';
import 'package:handy_trust/providers/escrow_provider.dart';
import 'package:handy_trust/providers/notification_provider.dart';
import 'package:handy_trust/ui/screens/chat_screen.dart';

final _t = DateTime(2026, 11, 5, 9);
MessageModel _m(String id, String from, String to, {bool read = false, bool pending = false, DateTime? delivered}) =>
    MessageModel(id: id, jobId: 'j1', senderId: from, receiverId: to, text: 'm $id', isRead: read, isPending: pending, deliveredAt: delivered, createdAt: _t);

class _User implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  bool get isAnonymous => false;
  @override
  bool get emailVerified => true;
  @override
  String? get email => '$uid@example.com';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Order {
  final events = <String>[];
}

class _FakeAuthService implements IAuthService {
  _FakeAuthService(this.o);
  final _Order o;
  @override
  Future<void> signOut() async => o.events.add('signOut');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Push implements PushPlatform {
  _Push(this.o, {this.failRemove = false, this.failDelete = false, this.hangDelete = false, this.pending = false});
  final _Order o;
  final bool failRemove;
  bool failDelete;
  bool hangDelete;
  bool pending;
  @override
  Future<String> deviceId() async => 'dev-9';
  @override
  Future<void> removeDevice(String uid, String deviceId) async {
    if (failRemove) throw StateError('offline');
    o.events.add('removeDevice:$uid:$deviceId');
  }

  @override
  Future<bool> deleteToken() {
    o.events.add('deleteToken');
    if (hangDelete) return Completer<bool>().future; // never completes
    return Future.value(!failDelete);
  }

  @override
  Future<bool> invalidationPending() async => pending;
  @override
  Future<void> setInvalidationPending(bool p) async {
    pending = p;
    o.events.add('pending:$p');
  }

  @override
  Stream<String> get openedAppDestinations => const Stream.empty();
  @override
  set onLocalTap(void Function(String? payload)? handler) {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Chat implements ChatService {
  final acked = <String>[];
  final reads = <List<Object?>>[];
  @override
  Future<int> markDelivered(String jobId, Iterable<String> messageIds) async {
    acked.addAll(messageIds.map((id) => '$jobId/$id'));
    return messageIds.length;
  }

  @override
  Future<void> markAllAsRead(String jobId, {required String viewerId, String? otherPartyId}) async => reads.add([jobId, viewerId, otherPartyId]);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

Future<void> _flush([int n = 4]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

JobModel _job() => JobModel(id: 'j1', customerId: 'c1', artisanId: 'a1', category: 'Plumbing', description: 'x', status: JobStatus.inChat, createdAt: _t);

void main() {
  group('Receipt states (Stage 8.2 definitions)', () {
    test('sending → sent → delivered → read, from real fields only', () {
      expect(ReadReceipts.of(_m('a', 'c1', 'a1', pending: true)), ReceiptState.sending);
      expect(ReadReceipts.of(_m('b', 'c1', 'a1')), ReceiptState.sent);
      expect(ReadReceipts.of(_m('c', 'c1', 'a1', delivered: _t)), ReceiptState.delivered);
      expect(ReadReceipts.of(_m('d', 'c1', 'a1', read: true)), ReceiptState.read);
      expect(ReadReceipts.of(_m('e', 'c1', 'a1', read: true, delivered: _t)), ReceiptState.read);
      expect(ReceiptState.values.map(ReadReceipts.label), ['Sending', 'Sent', 'Delivered', 'Read']);
    });

    test('only server-confirmed, unread, undelivered incoming messages are acknowledged', () {
      final todo = DeliveryReceipts.toAcknowledge([
        _m('ok', 'a1', 'c1'),
        _m('pending', 'a1', 'c1', pending: true), // not from the server yet
        _m('done', 'a1', 'c1', delivered: _t), // already acknowledged
        _m('read', 'a1', 'c1', read: true),
        _m('mine', 'c1', 'a1'), // the viewer's own message
      ], viewerId: 'c1', fromCache: false);
      expect(todo.map((m) => m.id), ['ok']);
    });

    test('F-3: a cache-only snapshot never produces a delivery receipt', () {
      expect(DeliveryReceipts.toAcknowledge([_m('ok', 'a1', 'c1')], viewerId: 'c1', fromCache: true), isEmpty);
    });

    test('F-2: a read receipt writes only isRead + readAt (never deliveredAt)', () {
      expect(ChatService.readReceiptUpdate().keys.toSet(), {'isRead', 'readAt'});
      expect(ChatService.readReceiptUpdate()['isRead'], true);
    });
  });

  group('F-1: message notifications keep /job routes for older apps', () {
    test('new app opens the exact conversation from chatWith', () {
      expect(PushLogic.destination(type: 'message_received', jobId: 'j1', route: '/job/j1', chatWith: 'a2'), '/chat/j1?with=a2');
      expect(
        notificationDestination(NotificationModel(id: 'n', userId: 'c1', type: 'message_received', title: 'New Message', body: 'x', createdAt: _t, jobId: 'j1', route: '/job/j1', chatWith: 'a2')),
        '/chat/j1?with=a2',
      );
    });
    test('without (or with an unsafe) chatWith it falls back to the job chat', () {
      expect(PushLogic.destination(type: 'message_received', jobId: 'j1', route: '/job/j1'), '/chat/j1');
      expect(PushLogic.destination(type: 'message_received', jobId: 'j1', route: '/job/j1', chatWith: 'a2&x=1'), '/chat/j1');
      expect(PushLogic.destination(type: 'message_received', jobId: 'j1', route: '/job/j1', chatWith: '../admin'), '/chat/j1');
      expect(PushLogic.destination(type: 'message_received', jobId: 'j1', route: 'https://evil.example/chat/'), '/chat/j1');
    });
    test('ids allowed in routes', () {
      expect(PushLogic.isSafeId('aZ09_-'), isTrue);
      for (final bad in [null, '', 'a/b', 'a?b', 'a#b', 'a b', 'x' * 129]) {
        expect(PushLogic.isSafeId(bad), isFalse, reason: '$bad');
      }
    });
  });

  group('F-6/F-11: foreground pushes for another account are not shown', () {
    test('shown only to the signed-in recipient', () {
      expect(PushLogic.shouldShowForeground(targetUid: 'u1', currentUid: 'u1', enabled: true), isTrue);
      expect(PushLogic.shouldShowForeground(targetUid: 'u2', currentUid: 'u1', enabled: true), isFalse);
      expect(PushLogic.shouldShowForeground(targetUid: 'u1', currentUid: null, enabled: true), isFalse);
      expect(PushLogic.shouldShowForeground(targetUid: 'u1', currentUid: 'u1', enabled: false), isFalse);
      // A server that does not send `uid` yet: shown to a signed-in user, as before.
      expect(PushLogic.shouldShowForeground(targetUid: null, currentUid: 'u1', enabled: true), isTrue);
      expect(PushLogic.shouldShowForeground(targetUid: '', currentUid: 'u1', enabled: true), isTrue);
    });
  });

  group('Sign-out removes this device first', () {
    test('hook runs before sign-out; sign-out still happens if the hook fails', () async {
      final o = _Order();
      await AuthNotifier(_FakeAuthService(o), beforeSignOut: () async => o.events.add('hook')).signOut();
      expect(o.events, ['hook', 'signOut']);
      final o2 = _Order();
      await AuthNotifier(_FakeAuthService(o2), beforeSignOut: () async => throw StateError('x')).signOut();
      expect(o2.events, ['signOut']);
    });

    testWidgets('F-5: a hook that never completes cannot block sign-out', (t) async {
      final o = _Order();
      var done = false;
      unawaited(AuthNotifier(_FakeAuthService(o), beforeSignOut: () => Completer<void>().future).signOut().then((_) => done = true));
      await t.pump(AuthNotifier.beforeSignOutTimeout - const Duration(milliseconds: 100));
      expect(o.events, isEmpty);
      await t.pump(const Duration(milliseconds: 200));
      expect(o.events, ['signOut']);
      expect(done, isTrue);
    });

    test('unregisterPushDevice: removes the device doc while signed in, then invalidates the token', () async {
      final o = _Order();
      final c = ProviderContainer(overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream<User?>.value(_User('u1'))),
        pushPlatformProvider.overrideWithValue(_Push(o)),
        beforeSignOutProvider.overrideWith((ref) => () => unregisterPushDevice(ref)),
      ]);
      addTearDown(c.dispose);
      await c.read(authStateChangesProvider.future);
      await c.read(beforeSignOutProvider)();
      expect(o.events, ['removeDevice:u1:dev-9', 'deleteToken', 'pending:false']);
    });

    test('offline removal still invalidates the token', () async {
      final o = _Order();
      final c = ProviderContainer(overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream<User?>.value(_User('u1'))),
        pushPlatformProvider.overrideWithValue(_Push(o, failRemove: true)),
        beforeSignOutProvider.overrideWith((ref) => () => unregisterPushDevice(ref)),
      ]);
      addTearDown(c.dispose);
      await c.read(authStateChangesProvider.future);
      await c.read(beforeSignOutProvider)();
      expect(o.events, ['deleteToken', 'pending:false']);
    });
  });

  group('F-5/F-6: token invalidation is bounded and retried until it succeeds', () {
    test('a failed invalidation is remembered; a retry while signed out clears it', () async {
      final o = _Order();
      final push = _Push(o, failDelete: true);
      expect(await invalidateDeviceToken(push), isFalse);
      expect(push.pending, isTrue);
      push.failDelete = false;
      await retryPendingInvalidation(push);
      expect(push.pending, isFalse);
      expect(o.events, ['deleteToken', 'pending:true', 'deleteToken', 'pending:false']);
    });

    test('nothing pending → no retry', () async {
      final o = _Order();
      await retryPendingInvalidation(_Push(o));
      expect(o.events, isEmpty);
    });

    testWidgets('a hanging token delete times out and is marked pending', (t) async {
      final o = _Order();
      final push = _Push(o, hangDelete: true);
      bool? result;
      unawaited(invalidateDeviceToken(push, timeout: const Duration(seconds: 4)).then((r) => result = r));
      await t.pump(const Duration(seconds: 5));
      expect(result, isFalse);
      expect(push.pending, isTrue);
    });

    test('signed out: retried at start and again when the device comes back online', () async {
      final o = _Order();
      final push = _Push(o, failDelete: true, pending: true);
      final online = StreamController<bool>();
      final c = ProviderContainer(overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream<User?>.value(null)),
        currentUserProfileProvider.overrideWith((ref) => Stream<UserModel?>.value(null)),
        isOnlineProvider.overrideWith((ref) => online.stream),
        pushPlatformProvider.overrideWithValue(push),
        pushNavigatorProvider.overrideWithValue((_) {}),
      ]);
      addTearDown(c.dispose);
      addTearDown(online.close);
      final sub = c.listen(notificationInitProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(authStateChangesProvider.future);
      await _flush();
      expect(o.events.where((e) => e == 'deleteToken').length, 1); // at start (still offline → fails)
      expect(push.pending, isTrue);
      push.failDelete = false;
      online.add(false);
      await _flush();
      online.add(true);
      await _flush();
      expect(o.events.where((e) => e == 'deleteToken').length, 2);
      expect(push.pending, isFalse);
    });
  });

  group('F-10: refused receipts back off; batches stay under the Firestore cap', () {
    test('60 s, doubling, capped at 30 min; success clears', () {
      final b = ReceiptBackoff();
      final t0 = DateTime(2026, 11, 5, 9);
      expect(b.ready('k', t0), isTrue);
      b.failed('k', t0);
      expect(b.ready('k', t0.add(const Duration(seconds: 59))), isFalse);
      expect(b.ready('k', t0.add(const Duration(seconds: 60))), isTrue);
      b.succeeded('k');
      var now = t0;
      var expected = const Duration(seconds: 60);
      for (var i = 0; i < 8; i++) {
        b.failed('k', now);
        expect(b.ready('k', now.add(expected - const Duration(seconds: 1))), isFalse, reason: 'attempt $i');
        expect(b.ready('k', now.add(expected)), isTrue, reason: 'attempt $i');
        now = now.add(expected);
        expected = expected * 2 > const Duration(minutes: 30) ? const Duration(minutes: 30) : expected * 2;
      }
      b.succeeded('k');
      expect(b.ready('k', now), isTrue);
    });

    test('batches of at most 450 writes', () {
      final ids = List.generate(1001, (i) => 'm$i');
      expect(chunked(ids, ChatService.maxBatchWrites).map((c) => c.length), [450, 450, 101]);
      expect(chunked(<String>[], 450), isEmpty);
      expect(ChatService.maxBatchWrites, lessThanOrEqualTo(500));
    });
  });

  group('Delivery acknowledger', () {
    test('stamps only qualifying, server-confirmed messages, per conversation (F-3)', () async {
      final chat = _Chat();
      final stream = StreamController<IncomingSnapshot>();
      final c = ProviderContainer(overrides: [
        chatServiceProvider.overrideWithValue(chat),
        customerConversationsProvider.overrideWith((ref, uid) => AsyncValue.data([ConversationRef(job: _job(), viewerId: 'c1', otherPartyId: 'a1')])),
        artisanConversationsProvider.overrideWith((ref, uid) => const AsyncValue.data(<ConversationRef>[])),
        incomingUnreadProvider.overrideWith((ref, k) => stream.stream),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(deliveryAckProvider('c1'), (_, _) {});
      addTearDown(sub.close);
      final msgs = [_m('x1', 'a1', 'c1'), _m('x2', 'a1', 'c1', pending: true), _m('x3', 'a1', 'c1', delivered: _t)];
      stream.add(IncomingSnapshot(msgs, fromCache: true)); // cold start, cache only
      await _flush();
      expect(chat.acked, isEmpty);
      stream.add(IncomingSnapshot(msgs, fromCache: false)); // confirmed by the server
      await _flush();
      expect(chat.acked, ['j1/x1']);
    });

    test('F-4: listeners end when the app root stops watching (sign-out)', () async {
      var cancelled = false;
      final stream = StreamController<IncomingSnapshot>(onCancel: () => cancelled = true);
      final c = ProviderContainer(overrides: [
        chatServiceProvider.overrideWithValue(_Chat()),
        customerConversationsProvider.overrideWith((ref, uid) => AsyncValue.data([ConversationRef(job: _job(), viewerId: 'c1', otherPartyId: 'a1')])),
        artisanConversationsProvider.overrideWith((ref, uid) => const AsyncValue.data(<ConversationRef>[])),
        incomingUnreadProvider.overrideWith((ref, k) => stream.stream),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(deliveryAckProvider('c1'), (_, _) {});
      await _flush();
      expect(stream.hasListener, isTrue);
      // Firestore listeners emit at once (from cache first, even offline).
      // Riverpod 2.6 only cancels a source stream that has emitted.
      stream.add(const IncomingSnapshot([], fromCache: true));
      await _flush();
      sub.close(); // what the root does when the user signs out
      await _flush(6);
      expect(cancelled, isTrue);
    });
  });

  testWidgets('chat shows Delivered when the recipient’s device has the message', (t) async {
    t.view.physicalSize = const Size(430, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final chat = _Chat();
    await t.pumpWidget(ProviderScope(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream<User?>.value(_User('c1'))),
        currentUserProfileProvider.overrideWith((ref) => Stream.value(UserModel(uid: 'c1', name: 'C', createdAt: _t))),
        jobStreamProvider.overrideWith((ref, id) => Stream.value(JobModel(id: 'j1', customerId: 'c1', artisanId: 'a1', category: 'Plumbing', description: 'x', status: JobStatus.inChat, createdAt: _t))),
        artisanProfileProvider.overrideWith((ref, id) => Stream.value(ArtisanModel(uid: 'a1', name: 'A', createdAt: _t))),
        chatServiceProvider.overrideWithValue(chat),
        messagesStreamProvider.overrideWith((ref, k) => Stream.value([_m('s1', 'c1', 'a1'), _m('s2', 'c1', 'a1', delivered: _t), _m('s3', 'c1', 'a1', read: true)])),
      ],
      child: const MaterialApp(home: ChatScreen(jobId: 'j1', otherUserId: 'a1')),
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(find.byTooltip('Sent'), findsOneWidget);
    expect(find.byTooltip('Delivered'), findsOneWidget);
    expect(find.byTooltip('Read'), findsOneWidget);
    expect(chat.reads, isEmpty); // nothing unread from the other party
  });
}
