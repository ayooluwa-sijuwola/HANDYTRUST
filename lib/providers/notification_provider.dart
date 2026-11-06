import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/services/notification_service.dart';
import '../core/services/push_logic.dart';
import '../firebase/messaging/local_notification_service.dart';
import '../models/notification_model.dart';
import '../routes/router.dart';
import 'auth_provider.dart';
import 'connectivity_provider.dart';

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

  /// Invalidates this device's token; false if that failed (e.g. offline).
  Future<bool> deleteToken();
  Stream<String> get onTokenRefresh;

  /// Destination of the push that launched the app from terminated, if any.
  Future<String?> initialMessageDestination();

  /// Destinations of pushes tapped while the app was in the background.
  Stream<String> get openedAppDestinations;

  /// A tap on a locally displayed (foreground) notification that happened
  /// before the handler was set, including an app launch.
  String? takeLocalLaunchPayload();
  set onLocalTap(void Function(String? payload)? handler);

  /// [shouldShow] receives the recipient uid the server put in the push.
  void startForegroundListener(bool Function(String? targetUid) shouldShow);

  /// Stage 8.2 F-6: a token invalidation that failed and must be retried
  /// while nobody is signed in (persisted across app restarts).
  Future<bool> invalidationPending();
  Future<void> setInvalidationPending(bool pending);

  /// Stable id of this app installation (per-device token document).
  Future<String> deviceId();

  /// Stage 8.2: `fcm_tokens/{uid}/devices/{deviceId}` — one document per
  /// device (owner-only write, firestore.rules), read by the server's
  /// push delivery. Devices no longer overwrite each other.
  Future<void> saveToken(String uid, String deviceId, String token);
  Future<void> removeDevice(String uid, String deviceId);
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
  Future<bool> deleteToken() => _local.deleteToken();
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
  void startForegroundListener(bool Function(String? targetUid) shouldShow) => _local.startForegroundListener(shouldShow: shouldShow);
  @override
  Future<bool> invalidationPending() async => (await SharedPreferences.getInstance()).getBool(_pendingKey) ?? false;
  @override
  Future<void> setInvalidationPending(bool pending) async {
    final prefs = await SharedPreferences.getInstance();
    if (pending) {
      await prefs.setBool(_pendingKey, true);
    } else {
      await prefs.remove(_pendingKey);
    }
  }

  static const _pendingKey = 'push_invalidation_pending';
  @override
  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  static const _deviceIdKey = 'push_device_id';

  static String get _platform => kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');

  @override
  Future<void> saveToken(String uid, String deviceId, String token) =>
      _db.collection('fcm_tokens').doc(uid).collection('devices').doc(deviceId).set({
        'token': token,
        'platform': _platform,
        'updatedAt': FieldValue.serverTimestamp(),
      });
  @override
  Future<void> removeDevice(String uid, String deviceId) =>
      _db.collection('fcm_tokens').doc(uid).collection('devices').doc(deviceId).delete();
}

/// Stage 8.2 F-5/F-6: invalidates this device's token, waiting at most
/// [timeout]. A failure (offline, slow) is remembered and retried while
/// nobody is signed in, so a signed-out phone stops receiving the previous
/// account's pushes once it is back online.
Future<bool> invalidateDeviceToken(PushPlatform platform, {Duration timeout = const Duration(seconds: 4)}) async {
  var ok = false;
  try {
    ok = await platform.deleteToken().timeout(timeout);
  } catch (e) {
    debugPrint('[push] token invalidation failed: $e');
  }
  try {
    await platform.setInvalidationPending(!ok);
  } catch (e) {
    debugPrint('[push] could not record token invalidation state: $e');
  }
  return ok;
}

Future<void>? _retryInFlight;

/// Retries a failed invalidation (F-6). Only called while nobody is signed
/// in: once an account registers, the server's newest-registration rule
/// releases the token from the previous account instead.
Future<void> retryPendingInvalidation(PushPlatform platform) {
  return _retryInFlight ??= () async {
    try {
      var pending = false;
      try {
        pending = await platform.invalidationPending();
      } catch (_) {}
      if (pending) await invalidateDeviceToken(platform);
    } finally {
      _retryInFlight = null;
    }
  }();
}

