import '../../models/notification_model.dart';

/// Filter tabs on the Notifications screen (references 12, 24).
enum NotificationCategory { escrow, jobs, account }

/// Stage 8: pure mapping of server notification types to filter tabs.
abstract final class NotificationCategories {
  static const _escrowWords = ['escrow', 'payment', 'payout', 'refund', 'transfer', 'settle', 'release', 'chargeback'];
  static const _accountWords = ['verif', 'account', 'suspend', 'password', 'admin', 'deletion'];

  static NotificationCategory of(NotificationModel n) {
    final type = n.type.toLowerCase();
    final title = n.title.toLowerCase();
    bool any(List<String> words, String s) => words.any(s.contains);
    if (any(_escrowWords, type) || any(_escrowWords, title)) return NotificationCategory.escrow;
    if (any(_accountWords, type) || any(_accountWords, title)) return NotificationCategory.account;
    return NotificationCategory.jobs;
  }

  /// Short status chip shown under a notification.
  static String chipLabel(NotificationModel n) {
    final t = '${n.type} ${n.title}'.toLowerCase();
    if (t.contains('refund')) return 'Refund';
    if (t.contains('payout') || t.contains('payment sent') || t.contains('released')) return 'Payout';
    if (t.contains('escrow') || t.contains('payment')) return 'Escrow';
    if (t.contains('quote')) return 'Quote';
    if (t.contains('agreement')) return 'Agreement';
    if (t.contains('dispute')) return 'Dispute';
    if (t.contains('review')) return 'Review';
    if (t.contains('message')) return 'Message';
    if (t.contains('verif')) return 'Verification';
    if (t.contains('booking') || t.contains('assigned')) return 'Booking';
    return 'Job update';
  }
}
