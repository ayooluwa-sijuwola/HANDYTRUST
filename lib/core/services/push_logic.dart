/// Pure push-notification rules (Stage 8.2). No Firebase, no BuildContext —
/// tested in test/push_notification_test.dart.
abstract final class PushLogic {
  /// In-app paths a notification may open. Anything else (absolute URLs,
  /// protocol-relative paths, admin pages, malformed values) falls back to
  /// the notifications list, so a payload can never send the app somewhere
  /// unexpected (Stage 6 HT-026 allow-list, unchanged).
  static const allowedPrefixes = ['/job/', '/chat/', '/dispute/', '/notifications', '/jobs', '/wallet', '/home'];

  static String safeRoute(String? route) {
    if (route == null || route.isEmpty) return '/notifications';
    if (!route.startsWith('/') || route.startsWith('//') || route.contains('://')) return '/notifications';
    return allowedPrefixes.any(route.startsWith) ? route : '/notifications';
  }

  /// Where tapping a notification goes. The server routes every job event
  /// to `/job/{id}`; a new-message notification should open the
  /// conversation instead, so `message_received` maps to `/chat/{id}` (the
  /// chat screen resolves the other participant from the job).
  static String destination({String? type, String? jobId, String? route}) {
    final id = jobId ?? '';
    if (type == 'message_received' && id.isNotEmpty && !id.contains('/')) return '/chat/$id';
    if (route != null && route.isNotEmpty) return safeRoute(route);
    if (id.isNotEmpty && !id.contains('/')) return '/job/$id';
    return '/notifications';
  }

  /// What the device should do with its push registration.
  static PushRegistration decide({required String? uid, required bool enabled, required String? previousUid}) {
    if (uid == null) return previousUid == null ? PushRegistration.none : PushRegistration.unregisterDevice;
    if (!enabled) return PushRegistration.unregisterAccount;
    return PushRegistration.register;
  }
}

enum PushRegistration {
  /// Nothing to do (signed out, nobody was signed in before).
  none,

  /// Signed in with push enabled: request permission, save the token.
  register,

  /// Signed in with push disabled: invalidate this device's token and
  /// remove the account's stored token, so the server has nothing to send to.
  unregisterAccount,

  /// Just signed out: invalidate this device's token so the previous
  /// account's pushes can no longer reach this device.
  unregisterDevice,
}
