// lib/features/connect/providers/members_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/mock_api.dart';

class MembersState {
  final List<Map<String, dynamic>> members;
  final bool isLoading;
  final bool isLoadingMore;
  final MembersQuery query;
  final int total;
  final bool hasMore;
  final int onlineCount;
  final int nearbyCount;

  MembersState({
    required this.members,
    required this.query,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.total = 0,
    this.hasMore = false,
    this.onlineCount = 0,
    this.nearbyCount = 0,
  });

  MembersState copyWith({
    List<Map<String, dynamic>>? members,
    bool? isLoading,
    bool? isLoadingMore,
    MembersQuery? query,
    int? total,
    bool? hasMore,
    int? onlineCount,
    int? nearbyCount,
  }) {
    return MembersState(
      members: members ?? this.members,
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      onlineCount: onlineCount ?? this.onlineCount,
      nearbyCount: nearbyCount ?? this.nearbyCount,
    );
  }
}

class MembersNotifier extends Notifier<MembersState> {
  @override
  MembersState build() {
    return MembersState(
      members: const [],
      query: const MembersQuery(tab: 'nearest', status: 'Semua', page: 1, pageSize: 10),
    );
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, query: state.query.copyWith(page: 1));
    final result = await MockApi.instance.getMembers(state.query);
    final stats = _computeStats(result.items, state.query);
    state = state.copyWith(
      members: result.items,
      isLoading: false,
      total: result.total,
      hasMore: result.hasMore,
      onlineCount: stats.$1,
      nearbyCount: stats.$2,
    );
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    final nextQuery = state.query.copyWith(page: state.query.page + 1);
    final result = await MockApi.instance.getMembers(nextQuery);
    final stats = _computeStats([...state.members, ...result.items], nextQuery);
    state = state.copyWith(
      members: [...state.members, ...result.items],
      isLoadingMore: false,
      query: nextQuery,
      total: result.total,
      hasMore: result.hasMore,
      onlineCount: stats.$1,
      nearbyCount: stats.$2,
    );
  }

  Future<void> setTab(int index) async {
    final tab = index == 0 ? 'nearest' : 'network';
    state = state.copyWith(
      query: state.query.copyWith(tab: tab, page: 1),
    );
    await refresh();
  }

  Future<void> setFilter(String status) async {
    state = state.copyWith(query: state.query.copyWith(status: status, page: 1));
    await refresh();
  }

  Future<void> setSearch(String search) async {
    state = state.copyWith(query: state.query.copyWith(search: search, page: 1));
    await refresh();
  }

  Future<void> setRadius(double radiusKm) async {
    state = state.copyWith(query: state.query.copyWith(radiusKm: radiusKm, page: 1));
    await refresh();
  }

  (int, int) _computeStats(List<Map<String, dynamic>> items, MembersQuery q) {
    int online = 0;
    int nearby = 0;
    for (final m in items) {
      if ((m['isOnline'] as bool?) == true) online++;
    }
    if (q.tab == 'nearest') {
      // When nearest tab is active, list already filtered by base location
      nearby = items.length;
    }
    return (online, nearby);
  }
}

final membersProvider = NotifierProvider.autoDispose<MembersNotifier, MembersState>(
  MembersNotifier.new,
);
