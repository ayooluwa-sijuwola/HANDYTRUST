import 'package:clock/clock.dart' as clk;
import 'package:intl/intl.dart';

/// Display-only formatting for the Stage 8 screens. Amounts always come
/// from server documents; these helpers never compute fees.
abstract final class HtFormat {
  static final _naira = NumberFormat.decimalPattern('en_NG');

  /// ₦85,000 — whole naira (kobo omitted when zero).
  static String naira(num? amount) {
    if (amount == null) return '—';
    final rounded = amount.round();
    if ((amount - rounded).abs() < 0.005) return '₦${_naira.format(rounded)}';
    return '₦${NumberFormat('#,##0.00', 'en_NG').format(amount)}';
  }

  /// Splits ₦86,500.00 into ('₦86,500', '.00') for the large/small amount style.
  static (String, String) nairaSplit(num amount) {
    final whole = amount.truncate();
    final kobo = ((amount - whole) * 100).round().toString().padLeft(2, '0');
    return ('₦${_naira.format(whole)}', '.$kobo');
  }

  static String initials(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  /// "HT-8402"-style short reference derived from the real document id.
  static String bookingRef(String id) {
    final clean = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final tail = clean.length <= 6 ? clean : clean.substring(clean.length - 6);
    return 'HT-${tail.toUpperCase()}';
  }

  static String timeAgo(DateTime t, {DateTime? now}) {
    final n = now ?? clk.clock.now();
    final d = n.difference(t);
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return '${d.inDays} days ago';
    return DateFormat('d MMM').format(t);
  }

  static String clock(DateTime t) => DateFormat('h:mm a').format(t);
  static String dayLabel(DateTime t, {DateTime? now}) {
    final n = now ?? clk.clock.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('EEE, d MMM').format(t);
  }

  static String dateTime(DateTime t) => DateFormat('d MMM yyyy, h:mm a').format(t);
  static String date(DateTime t) => DateFormat('d MMM yyyy').format(t);

  /// Last one or two comma-separated parts of an address ("Bodija, Ibadan");
  /// never the street line.
  static String? area(String? address) {
    if (address == null || address.trim().isEmpty) return null;
    final parts = address.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.length >= 3) return '${parts[parts.length - 2]}, ${parts.last}';
    if (parts.length == 2) return parts.last;
    return null;
  }
}
