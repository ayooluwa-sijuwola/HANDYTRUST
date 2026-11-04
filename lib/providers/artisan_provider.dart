import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/safe_firestore.dart';
import '../models/artisan_model.dart';

/// Live stream of a single artisan's profile — reactive to approval/rating changes.
final artisanProfileProvider =
    StreamProvider.family<ArtisanModel?, String>((ref, uid) {
  return safeDocStream(
    FirebaseFirestore.instance.collection('artisans').doc(uid),
    ArtisanModel.fromJson,
    debugLabel: 'artisanProfile:$uid',
  );
});

/// Whether this artisan has completed payout setup (bank_details_screen.dart
/// writes bankName/accountName/accountNumber to artisan_private/{uid} —
/// owner-only per firestore.rules, hence family-keyed by the artisan's own
/// uid, not queryable for anyone else). Read-only — no new writes. Exists
/// so the Earnings screen can tell an artisan *before* they finish a job
/// whether processEscrowRelease's automatic payout is actually set up to
/// succeed, rather than only finding out from a failed transfer later.
final artisanPayoutReadyProvider = StreamProvider.family<bool, String>((ref, uid) {
  return safeDocStream(
    FirebaseFirestore.instance.collection('artisan_private').doc(uid),
    (json) => json,
    debugLabel: 'artisanPrivate:$uid',
  ).map((data) =>
      (data?['bankName'] as String?)?.isNotEmpty == true &&
      (data?['accountNumber'] as String?)?.isNotEmpty == true);
});

/// Approved, real-verified artisans ordered by rating — powers the
/// "Featured Experts" list on the customer Home screen (pixel-matched to
/// Stitch, design/STITCH_IMPLEMENTATION_AUDIT.md). Real data, same
/// approvalStatus filter browse_artisans_screen.dart's own provider uses —
/// this one additionally requires real identity verification (a "Featured"
/// artisan should be one HandyTrust can actually vouch for) and orders by
/// rating so the top few genuinely are the top-rated, not an arbitrary
/// Firestore document order.
final featuredArtisansProvider =
    StreamProvider.autoDispose<List<ArtisanModel>>((ref) {
  return safeStream(
    FirebaseFirestore.instance
        .collection('artisans')
        .where('approvalStatus', isEqualTo: 'approved')
        .where('verificationStatus', whereIn: ['id_verified', 'trusted'])
        .orderBy('rating', descending: true)
        .limit(10),
    (d) => ArtisanModel.fromJson({...d.data(), 'uid': d.id}),
    debugLabel: 'featuredArtisans',
  );
});

/// Artisan reviews summary — count + average.
/// Uses the stored rating/totalRatings on the artisan doc (maintained by
/// the atomic transaction in ReviewScreen and Cloud Functions in production)
/// instead of fetching all review docs.
final artisanReviewsProvider =
    StreamProvider.family<({int count, double avg}), String>((ref, artisanId) {
  return FirebaseFirestore.instance
      .collection('artisans')
      .doc(artisanId)
      .snapshots()
      .map((snap) {
    if (!snap.exists) return (count: 0, avg: 0.0);
    final data = snap.data()!;
    final count = (data['totalRatings'] as num?)?.toInt() ?? 0;
    final avg = (data['rating'] as num?)?.toDouble() ?? 0.0;
    return (count: count, avg: avg);
  }).transform(
    StreamTransformer<({int count, double avg}), ({int count, double avg})>.fromHandlers(
      handleError: (Object e, StackTrace st, sink) {
        debugPrint('[artisanReviewsProvider:$artisanId] stream error swallowed: $e');
        sink.add((count: 0, avg: 0.0));
      },
    ),
  );
});
