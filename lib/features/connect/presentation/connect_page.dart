// lib/features/connect/pages/connect_page.dart
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

class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage>
    with SingleTickerProviderStateMixin {
  int _selectedTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();

  String _selectedFilter = 'Semua';
  final List<String> _filterOptions = [
    'Semua',
    'Friends',
    'Partners',
    'Online',
  ];

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Sample data for members
  final List<Map<String, dynamic>> _members = [
    {
      'id': '1',
      'name': 'Michael Chen',
      'distance': '0.5 km',
      'interests': ['Coffee', 'Music', 'Travel'],
      'isConnected': false,
      'isOnline': true,
      'avatar': 'https://randomuser.me/api/portraits/men/32.jpg',
      'lastSeen': 'Sekarang',
      'age': 35,
      'gender': 'Laki-laki',
    },
    {
      'id': '2',
      'name': 'Jessica Lee',
      'distance': '0.8 km',
      'interests': ['Art', 'Photography', 'Books'],
      'isConnected': false,
      'isOnline': true,
      'avatar': 'https://randomuser.me/api/portraits/women/28.jpg',
      'lastSeen': '5 menit lalu',
      'age': 28,
      'gender': 'Perempuan',
    },
    {
      'id': '3',
      'name': 'David Wilson',
      'distance': '1.2 km',
      'interests': ['Coffee', 'Business', 'Tech'],
      'isConnected': true,
      'isOnline': false,
      'avatar': 'https://randomuser.me/api/portraits/men/36.jpg',
      'lastSeen': '2 jam lalu',
      'age': 38,
      'gender': 'Laki-laki',
    },
    {
      'id': '4',
      'name': 'Emma Thompson',
      'distance': '1.5 km',
      'interests': ['Travel', 'Food', 'Music'],
      'isConnected': false,
      'isOnline': true,
      'avatar': 'https://randomuser.me/api/portraits/women/65.jpg',
      'lastSeen': 'Sekarang',
      'age': 30,
      'gender': 'Perempuan',
    },
    {
      'id': '5',
      'name': 'Robert Garcia',
      'distance': '2.0 km',
      'interests': ['Sports', 'Music', 'Movies'],
      'isConnected': false,
      'isOnline': false,
      'avatar': 'https://randomuser.me/api/portraits/men/67.jpg',
      'lastSeen': '1 hari lalu',
      'age': 32,
      'gender': 'Laki-laki',
    },
    {
      'id': '6',
      'name': 'Sophia Martinez',
      'distance': '2.5 km',
      'interests': ['Coffee', 'Art', 'Design'],
      'isConnected': false,
      'isOnline': true,
      'avatar': 'https://randomuser.me/api/portraits/women/33.jpg',
      'lastSeen': 'Sekarang',
      'age': 27,
      'gender': 'Perempuan',
    },
  ];

  List<Map<String, dynamic>> get _filteredMembers {
    List<Map<String, dynamic>> result = List.from(_members);

    // Apply tab filter
    if (_selectedTabIndex == 0) {
      // Nearest tab - could add distance filtering logic here
    }

    // Apply status filter
    if (_selectedFilter != 'Semua') {
      if (_selectedFilter == 'Online') {
        result = result.where((m) => m['isOnline'] as bool).toList();
      } else if (_selectedFilter == 'Friends') {
        result = result.where((m) => m['isConnected'] as bool).toList();
      } else if (_selectedFilter == 'Partners') {
        // Could add partner filtering logic here
      }
    }

    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      result = result.where((m) {
        final name = (m['name'] as String).toLowerCase();
        final interests = (m['interests'] as List<String>)
            .map((i) => i.toLowerCase())
            .join(' ');
        return name.contains(query) || interests.contains(query);
      }).toList();
    }

    return result;
  }

  @override
  void initState() {
    super.initState();
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
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(seconds: 1));
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

                    // Stats cards
                    Row(
                      children: [
                        StatCardWidget(
                          count: '24',
                          label: 'Online',
                          icon: Icons.people,
                        ),
                        const SizedBox(width: 12),
                        StatCardWidget(
                          count: '156',
                          label: 'Member',
                          icon: Icons.group,
                        ),
                        const SizedBox(width: 12),
                        StatCardWidget(
                          count: '8',
                          label: 'Nearby',
                          icon: Icons.location_on,
                        ),
                      ],
                    ),
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
                },
              ),

              const SizedBox(height: 8),

              // Search Bar
              SearchBarWidget(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {});
                },
              ),

              const SizedBox(height: 16),

              // Member list
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshData,
                  color: MC.darkBrown,
                  child: AnimationLimiter(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: _filteredMembers.length,
                      itemBuilder: (context, index) {
                        final member = _filteredMembers[index];
                        return AnimationConfiguration.staggeredList(
                          position: index,
                          duration: const Duration(milliseconds: 375),
                          child: SlideAnimation(
                            verticalOffset: 50.0,
                            child: FadeInAnimation(
                              // Hapus parameter onConnectToggled
                              child: MemberCardWidget(member: member),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
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
