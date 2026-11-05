import 'package:cloud_firestore/cloud_firestore.dart';

/// Read-only view of a server-written finance document (Stage 8.2, admin
/// Finance, Q-4). The four collections have different shapes, so the raw
/// map is kept and typed accessors read the fields each writer actually
/// sets (functions/index.js). Amounts are stored in kobo and shown as naira.
enum FinanceKind { chargebacks, platformLosses, refunds, settlements }

extension FinanceKindX on FinanceKind {
  String get collection => switch (this) {
        FinanceKind.chargebacks => 'chargebacks',
        FinanceKind.platformLosses => 'platform_losses',
        FinanceKind.refunds => 'refunds',
        FinanceKind.settlements => 'settlements',
      };

  /// Field each collection is ordered by (single-field index only).
  String get timeField => this == FinanceKind.platformLosses ? 'recordedAt' : 'createdAt';

  String get label => switch (this) {
        FinanceKind.chargebacks => 'Chargebacks',
        FinanceKind.platformLosses => 'Platform losses',
        FinanceKind.refunds => 'Refunds',
        FinanceKind.settlements => 'Settlements',
      };
}

class FinanceRecord {
  const FinanceRecord(this.kind, this.id, this.data);
  final FinanceKind kind;
  final String id;
  final Map<String, dynamic> data;

  String? str(String k) => data[k] is String && (data[k] as String).isNotEmpty ? data[k] as String : null;

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
  DateTime? get at => _date(data[kind.timeField]) ?? _date(data['createdAt']);
  DateTime? get closedAt => _date(data['closedAt']);

  static double? _naira(Object? kobo) => kobo is num ? kobo / 100 : null;

  String? get jobId => str('jobId');
  String? get status => str('status');

  /// The amount that matters for this record, in naira.
  double? get amount => switch (kind) {
        FinanceKind.chargebacks => _naira(data['chargedAmountKobo']),
        FinanceKind.platformLosses => _naira(data['amountKobo']),
        FinanceKind.refunds => _naira(data['amountKobo']),
        FinanceKind.settlements => _naira(data['serviceKobo']) ?? _naira((data['payoutLeg'] as Map?)?['amountKobo']),
      };

  // Chargebacks
  String? get outcome => str('outcome');
  String? get payoutStateAtOpen => str('payoutStateAtOpen');
  String? get investigationStatus => str('investigationStatus');
  bool get open => kind == FinanceKind.chargebacks && status != 'closed';

  // Refunds
  String? get refundKind => str('kind');
  String? get reason => str('reason');
  int get attempts => (data['attempts'] as num?)?.toInt() ?? 0;

  // Settlements
  String? get settlementOutcome => str('settlementOutcome') ?? str('outcome');
  double? get artisanLeg => _naira((data['payoutLeg'] as Map?)?['amountKobo']);
  String? get artisanLegStatus => (data['payoutLeg'] as Map?)?['status'] as String?;
  double? get refundLeg => _naira((data['refundLeg'] as Map?)?['amountKobo']);
  String? get refundLegStatus => (data['refundLeg'] as Map?)?['status'] as String?;
  double? get retained => _naira(data['platformRetainedKobo']);

  // Platform losses
  String? get absorbedBy => str('absorbedBy');
  String? get recoveryStatus => str('recoveryStatus');

  /// Human label for a raw status/outcome identifier ("paystack_resolved"
  /// → "Paystack resolved"); the raw value is shown alongside.
  static String humanise(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final s = raw.replaceAll('_', ' ');
    return s[0].toUpperCase() + s.substring(1);
  }
}
