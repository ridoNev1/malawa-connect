// lib/features/home/providers/presence_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/mock_api.dart';
import 'home_providers.dart';

class PresenceControllerState {
  final bool active;
  final int? locationId;
  final String? locationName;
  final DateTime? checkInAt;
  final bool heartbeatRunning;

  const PresenceControllerState({
    this.active = false,
    this.locationId,
    this.locationName,
    this.checkInAt,
    this.heartbeatRunning = false,
  });

  PresenceControllerState copyWith({
    bool? active,
    int? locationId,
    String? locationName,
    DateTime? checkInAt,
    bool? heartbeatRunning,
  }) {
    return PresenceControllerState(
      active: active ?? this.active,
      locationId: locationId ?? this.locationId,
      locationName: locationName ?? this.locationName,
      checkInAt: checkInAt ?? this.checkInAt,
      heartbeatRunning: heartbeatRunning ?? this.heartbeatRunning,
    );
  }
}

class PresenceController extends Notifier<PresenceControllerState> {
  Timer? _timer;

  @override
  PresenceControllerState build() {
    return const PresenceControllerState();
  }

  Future<void> checkIn(int locationId) async {
    await MockApi.instance.checkIn(locationId: locationId);
    final p = await MockApi.instance.getPresence();
    state = state.copyWith(
      active: true,
      locationId: p?['location_id'] as int?,
      locationName: p?['location_name'] as String?,
      checkInAt: DateTime.tryParse(p?['check_in_time'] ?? ''),
    );
    startHeartbeat();
    ref.invalidate(presenceProvider);
  }

  Future<void> checkOut() async {
    await MockApi.instance.checkOut();
    stopHeartbeat();
    state = const PresenceControllerState();
    ref.invalidate(presenceProvider);
  }

  void startHeartbeat({Duration interval = const Duration(seconds: 60)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => MockApi.instance.heartbeat());
    state = state.copyWith(heartbeatRunning: true);
  }

  void stopHeartbeat() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(heartbeatRunning: false);
  }

  Future<void> beatOnce() async {
    await MockApi.instance.heartbeat();
  }
}

final presenceControllerProvider =
    NotifierProvider<PresenceController, PresenceControllerState>(
  PresenceController.new,
);
