import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/notification_service.dart';
import '../core/services/push_logic.dart';
import '../firebase/messaging/local_notification_service.dart';
import '../models/notification_model.dart';
import '../routes/router.dart';
import 'auth_provider.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(FirebaseFirestore.instance),
);

/// In-app notification inbox for the current user — drives NotificationsScreen.
final userNotificationsProvider = StreamProvider<List<NotificationModel>>((ref) {
  final user = ref.watch(currentUserProvider).asData?.value;
  // Stream.empty() closes without emitting, leaving a StreamProvider stuck
  // in AsyncLoading forever. Emit an explicit empty list when signed out.
  if (user == null) return Stream.value(const []);
  return ref.watch(notificationServiceProvider).watchForUser(user.uid);
});

/// Unread count — drives the bell-icon badge.
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final user = ref.watch(currentUserProvider).asData?.value;
  if (user == null) return Stream.value(0);
  return ref.watch(notificationServiceProvider).watchUnreadCount(user.uid);
});

// ─── Push platform (Stage 8.2) ──────────────────────────────────────────────

/// Everything the push layer needs from FCM, the local-notification plugin
/// and Firestore, behind one interface so registration and tap routing are
/// testable without devices (test/push_notification_test.dart). Delivery
/// itself can only be verified on a device; see STAGE8_2_NOTIFICATION_AUDIT.
abstract class PushPlatform {
  Future<void> requestPermission();
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;

  /// Destination of the push that launched the app from terminated, if any.
  Future<String?> initialMessageDestination();

  /// Destinations of pushes tapped while the app was in the background.
  Stream<String> get openedAppDestinations;

  /// A tap on a locally displayed (foreground) notification that happened
  /// before the handler was set, including an app launch.
  String? takeLocalLaunchPayload();
  set onLocalTap(void Function(String? payload)? handler);

  void startForegroundListener(bool Function() enabled);

  /// `fcm_tokens/{uid}`: the document the server's onNotificationCreated
  /// reads (owner write per firestore.rules).
  Future<void> saveToken(String uid, String token);
  Future<void> removeToken(String uid);
}

class FirebasePushPlatform implements PushPlatform {
  FirebasePushPlatform(this._db);
  final FirebaseFirestore _db;
  LocalNotificationService get _local => LocalNotificationService.instance;

  @override
  Future<void> requestPermission() => _local.requestPermission();
  @override
  Future<String?> getToken() => _local.getToken();
  @override
  Future<void> deleteToken() => _local.deleteToken();
  @override
  Stream<String> get onTokenRefresh => _local.onTokenRefresh;
  @override
  Future<String?> initialMessageDestination() async {
    final m = await FirebaseMessaging.instance.getInitialMessage();
    return m == null ? null : destinationFromMessage(m);
  }

  @override
  Stream<String> get openedAppDestinations => FirebaseMessaging.onMessageOpenedApp.map(destinationFromMessage);
  @override
  String? takeLocalLaunchPayload() => _local.takePendingPayload();
  @override
  set onLocalTap(void Function(String? payload)? handler) => _local.onTap = handler;
  @override
  void startForegroundListener(bool Function() enabled) => _local.startForegroundListener(isEnabled: enabled);
  @override
  Future<void> saveToken(String uid, String token) => _db.collection('fcm_tokens').doc(uid).set({
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
      });
  @override
  Future<void> removeToken(String uid) => _db.collection('fcm_tokens').doc(uid).delete();
}

final pushPlatformProvider = Provider<PushPlatform>((ref) => FirebasePushPlatform(FirebaseFirestore.instance));

/// Opens an in-app route from a notification tap (GoRouter push).
final pushNavigatorProvider = Provider<void Function(String route)>((ref) => (route) => ref.read(routerProvider).push(route));

/// State that must survive rebuilds of [notificationInitProvider]: who was
/// signed in, and the listeners that must exist exactly once per session.
class PushSession {
  String? lastUid;
  bool tapsWired = false;
  bool initialHandled = false;
  StreamSubscription<String>? openedSub;
  StreamSubscription<String>? refreshSub;
}

