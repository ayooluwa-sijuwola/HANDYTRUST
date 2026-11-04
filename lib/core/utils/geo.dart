import 'dart:math' as math;

/// Stage 6 geo helpers for distance-first matching (policy D8) and coarse
/// job areas (P-K, policy D9). Pure — no Firestore, no platform plugins.
/// The geohash encoding matches functions/index.js `_geohashEncode` exactly,
/// so client- and server-written geohashes are interchangeable.
class Geo {
  static const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  static String geohash(double lat, double lng, int precision) {
    var latMin = -90.0, latMax = 90.0, lngMin = -180.0, lngMax = 180.0;
    final out = StringBuffer();
    var idx = 0, bit = 0;
    var evenBit = true;
    while (out.length < precision) {
      if (evenBit) {
        final mid = (lngMin + lngMax) / 2;
        if (lng >= mid) {
          idx = idx * 2 + 1;
          lngMin = mid;
        } else {
          idx *= 2;
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (lat >= mid) {
          idx = idx * 2 + 1;
          latMin = mid;
        } else {
          idx *= 2;
          latMax = mid;
        }
      }
      evenBit = !evenBit;
      if (++bit == 5) {
        out.write(_base32[idx]);
        bit = 0;
        idx = 0;
      }
    }
    return out.toString();
  }

  /// Cell size (degrees) for a geohash precision: (latSpan, lngSpan).
  static (double, double) cellSize(int precision) {
    final lngBits = (precision * 5 / 2).ceil();
    final latBits = (precision * 5 / 2).floor();
    return (180 / math.pow(2, latBits), 360 / math.pow(2, lngBits));
  }

  /// The cell containing (lat, lng) and its 8 neighbours — the candidate
  /// cells for a radius query no larger than one cell size.
  static List<String> neighbourhood(double lat, double lng, int precision) {
    final (dLat, dLng) = cellSize(precision);
    final cells = <String>{};
    for (final i in const [-1, 0, 1]) {
      for (final j in const [-1, 0, 1]) {
        final la = (lat + i * dLat).clamp(-89.999999, 89.999999);
        var lo = lng + j * dLng;
        if (lo > 180) lo -= 360;
        if (lo < -180) lo += 360;
        cells.add(geohash(la.toDouble(), lo, precision));
      }
    }
    return cells.toList();
  }

  /// Geohash precision whose 3x3 neighbourhood safely covers [radiusKm]
  /// (precision-4 cells are ~19.5 km tall; precision-3 ~156 km).
  static int precisionForRadius(double radiusKm) => radiusKm <= 19 ? 4 : 3;

  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    return r * 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  /// "12 Home Street, Ikeja, Lagos" → "Ikeja, Lagos": the last two parts,
  /// only when there are at least three, so a street line never leaks.
  /// Mirrors functions/index.js `_areaLabel`.
  static String? areaLabel(String? address) {
    if (address == null) return null;
    final parts = address.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return parts.length >= 3 ? parts.sublist(parts.length - 2).join(', ') : null;
  }

  /// Coarse, publicly-visible job area (~1 km). Mirrors `_coarseArea`.
  static Map<String, dynamic>? coarseArea(double? lat, double? lng, String? address) {
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) return null;
    return {
      'areaLat': (lat * 100).roundToDouble() / 100,
      'areaLng': (lng * 100).roundToDouble() / 100,
      'areaGeohash3': geohash(lat, lng, 3),
      'areaGeohash4': geohash(lat, lng, 4),
      'areaLabel': ?areaLabel(address),
    };
  }
}
