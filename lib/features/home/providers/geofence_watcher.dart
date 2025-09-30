import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/mock_api.dart';
import 'presence_controller.dart';

class GeofenceState {
  final bool permissionGranted;
  final int? insideLocationId;
  final bool active;

  const GeofenceState({
    this.permissionGranted = false,
    this.insideLocationId,
    this.active = false,
  });

  GeofenceState copyWith({bool? permissionGranted, int? insideLocationId, bool? active}) {
    return GeofenceState(
      permissionGranted: permissionGranted ?? this.permissionGranted,
      insideLocationId: insideLocationId ?? this.insideLocationId,
      active: active ?? this.active,
    );
  }
}

class GeofenceWatcher extends Notifier<GeofenceState> {
  StreamSubscription? _sub;

  @override
  GeofenceState build() {
    _start();
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    return const GeofenceState();
  }

  Future<void> _start() async {
    final granted = await LocationService.ensurePermission();
    state = state.copyWith(permissionGranted: granted);
    if (!granted) return;

    // Initial check
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      await _evaluatePosition(pos.latitude, pos.longitude);
    }

    _sub?.cancel();
    _sub = LocationService.positionStream().listen((p) {
      _evaluatePosition(p.latitude, p.longitude);
    });
  }

  Future<void> _evaluatePosition(double lat, double lng) async {
    final locations = await MockApi.instance.getLocations();
    int? insideId;
    for (final l in locations) {
      final llat = (l['lat'] as num?)?.toDouble();
      final llng = (l['lng'] as num?)?.toDouble();
      if (llat == null || llng == null) continue;
      final radius = (l['geofence_radius_m'] as num?)?.toDouble() ?? 100.0;
      final d = LocationService.distanceMeters(lat1: lat, lon1: lng, lat2: llat, lon2: llng);
      if (d <= radius) {
        insideId = l['id'] as int?;
        break;
      }
    }

    final presence = ref.read(presenceControllerProvider);
    if (insideId != null) {
      state = state.copyWith(insideLocationId: insideId, active: true);
      if (!presence.active || presence.locationId != insideId) {
        await ref.read(presenceControllerProvider.notifier).checkIn(insideId);
      }
    } else {
      state = state.copyWith(insideLocationId: null, active: false);
      if (presence.active) {
        await ref.read(presenceControllerProvider.notifier).checkOut();
      }
    }
  }
}

final geofenceWatcherProvider = NotifierProvider<GeofenceWatcher, GeofenceState>(
  GeofenceWatcher.new,
);

