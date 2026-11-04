import '../../models/artisan_model.dart';
import '../../models/job_model.dart';
import '../utils/geo.dart';

/// Stage 6 (policy D8): distance-first ordering. Pure, so the exact ranking
/// rules are unit-tested (test/stage6_test.dart).
///
/// An artisan is "in range" when the job is within THEIR service radius
/// (default from config). In-range results are ordered by distance in 2 km
/// bands, then by match quality inside a band — so a strong artisan 1.5 km
/// away isn't ranked below a weak one 1.2 km away, but nobody far away
/// outranks someone near. Artisans/jobs with no location yet come after all
/// in-range results (they are not hidden, so existing artisans who haven't
/// set a service area don't vanish).
class DistanceMatching {
  static const bandKm = 2.0;

  static double radiusFor(ArtisanModel a, double defaultRadiusKm) =>
      (a.serviceRadiusKm != null && a.serviceRadiusKm! > 0) ? a.serviceRadiusKm! : defaultRadiusKm;

  /// (artisan, distanceKm or null) — in-range first by distance band, then
  /// score; then artisans without a location, by score. Out-of-range dropped.
  static List<(ArtisanModel, double?)> rankArtisans(
    List<ArtisanModel> candidates, {
    required double? jobLat,
    required double? jobLng,
    required double defaultRadiusKm,
  }) {
    final inRange = <(ArtisanModel, double)>[];
    final unknown = <ArtisanModel>[];
    final seen = <String>{};
    for (final a in candidates) {
      if (!seen.add(a.uid)) continue;
      if (jobLat == null || jobLng == null || a.latitude == null || a.longitude == null) {
        unknown.add(a);
        continue;
      }
      final d = Geo.distanceKm(jobLat, jobLng, a.latitude!, a.longitude!);
      if (d <= radiusFor(a, defaultRadiusKm)) inRange.add((a, d));
    }
    inRange.sort((x, y) {
      final band = (x.$2 / bandKm).floor().compareTo((y.$2 / bandKm).floor());
      if (band != 0) return band;
      final score = y.$1.matchScore.compareTo(x.$1.matchScore);
      return score != 0 ? score : x.$2.compareTo(y.$2);
    });
    unknown.sort((x, y) => y.matchScore.compareTo(x.matchScore));
    return [
      for (final e in inRange) (e.$1, e.$2),
      for (final a in unknown) (a, null),
    ];
  }

  /// Open-jobs feed for an artisan: jobs within their radius by distance,
  /// then jobs with no area. Without an artisan location, everything is
  /// returned unchanged (they're prompted to set a service area).
  static List<JobModel> filterJobsForArtisan(
    List<JobModel> jobs,
    ArtisanModel? artisan, {
    required double defaultRadiusKm,
  }) {
    if (artisan?.latitude == null || artisan?.longitude == null) return jobs;
    final radius = radiusFor(artisan!, defaultRadiusKm);
    final near = <(JobModel, double)>[];
    final noArea = <JobModel>[];
    for (final j in jobs) {
      if (j.areaLat == null || j.areaLng == null) {
        noArea.add(j);
        continue;
      }
      final d = Geo.distanceKm(artisan.latitude!, artisan.longitude!, j.areaLat!, j.areaLng!);
      if (d <= radius) near.add((j, d));
    }
    near.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final e in near) e.$1, ...noArea];
  }
}
