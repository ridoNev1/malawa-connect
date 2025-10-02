import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_api.dart';
import '../../../core/services/local_notifications.dart';

class NotificationsState {
  final List<Map<String, dynamic>> items;
  final bool loading;
  NotificationsState({required this.items, this.loading = false});

  NotificationsState copyWith({
    List<Map<String, dynamic>>? items,
    bool? loading,
  }) {
    return NotificationsState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
    );
  }
}

class NotificationsNotifier extends Notifier<NotificationsState> {
  RealtimeChannel? _channel;
  Timer? _poll;

  @override
  NotificationsState build() {
    ref.onDispose(() async {
      if (_channel != null) {
        try {
          await _channel!.unsubscribe();
        } catch (_) {}
      }
      _poll?.cancel();
    });
    _initRealtime();
    _startPolling();
    // initial load
    Future.microtask(() => refresh());
    return NotificationsState(items: const []);
  }

  void _initRealtime() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    // Subscribe to INSERT/UPDATE for notifications of current user
    _channel = Supabase.instance.client
        .channel('public:notifications:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) async {
            try {
              final dynamic rec = (payload as dynamic).newRecord;
              final type = (rec?['type'] ?? '').toString();
              final title = () {
                if (type == 'newMessage') return 'Pesan baru';
                if (type == 'connectionRequest') return 'Permintaan koneksi';
                if (type == 'connectionAccepted') return 'Koneksi diterima';
                return 'Notifikasi baru';
              }();
              final body = (rec?['message'] ?? '').toString().isNotEmpty
                  ? rec['message'].toString()
                  : (type == 'newMessage' ? 'Ada pesan baru' : '');
              // Show a foreground local notification
              await LocalNotifications.show(title: title, body: body);
              // Lazy import to avoid circulars
            } catch (_) {}
            // To keep consistent shape (with senderName/avatar), just refresh
            await refresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) async {
            await refresh();
          },
        )
        .subscribe();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) async {
      // lightweight refresh; ignore if already loading
      if (!state.loading) {
        await refresh();
      }
    });
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    try {
      final list = await SupabaseApi.getNotificationsOrg5(
        onlyUnread: false,
        limit: 100,
      );
      // Normalize keys to camelCase we use in UI
      final normalized = list.map(_normalizeKeys).toList();
      // Show connection and chat notifications
      final filtered = normalized
          .where(
            (n) =>
                n['type'] == 'connectionAccepted' ||
                n['type'] == 'connectionRequest' ||
                n['type'] == 'newMessage',
          )
          .toList();
      final enriched = await _enrichSender(filtered);
      state = state.copyWith(items: enriched, loading: false);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  // Ensure senderName/senderAvatar are present by fetching profile on demand
  Future<List<Map<String, dynamic>>> _enrichSender(
    List<Map<String, dynamic>> items,
  ) async {
    final futures = <Future<Map<String, dynamic>>>[];
    for (final n in items) {
      final type = n['type']?.toString();
      final senderId = (n['senderId'] ?? n['sender_id'])?.toString();
      final hasName = (n['senderName'] ?? '').toString().trim().isNotEmpty;
      final needsFetch =
          (type == 'connectionRequest' || type == 'connectionAccepted') &&
          !hasName &&
          senderId != null &&
          senderId.isNotEmpty;
      if (!needsFetch) {
        futures.add(Future.value(n));
        continue;
      }
      futures.add(() async {
        try {
          final detail = await SupabaseApi.getMemberDetailOrg5(id: senderId);
          if (detail != null) {
            return {
              ...n,
              'senderName': (detail['name'] ?? n['senderName']),
              'senderAvatar': (detail['avatar'] ?? n['senderAvatar']),
            };
          }
        } catch (_) {}
        return n;
      }());
    }
    return await Future.wait(futures);
  }

  Map<String, dynamic> _normalizeKeys(Map<String, dynamic> n) {
    return {
      ...n,
      'senderId': n['senderId'] ?? n['sender_id'] ?? n['senderid'],
      'senderName': n['senderName'] ?? n['sender_name'] ?? n['sendername'],
      'senderAvatar':
          n['senderAvatar'] ?? n['sender_avatar'] ?? n['senderavatar'],
      'created_at': n['created_at'] ?? n['timestamp'] ?? n['createdAt'],
      'isRead': n['isRead'] ?? n['is_read'] ?? n['isread'],
      'requiresAction':
          n['requiresAction'] ?? n['requires_action'] ?? n['requiresaction'],
    };
  }

  Future<void> markAllRead() async {
    await SupabaseApi.markAllNotificationsReadOrg5();
    await refresh();
  }

  Future<void> accept(String id) async {
    // id here should be requesterId (senderId)
    await SupabaseApi.acceptConnectionRequestOrg5(requesterId: id);
    await refresh();
  }

  Future<void> decline(String id) async {
    // id here should be requesterId (senderId)
    await SupabaseApi.declineConnectionRequestOrg5(requesterId: id);
    await refresh();
  }
}

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, NotificationsState>(
      NotificationsNotifier.new,
    );
