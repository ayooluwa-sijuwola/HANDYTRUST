import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/services/distance_matching.dart';
import 'package:handy_trust/core/utils/geo.dart';
import 'package:handy_trust/models/artisan_model.dart';
import 'package:handy_trust/models/job_model.dart';
import 'package:handy_trust/models/notification_model.dart';
import 'package:handy_trust/providers/notification_provider.dart';

// Stage 6 (design/REMEDIATION_STAGE6_REPORT_2026-11-03.md): distance-first
// matching (D8), coarse job areas (D9), safe notification deep links.
void main() {
  group('Geo', () {
    test('geohash matches the published reference (and functions/index.js)', () {
      expect(Geo.geohash(57.64911, 10.40744, 11), 'u4pruydqqvj');
    });

    test('neighbourhood contains the own cell and up to 8 neighbours', () {
      final cells = Geo.neighbourhood(6.5244, 3.3792, 4);
      expect(cells, contains(Geo.geohash(6.5244, 3.3792, 4)));
      expect(cells.length, 9);
    });

    test('distance: Ikeja → Lekki is roughly 20–25 km', () {
      final d = Geo.distanceKm(6.6018, 3.3515, 6.4474, 3.4728);
      expect(d, greaterThan(20));
      expect(d, lessThan(25));
    });

    test('coarse area rounds to ~1 km and never leaks a short street address', () {
      final a = Geo.coarseArea(6.52437, 3.37921, '12 Home Street, Ikeja, Lagos')!;
      expect(a['areaLat'], 6.52);
      expect(a['areaLng'], 3.38);
      expect(a['areaLabel'], 'Ikeja, Lagos');
      expect(Geo.coarseArea(6.5, 3.4, '12 Home Street, Lagos')!.containsKey('areaLabel'), isFalse);
      expect(Geo.coarseArea(null, 3.4, 'x'), isNull);
    });

    test('query precision covers the radius', () {
      expect(Geo.precisionForRadius(15), 4);
      expect(Geo.precisionForRadius(25), 3);
    });
  });

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

  group('Distance-first ranking (D8)', () {
    const jobLat = 6.5244, jobLng = 3.3792;

    test('nearer artisans rank first across bands; quality only breaks ties within a band', () {
      final near = artisan('near', lat: 6.5300, lng: 3.3800, rating: 3);    // ~0.6 km
      final mid = artisan('mid', lat: 6.5600, lng: 3.3800, rating: 5);      // ~4 km
      final sameBandBetter = artisan('nearBetter', lat: 6.5310, lng: 3.3790, rating: 5); // ~0.7 km
      final r = DistanceMatching.rankArtisans([mid, near, sameBandBetter],
          jobLat: jobLat, jobLng: jobLng, defaultRadiusKm: 10);
      expect(r.map((e) => e.$1.uid), ['nearBetter', 'near', 'mid']);
      expect(r.first.$2, isNotNull);
    });

    test("an artisan whose own radius doesn't reach the job is excluded", () {
      final far = artisan('far', lat: 6.6018, lng: 3.3515, radius: 5); // ~9 km away, 5 km radius
      final wide = artisan('wide', lat: 6.6018, lng: 3.3515, radius: 15);
      final r = DistanceMatching.rankArtisans([far, wide], jobLat: jobLat, jobLng: jobLng, defaultRadiusKm: 10);
      expect(r.map((e) => e.$1.uid), ['wide']);
    });

    test('artisans without a service area come after nearby ones, not hidden', () {
      final unknown = artisan('unknown', rating: 5);
      final near = artisan('near', lat: 6.5300, lng: 3.3800, rating: 2);
      final r = DistanceMatching.rankArtisans([unknown, near], jobLat: jobLat, jobLng: jobLng, defaultRadiusKm: 10);
      expect(r.map((e) => e.$1.uid), ['near', 'unknown']);
      expect(r.last.$2, isNull);
    });

    test('duplicates (from two verification-status queries) are collapsed', () {
      final a = artisan('a', lat: 6.53, lng: 3.38);
      expect(DistanceMatching.rankArtisans([a, a], jobLat: jobLat, jobLng: jobLng, defaultRadiusKm: 10).length, 1);
    });
  });

  group('Nearby-jobs feed (D8)', () {
    JobModel job(String id, {double? lat, double? lng}) => JobModel(
          id: id, customerId: 'c', category: 'Plumbing', description: 'x',
          createdAt: DateTime(2026, 1, 1), areaLat: lat, areaLng: lng,
        );

    test('within radius by distance, jobs without an area last, far jobs hidden', () {
      final me = artisan('me', lat: 6.5244, lng: 3.3792, radius: 10);
      final r = DistanceMatching.filterJobsForArtisan([
        job('far', lat: 6.4474, lng: 3.4728),
        job('noArea'),
        job('mid', lat: 6.5600, lng: 3.3800),
        job('near', lat: 6.5300, lng: 3.3800),
      ], me, defaultRadiusKm: 10);
      expect(r.map((j) => j.id), ['near', 'mid', 'noArea']);
    });

    test('no service area set → feed unchanged', () {
      final jobs = [job('a', lat: 6.5, lng: 3.4), job('b')];
      expect(DistanceMatching.filterJobsForArtisan(jobs, artisan('me'), defaultRadiusKm: 10), jobs);
    });
  });

  group('Notification deep links (HT-026)', () {
    test('in-app routes are followed; anything else falls back safely', () {
      expect(safeNotificationRoute('/job/abc'), '/job/abc');
      expect(safeNotificationRoute('/dispute/abc'), '/dispute/abc');
      expect(safeNotificationRoute(null), '/notifications');
      expect(safeNotificationRoute('https://evil.example'), '/notifications');
      expect(safeNotificationRoute('//evil.example'), '/notifications');
      expect(safeNotificationRoute('/admin/users'), '/notifications');
    });

    test('NotificationModel carries the server route', () {
      final n = NotificationModel.fromJson({
        'id': 'n1', 'userId': 'u', 'type': 'job_status_update', 'title': 't', 'body': 'b',
        'isRead': false, 'jobId': 'j1', 'route': '/job/j1',
      });
      expect(n.route, '/job/j1');
    });
  });

  test('JobModel parses the coarse area and payout mirror', () {
    final j = JobModel.fromJson({
      'id': 'j1', 'customerId': 'c', 'status': 'completed', 'areaLat': 6.52, 'areaLng': 3.38,
      'areaGeohash4': 's14j', 'areaLabel': 'Ikeja, Lagos', 'payoutStatus': 'processing',
    });
    expect(j.areaLabel, 'Ikeja, Lagos');
    expect(j.areaLat, 6.52);
    expect(j.payoutStatus, 'processing');
    expect(j.customerAddress, isNull);
  });
}
