// lib/features/connect/providers/members_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_api.dart';

// Local query model to avoid coupling with mock API
class MembersQuery {
  final String tab; // 'nearest' | 'network'
  final String status; // 'Semua' | 'Online' | 'Friends' | 'Partners'
  final String search;
  final int page;
  final int pageSize;
  final int? locationId; // optional
  final double? radiusKm; // optional

  const MembersQuery({
    this.tab = 'nearest',
    this.status = 'Semua',
    this.search = '',
    this.page = 1,
    this.pageSize = 10,
    this.locationId,
    this.radiusKm,
  });

  MembersQuery copyWith({
    String? tab,
    String? status,
    String? search,
    int? page,
    int? pageSize,
    int? locationId,
    double? radiusKm,
  }) {
    return MembersQuery(
      tab: tab ?? this.tab,
      status: status ?? this.status,
      search: search ?? this.search,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      locationId: locationId ?? this.locationId,
      radiusKm: radiusKm ?? this.radiusKm,
    );
  }
}

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
    final result = await SupabaseApi.getMembersOrg5(
      tab: state.query.tab,
      status: state.query.status,
      search: state.query.search,
      page: 1,
      pageSize: state.query.pageSize,
    );
    // Deduplicate items by member_id (fallback to id) to mitigate any BE duplicates
    final raw = List<Map<String, dynamic>>.from(result['items'] ?? const []);
    final seen = <String>{};
    final items = <Map<String, dynamic>>[];
    for (final m in raw) {
      final key = (m['member_id'] ?? m['id'] ?? '').toString();
      if (key.isEmpty) {
        items.add(m);
        continue;
      }
      if (!seen.contains(key)) {
        seen.add(key);
        items.add(m);
      }
    }
    final stats = _computeStats(items, state.query);
    state = state.copyWith(
      members: items,
      isLoading: false,
      total: (result['total'] as int?) ?? items.length,
      hasMore: (result['hasMore'] as bool?) ?? false,
      onlineCount: stats.$1,
      nearbyCount: stats.$2,
    );
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    final nextQuery = state.query.copyWith(page: state.query.page + 1);
    final result = await SupabaseApi.getMembersOrg5(
      tab: nextQuery.tab,
      status: nextQuery.status,
      search: nextQuery.search,
      page: nextQuery.page,
      pageSize: nextQuery.pageSize,
    );
    // Deduplicate in load more as well
    final incoming = List<Map<String, dynamic>>.from(result['items'] ?? const []);
    final seen = <String>{}..addAll(
        state.members.map((m) => (m['member_id'] ?? m['id'] ?? '').toString()),
      );
    final items = <Map<String, dynamic>>[];
    for (final m in incoming) {
      final key = (m['member_id'] ?? m['id'] ?? '').toString();
      if (key.isEmpty || !seen.contains(key)) {
        seen.add(key);
        items.add(m);
      }
    }
    final stats = _computeStats([...state.members, ...items], nextQuery);
    state = state.copyWith(
      members: [...state.members, ...items],
      isLoadingMore: false,
      query: nextQuery,
      total: (result['total'] as int?) ?? (state.members.length + items.length),
      hasMore: (result['hasMore'] as bool?) ?? false,
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
