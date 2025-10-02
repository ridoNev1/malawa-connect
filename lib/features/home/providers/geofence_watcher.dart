import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:malawa_connect/features/home/providers/home_providers.dart';
import '../../../core/services/location_service.dart';
import 'presence_controller.dart';
import '../../../core/config/env.dart';

class GeofenceState {
  final bool permissionGranted;
  final int? insideLocationId;
  final bool active;

  const GeofenceState({
    this.permissionGranted = false,
    this.insideLocationId,
    this.active = false,
  });

  GeofenceState copyWith({
    bool? permissionGranted,
    int? insideLocationId,
    bool? active,
  }) {
    return GeofenceState(
      permissionGranted: permissionGranted ?? this.permissionGranted,
      insideLocationId: insideLocationId ?? this.insideLocationId,
      active: active ?? this.active,
    );
  }
}

class GeofenceWatcher extends Notifier<GeofenceState> {
  StreamSubscription? _sub;
  Timer? _poll;

  @override
  GeofenceState build() {
    _start();
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
      _poll?.cancel();
      _poll = null;
    });
    return const GeofenceState();
  }

  Future<void> _start() async {
    // Preload locations from BE to ensure RPC call shows in network
    try {
      // Use provider to allow caching and consistent behavior
      // Ignore result; geofence evaluation fetches again if needed
      await ref.read(locationsOrg5Provider.future);
    } catch (_) {}

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

    // Fallback poll: ensure periodic evaluation even when stream is quiet
    _poll?.cancel();
    _poll = Timer.periodic(Duration(seconds: AppEnv.geofencePollSeconds), (
      _,
    ) async {
      // silent poll in production
      await evaluateOnce();
    });
  }

  Future<void> _evaluatePosition(double lat, double lng) async {
    // Debug override for testing in Simulator/emulator
    if (AppEnv.geofenceDebug &&
        AppEnv.debugLat != null &&
        AppEnv.debugLng != null) {
      lat = AppEnv.debugLat!;
      lng = AppEnv.debugLng!;
    }
    // Use provider so RPC is tracked consistently and cached
    List<Map<String, dynamic>> locations = await ref.read(
      locationsOrg5Provider.future,
    );
    int? insideId;

    // Find nearest location with valid coordinates
    double? nearestDist;
    Map<String, dynamic>? nearestLoc;

    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    for (final l in locations) {
      final llat = toDouble(l['lat']);
      final llng = toDouble(l['lng']);
      if (llat == null || llng == null) continue;
      final d = LocationService.distanceMeters(
        lat1: lat,
        lon1: lng,
        lat2: llat,
        lon2: llng,
      );
      if (nearestDist == null || d < nearestDist) {
        nearestDist = d;
        nearestLoc = l;
      }
    }

    // silent diagnostics removed

    if (nearestLoc != null && nearestDist != null) {
      final radius = toDouble(nearestLoc['geofence_radius_m']) ?? 100.0;
      final isInside = nearestDist <= radius;
      // silent diagnostics removed
      if (isInside) {
        insideId = nearestLoc['id'] as int?;
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

  // Public: force a single geofence evaluation (e.g., from heartbeat)
  Future<void> evaluateOnce() async {
    try {
      // Force refresh latest locations from server
      await ref.refresh(locationsOrg5Provider.future);
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        await _evaluatePosition(pos.latitude, pos.longitude);
        return;
      }
      // If no position available but debug override exists, use it
      if (AppEnv.geofenceDebug &&
          AppEnv.debugLat != null &&
          AppEnv.debugLng != null) {
        await _evaluatePosition(AppEnv.debugLat!, AppEnv.debugLng!);
      }
    } catch (_) {}
  }
}

final geofenceWatcherProvider =
    NotifierProvider<GeofenceWatcher, GeofenceState>(GeofenceWatcher.new);