/// Stage 8.2: removes THIS device's push registration while the user is
/// still signed in (the rules require the owner), then invalidates the
/// device token. Wired as the app's `beforeSignOutProvider`. Bounded: at
/// most ~7 s, and AuthNotifier caps the hook as a whole (F-5).
Future<void> unregisterPushDevice(Ref ref) async {
  final uid = ref.read(authStateChangesProvider).asData?.value?.uid;
  final platform = ref.read(pushPlatformProvider);
  try {
    if (uid != null) {
      final id = await platform.deviceId();
      await platform.removeDevice(uid, id).timeout(const Duration(seconds: 3));
    }
  } catch (e) {
    // Offline or slow: the token is invalidated below (or retried later),
    // and the server removes the stale registration on its next failed send.
    debugPrint('[push] device unregister before sign-out failed: $e');
  }
  await invalidateDeviceToken(platform);
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

  // F-6: while nobody is signed in, a token invalidation that failed
  // earlier is retried at start and whenever the device comes back online.
  final signedOutResolved = authAsyncIsSignedOut(ref.watch(authStateChangesProvider));
  if (signedOutResolved) {
    ref.listen<AsyncValue<bool>>(isOnlineProvider, (prev, next) {
      if (next.asData?.value == true && prev?.asData?.value != true) retryPendingInvalidation(platform);
    });
  }

  if (uid != null && enabled == null) return; // profile still loading
  final action = PushLogic.decide(uid: uid, enabled: enabled ?? true, previousUid: session.lastUid);
  session.lastUid = uid;

  switch (action) {
    case PushRegistration.none:
      if (signedOutResolved) retryPendingInvalidation(platform);
      return;
    case PushRegistration.unregisterDevice:
      session.refreshSub?.cancel();
      session.refreshSub = null;
      invalidateDeviceToken(platform);
      return;
    case PushRegistration.unregisterAccount:
      // The server also skips pushes for this account (preference check);
      // this removes this device's registration and invalidates its token.
      session.refreshSub?.cancel();
      session.refreshSub = null;
      () async {
        try {
          await platform.removeDevice(uid!, await platform.deviceId());
        } catch (e) {
          debugPrint('[push] removing device registration failed: $e');
        }
        await invalidateDeviceToken(platform);
      }();
      return;
    case PushRegistration.register:
      platform.startForegroundListener((targetUid) {
        final u = ref.read(authStateChangesProvider).asData?.value;
        return PushLogic.shouldShowForeground(
          targetUid: targetUid,
          currentUid: (u == null || u.isAnonymous) ? null : u.uid,
          enabled: ref.read(currentUserProvider).asData?.value?.notificationsEnabled ?? true,
        );
      });
      () async {
        try {
          await platform.requestPermission();
          final token = await platform.getToken();
          if (token != null) {
            await platform.saveToken(uid!, await platform.deviceId(), token);
            // The registration now belongs to this account; the server
            // releases the token from any previous account (F-7), so a
            // pending invalidation is no longer needed.
            await platform.setInvalidationPending(false);
          }
        } catch (e) {
          debugPrint('[push] registration failed: $e');
        }
      }();
      session.refreshSub?.cancel();
      session.refreshSub = platform.onTokenRefresh.listen((t) async {
        try {
          await platform.saveToken(uid!, await platform.deviceId(), t);
        } catch (e) {
          debugPrint('[push] token refresh save failed: $e');
        }
      });
  }
});

/// Stage 6 (HT-026): only in-app paths are followed from a notification
/// payload; anything else falls back to the notifications list.
String safeNotificationRoute(String? route) => PushLogic.safeRoute(route);

/// Destination for an in-app notification row (same rules as push taps).
String notificationDestination(NotificationModel n) =>
    PushLogic.destination(type: n.type, jobId: n.jobId, route: n.route, chatWith: n.chatWith);

/// True once the auth state has resolved to "nobody (non-anonymous) signed
/// in" — never while it is still loading.
bool authAsyncIsSignedOut(AsyncValue<User?> a) => a is AsyncData<User?> && (a.value == null || a.value!.isAnonymous);
