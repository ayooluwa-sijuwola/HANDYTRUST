import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;

import '../../core/services/push_logic.dart';

/// Top-level FCM background handler — must be a top-level function and annotated
/// so the Dart compiler does not tree-shake it in release builds.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages on Android are displayed by the system from the
  // message's `notification` block (on the default channel named in the
  // manifest). Nothing is shown here, so a message is never displayed twice.
  debugPrint('[FCM] Background message received: ${message.messageId}');
}

/// Singleton notification service.
/// Call [init] once after Firebase is initialized (before any notifications
/// can be shown).
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _fcm = FirebaseMessaging.instance;

  /// Android channel for every HandyTrust notification. The manifest also
  /// names it as FCM's default channel, so notifications the system shows
  /// while the app is in the background use it too (Stage 8.2).
  static const channelId = 'handy_trust_main';

  static const _channel = AndroidNotificationChannel(
    channelId,
    'HandyTrust',
    description: 'Job updates, messages, and payment notifications.',
    importance: Importance.high,
  );

  static bool _alwaysEnabled() => true;

  bool _foregroundListenerRegistered = false;
  bool Function() _isEnabled = _alwaysEnabled;

  /// Called when the user taps a notification this service displayed
  /// (foreground messages). Set by the push provider; until then a tap is
  /// kept for [takePendingPayload].
  void Function(String? payload)? onTap;
  String? _pendingPayload;

  void _handleTap(String? payload) {
    final handler = onTap;
    if (handler != null) {
      handler(payload);
    } else {
      _pendingPayload = payload ?? '/notifications';
    }
  }

  /// A tap that arrived before anyone was listening, including the tap that
  /// launched the app from a terminated state. Returned once.
  String? takePendingPayload() {
    final p = _pendingPayload;
    _pendingPayload = null;
    return p;
  }

  /// Initialise flutter_local_notifications and register the FCM background handler.
  /// Must be called once from main() after WidgetsFlutterBinding.ensureInitialized()
  /// and after Firebase.initializeApp().
  Future<void> init() async {
    try {
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      }
    } catch (e) {
      debugPrint('[LocalNotif] onBackgroundMessage registration skipped: $e');
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    try {
      if (!kIsWeb) {
        await _plugin.initialize(
          const InitializationSettings(android: androidInit, iOS: iosInit),
          // Stage 8.2: taps on notifications shown while the app was open
          // previously did nothing (no callback was registered).
          onDidReceiveNotificationResponse: (r) => _handleTap(r.payload),
        );

        // The app was launched by tapping one of our notifications.
        final launch = await _plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) {
          _pendingPayload = launch?.notificationResponse?.payload ?? '/notifications';
        }

        if (defaultTargetPlatform == TargetPlatform.android) {
          await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.createNotificationChannel(_channel);
        }
      } else {
        debugPrint('[LocalNotif] skipping plugin initialization on web');
      }
    } catch (e) {
      debugPrint('[LocalNotif] init failed or skipped: $e');
    }
  }

  /// Request OS-level notification permission (iOS + Android 13+).
  /// Returns true if granted or provisional.
  Future<bool> requestPermission() async {
    try {
      final settings = await _fcm.requestPermission(alert: true, badge: true, sound: true);
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('[FCM] requestPermission failed: $e');
      return false;
    }
  }

  /// Returns the current FCM registration token, or null if unavailable.
  Future<String?> getToken() async {
    try {
      return await _fcm.getToken();
    } catch (e) {
      debugPrint('[FCM] getToken failed: $e');
      return null;
    }
  }

  /// Invalidates this device's FCM token (sign-out, or push turned off).
  /// A later [getToken] returns a fresh token.
  Future<void> deleteToken() async {
    try {
      await _fcm.deleteToken();
    } catch (e) {
      debugPrint('[FCM] deleteToken failed: $e');
    }
  }

  /// Returns a stream that fires whenever the FCM token is refreshed.
  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  /// Start listening for foreground FCM messages and show local notifications.
  /// Safe to call multiple times — only registers the listener once.
  /// [isEnabled] is re-checked on every message so a live preference change
  /// takes effect without re-registering the listener.
  void startForegroundListener({bool Function() isEnabled = _alwaysEnabled}) {
    _isEnabled = isEnabled;
    if (kIsWeb) {
      debugPrint('[LocalNotif] startForegroundListener skipped on web');
      return;
    }
    if (_foregroundListenerRegistered) return;
    _foregroundListenerRegistered = true;
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (!_isEnabled()) return;
      final notification = message.notification;
      if (notification == null) return;
      _show(
        id: (message.messageId ?? message.sentTime?.toIso8601String() ?? notification.title ?? '').hashCode,
        title: notification.title ?? 'HandyTrust',
        body: notification.body ?? '',
        payload: destinationFromMessage(message),
      );
    });
  }

  Future<void> _show({required int id, required String title, required String body, String? payload}) async {
    try {
      if (kIsWeb) return;
      final androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        // Stage 8.2: on a secure lock screen Android shows that something
        // arrived but hides the text (message previews).
        visibility: NotificationVisibility.private,
      );
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(android: androidDetails, iOS: const DarwinNotificationDetails()),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[LocalNotif] show failed: $e');
    }
  }
}

/// Where a tapped push should open (Stage 8.2): new-message notifications
/// open the conversation; everything else follows the server's allow-listed
/// route. Same rule for foreground, background and terminated taps.
String destinationFromMessage(RemoteMessage message) {
  final data = message.data;
  return PushLogic.destination(
    type: data['type'] as String?,
    jobId: data['jobId'] as String?,
    route: data['route'] as String?,
  );
}
