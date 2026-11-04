import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/distance_matching.dart';
import 'package:handy_trust/core/utils/geo.dart';
import 'package:handy_trust/models/artisan_model.dart';
import 'package:handy_trust/models/job_model.dart';

// Stage 7 (design/REMEDIATION_STAGE7_REPORT_2026-11-03.md §8): matching and
// location edge cases on top of test/stage6_test.dart.
void main() {
  const jobLat = 6.5244, jobLng = 3.3792;

  ArtisanModel artisan(String id, {double? lat, double? lng, double? radius, double rating = 4}) => ArtisanModel(
        uid: id,
        name: id,
        createdAt: DateTime(2026, 1, 1),
        latitude: lat,
        longitude: lng,
        serviceRadiusKm: radius,
        rating: rating,
        totalJobs: 10,
        completedJobs: 9,
      );

  List<String> rank(List<ArtisanModel> a, {double? lat = jobLat, double? lng = jobLng}) =>
      DistanceMatching.rankArtisans(a, jobLat: lat, jobLng: lng, defaultRadiusKm: 10).map((e) => e.$1.uid).toList();

  group('Radius boundary', () {
    test('exactly on the radius is inside (inclusive); just beyond is outside', () {
      const aLat = 6.6018, aLng = 3.3515;
      final d = Geo.distanceKm(jobLat, jobLng, aLat, aLng);
      expect(rank([artisan('edge', lat: aLat, lng: aLng, radius: d)]), ['edge']);
      expect(rank([artisan('short', lat: aLat, lng: aLng, radius: d - 0.001)]), isEmpty);
    });

    test('artisan without own radius uses the configured default (10 km)', () {
      // ~9 km away → inside default; ~22 km away → outside
      expect(rank([artisan('d9', lat: 6.6018, lng: 3.3515)]), ['d9']);
      expect(rank([artisan('d22', lat: 6.4474, lng: 3.4728)]), isEmpty);
    });

    test('zero / negative radius falls back to the default instead of excluding everyone', () {
      expect(DistanceMatching.radiusFor(artisan('z', radius: 0), 10), 10);
      expect(DistanceMatching.radiusFor(artisan('n', radius: -5), 10), 10);
    });

    test('configured max radius (25 km) selects a geohash precision whose 3x3 cells cover it', () {
      for (final r in [5.0, 10.0, 19.0, 25.0]) {
        final p = Geo.precisionForRadius(r);
        final (dLat, dLng) = Geo.cellSize(p);
        // one full neighbouring cell on each side → coverage ≥ one cell size
        expect(dLat * 111.0, greaterThanOrEqualTo(r), reason: 'lat cover for $r km');
        expect(dLng * 111.0, greaterThanOrEqualTo(r), reason: 'lng cover for $r km');
      }
    });
  });

  group('Missing / invalid coordinates', () {
    test('job without coordinates → everyone is "unknown distance", ranked by quality, none hidden', () {
      final r = DistanceMatching.rankArtisans(
          [artisan('lo', lat: 6.53, lng: 3.38, rating: 2), artisan('hi', lat: 6.6, lng: 3.35, rating: 5)],
          jobLat: null, jobLng: null, defaultRadiusKm: 10);
      expect(r.map((e) => e.$1.uid), ['hi', 'lo']);
      expect(r.every((e) => e.$2 == null), isTrue);
    });

    test('NaN artisan coordinates are dropped, never ranked as "nearest"', () {
      expect(rank([artisan('nan', lat: double.nan, lng: 3.38), artisan('ok', lat: 6.53, lng: 3.38)]), ['ok']);
    });

    test('out-of-range coordinates give no coarse area (nothing written to the job)', () {
      expect(Geo.coarseArea(91, 3.4, 'a, b, c'), isNull);
      expect(Geo.coarseArea(6.5, 181, 'a, b, c'), isNull);
    });
  });

  group('Changed location', () {
    test('moving the artisan re-ranks on the next query (no cached distance)', () {
      final before = artisan('m', lat: 6.4474, lng: 3.4728); // ~22 km — out
      expect(rank([before]), isEmpty);
      final after = artisan('m', lat: 6.5300, lng: 3.3800); // moved close — in
      expect(rank([after]), ['m']);
    });

    test('nearby-jobs feed follows the artisan\'s new location', () {
      JobModel job(String id, double lat, double lng) => JobModel(
          id: id, customerId: 'c', category: 'Plumbing', description: 'x',
          createdAt: DateTime(2026, 1, 1), areaLat: lat, areaLng: lng);
      final jobs = [job('ikeja', 6.60, 3.35), job('lekki', 6.45, 3.47)];
      final atIkeja = artisan('me', lat: 6.6018, lng: 3.3515, radius: 5);
      final atLekki = artisan('me', lat: 6.4474, lng: 3.4728, radius: 5);
      expect(DistanceMatching.filterJobsForArtisan(jobs, atIkeja, defaultRadiusKm: 10).map((j) => j.id), ['ikeja']);
      expect(DistanceMatching.filterJobsForArtisan(jobs, atLekki, defaultRadiusKm: 10).map((j) => j.id), ['lekki']);
    });
  });

  group('Sorting stability', () {
    test('same band, same score → nearer first', () {
      expect(rank([artisan('b', lat: 6.5310, lng: 3.3790), artisan('a', lat: 6.5250, lng: 3.3792)]), ['a', 'b']);
    });

    test('a 5-star artisan 3 km away never outranks a 1-star artisan 0.5 km away (distance-first)', () {
      expect(rank([artisan('far5', lat: 6.5514, lng: 3.3792, rating: 5), artisan('near1', lat: 6.5289, lng: 3.3792, rating: 1)]),
          ['near1', 'far5']);
    });
  });
}
