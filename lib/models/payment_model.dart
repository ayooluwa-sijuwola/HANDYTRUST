import 'package:cloud_firestore/cloud_firestore.dart';

/// abandoned / requiresRefund are server-only (Stage 3): a checkout that
/// expired or was superseded, and a captured charge that must not fund the
/// job (paid after cancellation, duplicate, mismatch) — awaiting refund.
/// Stage 4 adds the in-flight money states: releasing (payout transfer
/// initiated, awaiting Paystack confirmation), refundPending (a refund of a
/// non-funding charge is in progress), settling / settled (an admin dispute or
/// cancellation settlement is executing / complete).
enum PaymentStatus {
  pending,
  processing,
  escrowHeld,
  releasing,
  released,
  refundPending,
  refunded,
  settling,
  settled,
  failed,
  abandoned,
  requiresRefund,
  // Stage 7.1: the card issuer reversed the charge (chargeback lost).
  chargedBack,
}

class PaymentModel {
  final String id;
  final String jobId;
  final String payerId;
  final String artisanId;
  /// The artisan's agreed service price (what payout and earnings use).
  final double amount;
  /// Stage 3 fee breakdown — null on payments created before the platform
  /// fee existed, where the customer was charged exactly [amount].
  final double? platformFee;
  final double? totalCharged;
  final PaymentStatus status;
  final String? paystackReference;
  final String? paystackAccessCode;
  final String? authorizationUrl;
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? releasedAt;

  const PaymentModel({
    required this.id,
    required this.jobId,
    required this.payerId,
    required this.artisanId,
    required this.amount,
    this.platformFee,
    this.totalCharged,
    this.status = PaymentStatus.pending,
    this.paystackReference,
    this.paystackAccessCode,
    this.authorizationUrl,
    required this.createdAt,
    this.paidAt,
    this.releasedAt,
  });

  /// What the customer actually paid (service price + platform fee).
  double get chargedTotal => totalCharged ?? amount;

  static DateTime _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return DateTime.tryParse(v as String? ?? '') ?? DateTime.now();
  }

  static DateTime? _parseDateNullable(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    return DateTime.tryParse(v as String? ?? '');
  }

  factory PaymentModel.fromJson(Map<String, dynamic> json) => PaymentModel(
        id: json['id'] as String,
        jobId: json['jobId'] as String,
        payerId: json['payerId'] as String,
        artisanId: json['artisanId'] as String,
        amount: (json['amount'] as num).toDouble(),
        platformFee: (json['platformFee'] as num?)?.toDouble(),
        totalCharged: (json['totalCharged'] as num?)?.toDouble(),
        status: PaymentStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => PaymentStatus.pending,
        ),
        paystackReference: json['paystackReference'] as String?,
        paystackAccessCode: json['paystackAccessCode'] as String?,
        authorizationUrl: json['authorizationUrl'] as String?,
        createdAt: _parseDate(json['createdAt']),
        paidAt: _parseDateNullable(json['paidAt']),
        releasedAt: _parseDateNullable(json['releasedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'payerId': payerId,
        'artisanId': artisanId,
        'amount': amount,
        'status': status.name,
        if (paystackReference != null) 'paystackReference': paystackReference,
        if (paystackAccessCode != null) 'paystackAccessCode': paystackAccessCode,
        if (authorizationUrl != null) 'authorizationUrl': authorizationUrl,
        'createdAt': Timestamp.fromDate(createdAt),
        if (paidAt != null) 'paidAt': Timestamp.fromDate(paidAt!),
        if (releasedAt != null) 'releasedAt': Timestamp.fromDate(releasedAt!),
      };

  PaymentModel copyWith({
    PaymentStatus? status,
    String? paystackReference,
    String? paystackAccessCode,
    String? authorizationUrl,
    DateTime? paidAt,
    DateTime? releasedAt,
  }) =>
      PaymentModel(
        id: id,
        jobId: jobId,
        payerId: payerId,
        artisanId: artisanId,
        amount: amount,
        platformFee: platformFee,
        totalCharged: totalCharged,
        status: status ?? this.status,
        paystackReference: paystackReference ?? this.paystackReference,
        paystackAccessCode: paystackAccessCode ?? this.paystackAccessCode,
        authorizationUrl: authorizationUrl ?? this.authorizationUrl,
        createdAt: createdAt,
        paidAt: paidAt ?? this.paidAt,
        releasedAt: releasedAt ?? this.releasedAt,
      );
}
