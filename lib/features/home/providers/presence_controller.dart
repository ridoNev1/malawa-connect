// lib/features/home/providers/presence_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_providers.dart';
import 'geofence_watcher.dart';
import '../../../core/services/supabase_api.dart';
import '../../../core/config/env.dart';

class PresenceControllerState {
  final bool active;
  final int? locationId;
  final String? locationName;
  final DateTime? checkInAt;
  final bool heartbeatRunning;
  final DateTime? lastBeatAt;

  const PresenceControllerState({
    this.active = false,
    this.locationId,
    this.locationName,
    this.checkInAt,
    this.heartbeatRunning = false,
    this.lastBeatAt,
  });

  PresenceControllerState copyWith({
    bool? active,
    int? locationId,
    String? locationName,
    DateTime? checkInAt,
    bool? heartbeatRunning,
    DateTime? lastBeatAt,
  }) {
    return PresenceControllerState(
      active: active ?? this.active,
      locationId: locationId ?? this.locationId,
      locationName: locationName ?? this.locationName,
      checkInAt: checkInAt ?? this.checkInAt,
      heartbeatRunning: heartbeatRunning ?? this.heartbeatRunning,
      lastBeatAt: lastBeatAt ?? this.lastBeatAt,
    );
  }
}

class PresenceController extends Notifier<PresenceControllerState> {
  Timer? _timer;
  bool _resumed = false;

  @override
  PresenceControllerState build() {
    // On (hot) restart, resume heartbeat if presence is still active on server
    Future.microtask(_resumeIfActive);
    return const PresenceControllerState();
  }

  Future<void> _resumeIfActive() async {
    if (_resumed) return;
    _resumed = true;
    try {
      final p = await SupabaseApi.getCurrentPresence();
      if (p != null) {
        state = state.copyWith(
          active: true,
          locationId: p['location_id'] as int?,
          locationName: p['location_name'] as String?,
          checkInAt: DateTime.tryParse((p['check_in_time'] ?? '').toString()),
        );
        startHeartbeat();
        // Evaluate geofence once to check if user is still inside radius
        await ref.read(geofenceWatcherProvider.notifier).evaluateOnce();
        await ref.refresh(presenceProvider.future);
      } else {
        // Ensure no stale heartbeat
        stopHeartbeat();
      }
    } catch (e) {
      // silent
    }
  }

  Future<void> checkIn(int locationId) async {
    await SupabaseApi.checkIn(locationId: locationId);
    final p = await SupabaseApi.getCurrentPresence();
    state = state.copyWith(
      active: true,
      locationId: p?['location_id'] as int?,
      locationName: p?['location_name'] as String?,
      checkInAt: DateTime.tryParse((p?['check_in_time'] ?? '').toString()),
    );
    startHeartbeat();
    await ref.refresh(presenceProvider.future);
  }

  Future<void> checkOut() async {
    await SupabaseApi.checkOut();
    stopHeartbeat();
    state = const PresenceControllerState();
    await ref.refresh(presenceProvider.future);
  }

  void startHeartbeat({Duration? interval}) {
    _timer?.cancel();
    final dur = interval ?? Duration(seconds: AppEnv.heartbeatSeconds);
    _timer = Timer.periodic(dur, (_) async {
      try {
        await SupabaseApi.heartbeat();
        final now = DateTime.now();
        state = state.copyWith(lastBeatAt: now);
        // Ensure locations list is fresh in case lat/lng changed server-side
        await ref.refresh(locationsOrg5Provider.future);
        // Re-evaluate geofence so DB state reflects latest location
        await ref.read(geofenceWatcherProvider.notifier).evaluateOnce();
        // Then refresh presence to reflect new server state immediately
        await ref.refresh(presenceProvider.future);
      } catch (e) {
        // silent
      }
    });
    state = state.copyWith(heartbeatRunning: true);
  }

  void stopHeartbeat() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(heartbeatRunning: false);
  }

  Future<void> beatOnce() async {
    await SupabaseApi.heartbeat();
    final now = DateTime.now();
    state = state.copyWith(lastBeatAt: now);
    ref.invalidate(presenceProvider);
  }
}

final presenceControllerProvider =
    NotifierProvider<PresenceController, PresenceControllerState>(
      PresenceController.new,
    );
