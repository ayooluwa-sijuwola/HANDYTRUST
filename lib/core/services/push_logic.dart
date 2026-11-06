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
  static String destination({String? type, String? jobId, String? route, String? chatWith}) {
    final id = jobId ?? '';
    // Stage 8.2 (F-1): the server keeps `route: /job/{jobId}` (what older
    // app versions open) and names the other participant in `chatWith`.
    if (type == 'message_received' && isSafeId(id) && isSafeId(chatWith)) return '/chat/$id?with=$chatWith';
    if (type == 'message_received' && id.isNotEmpty && !id.contains('/')) return '/chat/$id';
    if (route != null && route.isNotEmpty) return safeRoute(route);
    if (id.isNotEmpty && !id.contains('/')) return '/job/$id';
    return '/notifications';
  }

  /// A Firestore document id or Firebase uid that is safe to put in a route
  /// (no path, query or fragment characters).
  static bool isSafeId(String? v) => v != null && RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(v);

  /// Whether a push that arrives while the app is open should be shown
  /// (F-6/F-11). The server names the recipient in `uid`; a push for any
  /// other account (a previous account on this device, or a registration
  /// another account claimed) is not shown. Pushes from servers that do not
  /// send `uid` yet are shown to a signed-in user, as before.
  static bool shouldShowForeground({required String? targetUid, required String? currentUid, required bool enabled}) {
    if (!enabled || currentUid == null || currentUid.isEmpty) return false;
    if (targetUid == null || targetUid.isEmpty) return true;
    return targetUid == currentUid;
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
