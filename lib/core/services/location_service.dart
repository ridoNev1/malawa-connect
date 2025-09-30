import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<bool> ensurePermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  static Future<Position?> getCurrentPosition() async {
    final ok = await ensurePermission();
    if (!ok) return null;
    try {
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  static Stream<Position> positionStream({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration interval = const Duration(seconds: 20),
    double distanceFilterMeters = 15,
  }) {
    final settings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
    );
    // Geolocator doesn't support interval directly on all platforms; rely on distanceFilter.
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  // Haversine distance in meters
  static double distanceMeters({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    const R = 6371000.0; // meters
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180.0);
}

