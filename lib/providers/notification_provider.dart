import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/notification_service.dart';
import '../firebase/messaging/local_notification_service.dart';
import '../models/notification_model.dart';
import 'auth_provider.dart';
import 'package:flutter/material.dart';
import '../routes/router.dart';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(FirebaseFirestore.instance),
);

/// In-app notification inbox for the current user — drives NotificationsScreen.
final userNotificationsProvider = StreamProvider<List<NotificationModel>>((ref) {
  final user = ref.watch(currentUserProvider).asData?.value;
  // Stream.empty() closes without emitting, leaving a StreamProvider stuck
  // in AsyncLoading forever — same bug class as currentUserProfileProvider
  // had. Emit an explicit empty list so signed-out callers resolve cleanly.
  if (user == null) return Stream.value(const []);
  return ref.watch(notificationServiceProvider).watchForUser(user.uid);
});

/// Unread count — drives the bell-icon badge.
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final user = ref.watch(currentUserProvider).asData?.value;
  if (user == null) return Stream.value(0);
  return ref.watch(notificationServiceProvider).watchUnreadCount(user.uid);
});

/// Writes the current FCM token to `fcm_tokens/{uid}` — the collection
/// Cloud Functions' `_sendNotification` already reads from (functions/index.js).
/// Previously this wrote to `users/{uid}.fcmToken`, a field the existing
/// Cloud Functions never look at, so server-sent pushes silently never had
/// a token to deliver to. Writing to the collection Cloud Functions already
/// expect makes the existing push infrastructure functional without
/// modifying any Cloud Function (preserves "no new backend services" scope).
Future<void> _saveFcmToken(FirebaseFirestore db, String uid, String token) =>
    db.collection('fcm_tokens').doc(uid).set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });

/// Bootstraps push notifications and FCM token registration.
/// Watch this provider in the root widget (_HandyTrustRouterApp) to keep it
/// alive for the entire session. It is a no-op when the user is signed out.
final notificationInitProvider = Provider<void>((ref) {
  final authAsync = ref.watch(authStateChangesProvider);
  final user = authAsync.asData?.value;

  if (user == null || user.isAnonymous) return;

  final service = LocalNotificationService.instance;
  final firestore = FirebaseFirestore.instance;

  // Start listening for foreground messages (idempotent). Skipped if the
  // user has turned off notifications in their preferences.
  service.startForegroundListener(
    isEnabled: () => ref.read(currentUserProvider).asData?.value?.notificationsEnabled ?? true,
  );

  // Request permission + register FCM token — fire and forget
  Future<void> register() async {
    try {
      await service.requestPermission();
      final token = await service.getToken();
      if (token != null) {
        try {
          await _saveFcmToken(firestore, user.uid, token);
          debugPrint('[notificationInitProvider] saved FCM token for ${user.uid}');
        } catch (e) {
          debugPrint('[notificationInitProvider] failed to save token: $e');
        }
      } else {
        debugPrint('[notificationInitProvider] no FCM token available for ${user.uid}');
      }
    } catch (e) {
      debugPrint('[notificationInitProvider] token registration failed: $e');
    }
  }

  register();

  // Re-register whenever the FCM token rotates
  final sub = service.onTokenRefresh.listen((newToken) {
    _saveFcmToken(firestore, user.uid, newToken).then((_) {
      debugPrint('[notificationInitProvider] refreshed FCM token saved for ${user.uid}');
    }).catchError((e) {
      debugPrint('[notificationInitProvider] token refresh save failed: $e');
    });
  });

  // Handle when a notification is tapped (app opened from terminated/background)
  // and deep-link to the route if available.
  try {
    // If app opened from a terminated state via a notification
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        final route = routeFromMessage(message);
        if (route != null) {
          debugPrint('[notificationInitProvider] initialMessage deep-link: $route');
          // Stage 6 (HT-026): navigate through GoRouter. The previous
          // Navigator.pushNamed had no route table under GoRouter, so it
          // threw (caught and logged) and taps never navigated.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(routerProvider).push(safeNotificationRoute(route));
          });
        }
      }
    });
  } catch (e) {
    debugPrint('[notificationInitProvider] getInitialMessage failed: $e');
  }

  // When the app is in background and user taps the notification
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    try {
      final route = routeFromMessage(message);
      if (route != null) {
        debugPrint('[notificationInitProvider] onMessageOpenedApp deep-link: $route');
        ref.read(routerProvider).push(safeNotificationRoute(route));
      }
    } catch (e) {
      debugPrint('[notificationInitProvider] onMessageOpenedApp handler failed: $e');
    }
  });

  ref.onDispose(sub.cancel);
});


/// Stage 6 (HT-026): only in-app paths are followed from a notification
/// payload — anything else (absolute URLs, empty or malformed values) falls
/// back to the notifications list, so a payload can never send the app
/// somewhere unexpected.
String safeNotificationRoute(String? route) {
  if (route == null || route.isEmpty) return '/notifications';
  if (!route.startsWith('/') || route.startsWith('//') || route.contains('://')) return '/notifications';
  const allowedPrefixes = ['/job/', '/chat/', '/dispute/', '/notifications', '/jobs', '/wallet', '/home'];
  return allowedPrefixes.any(route.startsWith) ? route : '/notifications';
}
