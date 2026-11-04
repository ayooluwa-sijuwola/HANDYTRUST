import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/artisan_model.dart';
import '../utils/geo.dart';
import 'distance_matching.dart';

/// Distance-first artisan matching for a job (Stage 6, policy D8).
///
/// Only approved artisans with a verified identity are ever returned
/// (approvalStatus == 'approved' AND verificationStatus in id_verified /
/// trusted) — the same bar firestore.rules enforce for public discovery.
///
/// Previously: one category-wide query capped at 100 documents, then a
/// proximity *bonus* of at most 10% — so the nearest artisans could be cut
/// by the cap, and distance barely affected order. Now, when the customer's
/// location is known, candidates are fetched by geohash neighbourhood
/// around the job (so the cap applies to nearby artisans), filtered to those
/// whose own service radius covers the job, and ranked by distance first
/// (see [DistanceMatching.rankArtisans]). Artisans who haven't set a
/// service area yet are appended after nearby ones rather than hidden.
class MatchingService {
  final FirebaseFirestore _db;

  MatchingService(this._db);

  static const _verifiedStatuses = ['id_verified', 'trusted'];
  static const maxResults = 8;

  Query<Map<String, dynamic>> _base(String category, String verificationStatus) => _db
      .collection('artisans')
      .where('category', isEqualTo: category)
      .where('isAvailable', isEqualTo: true)
      .where('approvalStatus', isEqualTo: 'approved')
      .where('verificationStatus', isEqualTo: verificationStatus);

  Future<List<ArtisanModel>> findMatches({
    required String category,
    double? customerLat,
    double? customerLng,
    double defaultRadiusKm = 10,
    double maxRadiusKm = 25,
  }) async {
    final candidates = <ArtisanModel>[];
    ArtisanModel parse(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
        ArtisanModel.fromJson({...d.data(), 'uid': d.id});

    if (customerLat != null && customerLng != null) {
      final precision = Geo.precisionForRadius(maxRadiusKm);
      final cells = Geo.neighbourhood(customerLat, customerLng, precision);
      final field = precision == 4 ? 'serviceGeohash4' : 'serviceGeohash3';
      for (final status in _verifiedStatuses) {
        final snap = await _base(category, status).where(field, whereIn: cells).limit(100).get();
        candidates.addAll(snap.docs.map(parse));
      }
    }

    var ranked = DistanceMatching.rankArtisans(
      candidates,
      jobLat: customerLat,
      jobLng: customerLng,
      defaultRadiusKm: defaultRadiusKm,
    );

    // Fallback so existing artisans without a service area (and jobs without
    // a customer location) still get results.
    if (ranked.length < maxResults) {
      final fallback = <ArtisanModel>[];
      for (final status in _verifiedStatuses) {
        final snap = await _base(category, status).limit(50).get();
        fallback.addAll(snap.docs.map(parse).where((a) =>
            customerLat == null || a.latitude == null || a.longitude == null));
      }
      final have = ranked.map((e) => e.$1.uid).toSet();
      ranked = [
        ...ranked,
        ...DistanceMatching.rankArtisans(
          fallback.where((a) => !have.contains(a.uid)).toList(),
          jobLat: null,
          jobLng: null,
          defaultRadiusKm: defaultRadiusKm,
        ),
      ];
    }

    return ranked.take(maxResults).map((e) => e.$1).toList();
  }
}
