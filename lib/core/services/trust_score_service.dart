import '../../models/artisan_model.dart';

/// Mirrors functions/index.js's _computeTrustScore exactly — for display
/// purposes ONLY. Cloud Functions remain the sole writer of trustScore;
/// Firestore security rules block any client write to that field by design
/// (so no artisan can fabricate their own trust score). This service never
/// writes to Firestore — it only explains and labels the score the server
/// already computed and stored on [ArtisanModel.trustScore].
///
/// Single source of truth for the breakdown shown on TrustScoreCard — avoid
/// re-deriving these weights anywhere else.
///
/// Weights (must match functions/index.js _computeTrustScore exactly):
///   30% Completion rate, 25% Customer ratings, 20% Verification,
///   15% Response speed, 10% Dispute history.
abstract final class TrustScoreService {
  static const Map<String, double> verificationPoints = {
    'unverified': 0,
    'id_submitted': 50,
    'id_verified': 100,
    'trusted': 100,
  };

  static double _responseTimePoints(double minutes) {
    if (minutes <= 15) return 100;
    if (minutes <= 30) return 80;
    if (minutes <= 60) return 60;
    if (minutes <= 120) return 40;
    return 20;
  }

  /// The 5 weighted components behind [ArtisanModel.trustScore], for the
  /// breakdown UI. Computed independently from the stored trustScore, so it
  /// can briefly disagree with it if the server hasn't recomputed yet after
  /// a very recent change (e.g. a review just submitted) — that's expected,
  /// not a bug; the server value is always the authoritative one.
  static List<TrustComponent> breakdown(ArtisanModel artisan) {
    return [
      TrustComponent(
        label: 'Completed Jobs',
        score: (artisan.completedJobs.clamp(0, 50) / 50) * 100 * 0.30,
        maxScore: 30,
      ),
      TrustComponent(
        label: 'Customer Rating',
        score: (artisan.totalRatings > 0 ? (artisan.rating / 5) * 100 : 50) * 0.25,
        maxScore: 25,
      ),
      TrustComponent(
        label: 'Verification',
        score: (verificationPoints[artisan.verificationStatus] ?? 0) * 0.20,
        maxScore: 20,
      ),
      TrustComponent(
        label: 'Response Time',
        score: _responseTimePoints(artisan.responseTimeMinutes) * 0.15,
        maxScore: 15,
      ),
      TrustComponent(
        label: 'Dispute History',
        score: (100 - artisan.openDisputeCount * 25).clamp(0, 100) * 0.10,
        maxScore: 10,
      ),
    ];
  }

  /// 90-100 Excellent / 75-89 Trusted / 60-74 Good / 40-59 Fair / 0-39 New
  static String tierLabel(double score) {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Trusted';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'New';
  }
}
