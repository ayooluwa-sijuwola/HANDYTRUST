import '../../models/artisan_model.dart';

/// Pure mirror of firestore.rules' `isArtisanEligible()` / `isReallyVerified()`
/// (see design/BETA_TESTING_GUIDE.md). Same relationship as JobService's
/// canConfirmAgreement/canInitPayment predicates have to their own rules
/// mirror: this is the one place the client computes these two questions,
/// used by both the UI (artisan Find Work and quote composer, quote_service.dart) and
/// this file's own tests — not a second, drifting copy of the logic.
///
/// firestore.rules remains the actual security authority regardless of what
/// this class says; a client-side "eligible" here that the server disagrees
/// with just means a confusing UI, not a security hole — the write would
/// still be rejected server-side either way.
abstract final class ArtisanEligibility {
  /// Can this artisan quote / be matched into a job? Mirrors
  /// isArtisanEligible(): approved, AND (really verified OR an
  /// admin-flagged beta tester). betaTester never substitutes for
  /// approval — only for the identity-verification half of the bar.
  static bool canQuote(ArtisanModel artisan) =>
      artisan.approvalStatus == 'approved' &&
      (isReallyVerified(artisan) || artisan.betaTester);

  /// Has this artisan actually completed identity verification? Mirrors
  /// isReallyVerified() — deliberately independent of betaTester/canQuote,
  /// since this is what gates the Verified badge and must stay true
  /// regardless of whether the artisan is also eligible to quote via the
  /// beta bypass. A beta tester is never "really verified" by this check.
  static bool isReallyVerified(ArtisanModel artisan) =>
      artisan.verificationStatus == 'id_verified' ||
      artisan.verificationStatus == 'trusted';
}
