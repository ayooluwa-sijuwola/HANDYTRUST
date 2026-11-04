import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Trusted backend settings (`config/platform`, Admin-SDK/console write only).
/// The server enforces these values (Cloud Functions + firestore.rules); the
/// app only reads them so customers and artisans see the same limits before
/// they post, quote, agree or accept (policy D1).
class PlatformConfig {
  /// Mirrors PLATFORM_CONFIG_DEFAULTS.minJobValueNgn in functions/index.js and
  /// minJobValueNgn() in firestore.rules.
  static const double defaultMinJobValueNgn = 3212;

  final double minJobValueNgn;
  final double platformFeePercent;
  /// Stage 5 (D5) — mirrors the server defaults.
  final int quoteValidityHours;
  final int bookingConfirmationHours;
  /// Stage 6 (D8): artisan service radius default and upper bound (km).
  final double defaultServiceRadiusKm;
  final double maxServiceRadiusKm;

  const PlatformConfig({
    this.minJobValueNgn = defaultMinJobValueNgn,
    this.platformFeePercent = 5,
    this.quoteValidityHours = 48,
    this.bookingConfirmationHours = 24,
    this.defaultServiceRadiusKm = 10,
    this.maxServiceRadiusKm = 25,
  });

  factory PlatformConfig.fromMap(Map<String, dynamic>? m) => PlatformConfig(
        minJobValueNgn: (m?['minJobValueNgn'] as num?)?.toDouble() ?? defaultMinJobValueNgn,
        platformFeePercent: (m?['platformFeePercent'] as num?)?.toDouble() ?? 5,
        quoteValidityHours: (m?['quoteValidityHours'] as num?)?.toInt() ?? 48,
        bookingConfirmationHours: (m?['bookingConfirmationHours'] as num?)?.toInt() ?? 24,
        defaultServiceRadiusKm: (m?['defaultServiceRadiusKm'] as num?)?.toDouble() ?? 10,
        maxServiceRadiusKm: (m?['maxServiceRadiusKm'] as num?)?.toDouble() ?? 25,
      );

  /// Display check only — the rules enforce validity from server time.
  bool quoteIsValid(DateTime? submittedAt, {DateTime? now}) =>
      submittedAt != null &&
      (now ?? DateTime.now()).isBefore(submittedAt.add(Duration(hours: quoteValidityHours)));

  bool meetsMinimum(double? amount) => amount != null && amount >= minJobValueNgn;

  String get minJobValueLabel => '₦${minJobValueNgn.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      )}';
}

final platformConfigStreamProvider = StreamProvider<PlatformConfig>((ref) {
  return FirebaseFirestore.instance
      .collection('config')
      .doc('platform')
      .snapshots()
      .map((s) => PlatformConfig.fromMap(s.data()));
});

/// Always has a value: the live config once loaded, the documented default
/// before that (or if the read fails) — the server enforces regardless.
final platformConfigProvider = Provider<PlatformConfig>(
  (ref) => ref.watch(platformConfigStreamProvider).asData?.value ?? const PlatformConfig(),
);