final pushSessionProvider = Provider<PushSession>((ref) {
  final s = PushSession();
  ref.onDispose(() {
    s.openedSub?.cancel();
    s.refreshSub?.cancel();
  });
  return s;
});

/// Bootstraps push notifications for the signed-in account. Watched by the
/// root widget for the whole session.
///
/// Stage 8.2 fixes (client-side only):
/// - Tap listeners are registered once per session. Previously a new
///   onMessageOpenedApp listener was added on every rebuild and never
///   cancelled, so one tap could navigate several times.
/// - Taps on notifications shown while the app is open now navigate.
/// - `notificationsEnabled = false` removes this account's push token (the
///   server then has nothing to send to); turning it on registers again.
///   Previously it only hid foreground pop-ups.
/// - Signing out invalidates this device's token, so the previous account's
///   pushes stop reaching the device (account switch).
/// - A `message_received` tap opens the conversation, not the job page.
final notificationInitProvider = Provider<void>((ref) {
  final platform = ref.watch(pushPlatformProvider);
  final session = ref.watch(pushSessionProvider);
  final navigate = ref.read(pushNavigatorProvider);
  final authUser = ref.watch(authStateChangesProvider).asData?.value;
  final uid = (authUser == null || authUser.isAnonymous) ? null : authUser.uid;
  // null until the profile has loaded: no decision is taken on a guess.
  final enabled = ref.watch(currentUserProvider.select((a) => a.asData?.value?.notificationsEnabled));

  void open(String? destination) => navigate(PushLogic.safeRoute(destination));
  void openAfterFrame(String destination) => WidgetsBinding.instance.addPostFrameCallback((_) => open(destination));

  if (!session.tapsWired) {
    session.tapsWired = true;
    platform.onLocalTap = (payload) => open(payload);
    session.openedSub = platform.openedAppDestinations.listen(open);
  }

  // Taps that launched the app wait until someone is signed in, otherwise
  // the router's sign-in redirect would swallow them.
  if (uid != null) {
    final local = platform.takeLocalLaunchPayload();
    if (local != null) openAfterFrame(local);
    if (!session.initialHandled) {
      session.initialHandled = true;
      platform.initialMessageDestination().then((d) {
        if (d != null) openAfterFrame(d);
      }, onError: (Object e) {
        debugPrint('[push] initial message failed: $e');
      });
    }
  }

  if (uid != null && enabled == null) return; // profile still loading
  final action = PushLogic.decide(uid: uid, enabled: enabled ?? true, previousUid: session.lastUid);
  session.lastUid = uid;

  switch (action) {
    case PushRegistration.none:
      return;
    case PushRegistration.unregisterDevice:
      session.refreshSub?.cancel();
      session.refreshSub = null;
      platform.deleteToken();
      return;
    case PushRegistration.unregisterAccount:
      session.refreshSub?.cancel();
      session.refreshSub = null;
      () async {
        await platform.deleteToken();
        try {
          await platform.removeToken(uid!);
        } catch (e) {
          debugPrint('[push] removing stored token failed: $e');
        }
      }();
      return;
    case PushRegistration.register:
      platform.startForegroundListener(() => ref.read(currentUserProvider).asData?.value?.notificationsEnabled ?? true);
      () async {
        try {
          await platform.requestPermission();
          final token = await platform.getToken();
          if (token != null) await platform.saveToken(uid!, token);
        } catch (e) {
          debugPrint('[push] registration failed: $e');
        }
      }();
      session.refreshSub?.cancel();
      session.refreshSub = platform.onTokenRefresh.listen((t) {
        platform.saveToken(uid!, t).catchError((Object e) => debugPrint('[push] token refresh save failed: $e'));
      });
  }
});

/// Stage 6 (HT-026): only in-app paths are followed from a notification
/// payload; anything else falls back to the notifications list.
String safeNotificationRoute(String? route) => PushLogic.safeRoute(route);

/// Destination for an in-app notification row (same rules as push taps).
String notificationDestination(NotificationModel n) =>
    PushLogic.destination(type: n.type, jobId: n.jobId, route: n.route);
