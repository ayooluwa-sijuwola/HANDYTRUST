import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Outcome of an explicit, user-initiated location lookup.
sealed class LocationLookup {
  const LocationLookup();
}

class LocationFound extends LocationLookup {
  const LocationFound(this.latitude, this.longitude, this.address);
  final double latitude;
  final double longitude;
  final String address;
}

class LocationUnavailable extends LocationLookup {
  const LocationUnavailable(this.message);
  final String message;
}

/// Stage 8: moved out of the old job-request screen so the new Post a Job
/// screen holds no platform logic. Called only when the user taps "Use my
/// location" — never in the background (Stage 7 §6).
class LocationService {
  const LocationService();

  Future<LocationLookup> currentArea() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationUnavailable('Location services are turned off. Enable them in Settings, or enter your address manually.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationUnavailable('Location permission was permanently denied. Enable it in Settings, or enter your address manually.');
      }
      if (permission == LocationPermission.denied) {
        return const LocationUnavailable('Location permission denied. Enter your address manually.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      final p = placemarks.isEmpty ? null : placemarks.first;
      final parts = [p?.subLocality, p?.locality, p?.administrativeArea]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
      return LocationFound(position.latitude, position.longitude, parts.join(', '));
    } catch (_) {
      // Services disabled mid-call, platform channel or geocoding failure:
      // never crash or hang — fall back to manual entry.
      return const LocationUnavailable('Could not get your location. Enter your address manually.');
    }
  }
}
