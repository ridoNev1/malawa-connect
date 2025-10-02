import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InAppPresenceState {
  final Set<String> activeUids;
  const InAppPresenceState({this.activeUids = const {}});

  InAppPresenceState copyWith({Set<String>? activeUids}) =>
      InAppPresenceState(activeUids: activeUids ?? this.activeUids);
}

class InAppPresenceNotifier extends Notifier<InAppPresenceState> {
  RealtimeChannel? _chan;
  Timer? _heartbeat;
  Timer? _prune;
  final Map<String, DateTime> _lastSeen = {};

  @override
  InAppPresenceState build() {
    _start();
    ref.onDispose(() async {
      _heartbeat?.cancel();
      _prune?.cancel();
      if (_chan != null) {
        try {
          await _chan!.unsubscribe();
        } catch (_) {}
      }
    });
    return const InAppPresenceState();
  }

  void _start() {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    // Subscribe to a shared channel for simple in-app activity broadcasts
    _chan = client.channel('app:presence:org5')
      ..onBroadcast(event: 'active', callback: (payload, [ref]) {
        try {
          Map<String, dynamic>? data;
          if (payload is Map) {
            data = (payload['payload'] as Map?)?.cast<String, dynamic>() ?? payload.cast<String, dynamic>();
          }
          final other = (data?['uid'] ?? '').toString();
          if (other.isNotEmpty) {
            _lastSeen[other] = DateTime.now();
            _recompute();
          }
        } catch (_) {}
      })
      ..subscribe();

    // Heartbeat: broadcast current user's activity every 10s when logged in
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      final u = Supabase.instance.client.auth.currentUser?.id;
      if (u != null) {
        try {
          _chan?.sendBroadcastMessage(event: 'active', payload: {'uid': u});
          // Optimistically mark self as active
          _lastSeen[u] = DateTime.now();
          _recompute();
        } catch (_) {}
      }
    });

    // Prune stale entries (>20s)
    _prune?.cancel();
    _prune = Timer.periodic(const Duration(seconds: 10), (_) {
      final now = DateTime.now();
      final toRemove = <String>[];
      _lastSeen.forEach((k, v) {
        if (now.difference(v).inSeconds > 20) toRemove.add(k);
      });
      if (toRemove.isNotEmpty) {
        for (final k in toRemove) {
          _lastSeen.remove(k);
        }
        _recompute();
      }
    });
  }

  void _recompute() {
    state = state.copyWith(activeUids: _lastSeen.keys.toSet());
  }
}

final inAppPresenceProvider =
    NotifierProvider<InAppPresenceNotifier, InAppPresenceState>(
        InAppPresenceNotifier.new);

