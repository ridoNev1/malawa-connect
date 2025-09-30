// lib/features/connect/pages/connect_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/bottom_navigation.dart';
import '../widgets/stat_card_widget.dart';
import '../widgets/tab_selector_widget.dart';
import '../widgets/filter_chip_widget.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/member_card_widget.dart';
import '../providers/members_provider.dart';

class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage>
    with SingleTickerProviderStateMixin {
  int _selectedTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  String _selectedFilter = 'Semua';
  final List<String> _filterOptions = [
    'Semua',
    'Friends',
    'Partners',
    'Online',
  ];

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Now driven by provider (membersProvider)

  @override
  void initState() {
    super.initState();
    // Load initial members
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(membersProvider.notifier).refresh();
    });
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              // Header with gradient background
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [MC.darkBrown, MC.mediumBrown],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connect',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Temukan teman atau pasangan dengan minat yang sama',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Stats cards (tied to provider state)
                    Consumer(builder: (context, ref, _) {
                      final state = ref.watch(membersProvider);
                      final online = state.onlineCount;
                      final memberTotal = state.total == 0
                          ? state.members.length
                          : state.total;
                      final nearby = state.nearbyCount;
                      return Row(
                        children: [
                          StatCardWidget(
                            count: '$online',
                            label: 'Online',
                            icon: Icons.people,
                          ),
                          const SizedBox(width: 12),
                          StatCardWidget(
                            count: '$memberTotal',
                            label: 'Member',
                            icon: Icons.group,
                          ),
                          const SizedBox(width: 12),
                          StatCardWidget(
                            count: '$nearby',
                            label: 'Nearby',
                            icon: Icons.location_on,
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),

              // Tabs
              TabSelectorWidget(
                selectedTabIndex: _selectedTabIndex,
                onTabSelected: (index) {
                  setState(() {
                    _selectedTabIndex = index;
                  });
                  ref.read(membersProvider.notifier).setTab(index);
                },
              ),

              // Filter chips
              FilterChipWidget(
                selectedFilter: _selectedFilter,
                filterOptions: _filterOptions,
                onFilterSelected: (filter) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                  ref.read(membersProvider.notifier).setFilter(filter);
                },
              ),

              const SizedBox(height: 8),

              // Search Bar
              SearchBarWidget(
                controller: _searchController,
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () {
                    if (!mounted) return;
                    ref.read(membersProvider.notifier).setSearch(value);
                  });
                },
              ),

              const SizedBox(height: 16),

              // Member list
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final state = ref.watch(membersProvider);
                    return RefreshIndicator(
                      onRefresh: () =>
                          ref.read(membersProvider.notifier).refresh(),
                      color: MC.darkBrown,
                      child: state.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : NotificationListener<ScrollNotification>(
                              onNotification: (scrollInfo) {
                                if (scrollInfo.metrics.pixels >=
                                        scrollInfo.metrics.maxScrollExtent -
                                            200 &&
                                    !state.isLoadingMore &&
                                    state.hasMore) {
                                  ref.read(membersProvider.notifier).loadMore();
                                }
                                return false;
                              },
                              child: AnimationLimiter(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 8.0,
                                  ),
                                  itemCount: state.members.length + 1,
                                  itemBuilder: (context, index) {
                                    if (index == state.members.length) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16.0,
                                        ),
                                        child: Center(
                                          child: state.isLoadingMore
                                              ? const CircularProgressIndicator()
                                              : (state.hasMore
                                                    ? const SizedBox.shrink()
                                                    : Text(
                                                        'Semua data sudah ditampilkan',
                                                        style: TextStyle(
                                                          color:
                                                              Colors.grey[500],
                                                        ),
                                                      )),
                                        ),
                                      );
                                    }
                                    final member = state.members[index];
                                    return AnimationConfiguration.staggeredList(
                                      position: index,
                                      duration: const Duration(
                                        milliseconds: 375,
                                      ),
                                      child: SlideAnimation(
                                        verticalOffset: 50.0,
                                        child: FadeInAnimation(
                                          child: MemberCardWidget(
                                            member: member,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 1,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/');
              break;
            case 1:
              context.go('/connect');
              break;
            case 2:
              context.go('/chat');
              break;
            case 3:
              context.go('/profiles');
              break;
          }
        },
      ),
    );
  }
}
