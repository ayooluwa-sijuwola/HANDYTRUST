import 'package:cloud_firestore/cloud_firestore.dart';

/// pending: visible to customer, editable/withdrawable by artisan
/// accepted: the winning quote for the job
/// closed: a competing quote that lost when another was accepted
/// rejected: explicitly turned down by the customer (no accepted quote yet)
/// withdrawn: artisan pulled the quote before any decision
/// expired: not accepted within its validity (policy D5: 48 h after the last
///   server-stamped submission) — server-set; the artisan may resubmit
enum QuoteStatus { pending, accepted, closed, rejected, withdrawn, expired }

QuoteStatus _statusFromString(String? v) => switch (v) {
      'accepted' => QuoteStatus.accepted,
      'closed' => QuoteStatus.closed,
      'rejected' => QuoteStatus.rejected,
      'withdrawn' => QuoteStatus.withdrawn,
      'expired' => QuoteStatus.expired,
      _ => QuoteStatus.pending,
    };

/// A quote document lives at `jobs/{jobId}/quotes/{artisanId}` — the
/// document ID *is* the artisan ID, which structurally enforces "one
/// active quote per artisan per job" (a second submission overwrites the
/// same document rather than creating a competing one).
///
/// Cost breakdown: [laborCost] + [materialsCost] = [amount] (computed getter).
/// Old Firestore docs without [laborCost] degrade gracefully: [laborCost]
/// defaults to the stored `amount` and [materialsCost] to 0.
class QuoteModel {
  final String id; // == artisanId
  final String jobId;
  final String artisanId;
  final double laborCost;
  final double materialsCost;
  final int durationDays;
  final String? notes;
  final QuoteStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Denormalized artisan snapshot at submission time — lets the Quote
  // Inbox render price/duration/rating/trust tier/verification badge
  // without an N+1 read per quote.
  final String artisanName;
  final double artisanRating;
  final String artisanTrustTier;
  final bool artisanVerified;
  final String? artisanProfileImageUrl;
  // Denormalized at submission for sort-by-trust in the comparison UI.
  final double artisanTrustScore;

  double get amount => laborCost + materialsCost;

  const QuoteModel({
    required this.id,
    required this.jobId,
    required this.artisanId,
    required this.laborCost,
    required this.materialsCost,
    required this.durationDays,
    this.notes,
    this.status = QuoteStatus.pending,
    this.createdAt,
    this.updatedAt,
    this.artisanName = '',
    this.artisanRating = 0.0,
    this.artisanTrustTier = 'standard',
    this.artisanVerified = false,
    this.artisanProfileImageUrl,
    this.artisanTrustScore = 0.0,
  });

  factory QuoteModel.fromJson(Map<String, dynamic> json) {
    final storedAmount = (json['amount'] as num?)?.toDouble() ?? 0.0;
    return QuoteModel(
      id: json['id'] as String,
      jobId: json['jobId'] as String,
      artisanId: json['artisanId'] as String,
      // Old docs: laborCost falls back to the stored amount total.
      laborCost: (json['laborCost'] as num?)?.toDouble() ?? storedAmount,
      materialsCost: (json['materialsCost'] as num?)?.toDouble() ?? 0.0,
      durationDays: (json['durationDays'] as num?)?.toInt() ?? 1,
      notes: json['notes'] as String?,
      status: _statusFromString(json['status'] as String?),
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
      artisanName: json['artisanName'] as String? ?? '',
      artisanRating: (json['artisanRating'] as num?)?.toDouble() ?? 0.0,
      artisanTrustTier: json['artisanTrustTier'] as String? ?? 'standard',
      artisanVerified: json['artisanVerified'] as bool? ?? false,
      artisanProfileImageUrl: json['artisanProfileImageUrl'] as String?,
      artisanTrustScore: (json['artisanTrustScore'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'jobId': jobId,
        'artisanId': artisanId,
        'laborCost': laborCost,
        'materialsCost': materialsCost,
        'amount': amount, // backward compat — always equals laborCost + materialsCost
        'durationDays': durationDays,
        if (notes != null) 'notes': notes,
        'status': status.name,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
        'artisanName': artisanName,
        'artisanRating': artisanRating,
        'artisanTrustTier': artisanTrustTier,
        'artisanVerified': artisanVerified,
        if (artisanProfileImageUrl != null)
          'artisanProfileImageUrl': artisanProfileImageUrl,
        'artisanTrustScore': artisanTrustScore,
      };
}
