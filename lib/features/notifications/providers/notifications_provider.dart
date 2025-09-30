import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/mock_api.dart';

class NotificationsState {
  final List<Map<String, dynamic>> items;
  final bool loading;
  NotificationsState({required this.items, this.loading = false});

  NotificationsState copyWith({List<Map<String, dynamic>>? items, bool? loading}) {
    return NotificationsState(items: items ?? this.items, loading: loading ?? this.loading);
  }
}

class NotificationsNotifier extends Notifier<NotificationsState> {
  @override
  NotificationsState build() => NotificationsState(items: const []);

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    final list = await MockApi.instance.getNotifications();
    state = state.copyWith(items: list, loading: false);
  }

  Future<void> markAllRead() async {
    await MockApi.instance.markAllNotificationsRead();
    await refresh();
  }

  Future<void> accept(String id) async {
    await MockApi.instance.acceptConnectionRequest(id);
    await refresh();
  }

  Future<void> decline(String id) async {
    await MockApi.instance.declineConnectionRequest(id);
    await refresh();
  }
}

final notificationsProvider = NotifierProvider<NotificationsNotifier, NotificationsState>(
  NotificationsNotifier.new,
);

