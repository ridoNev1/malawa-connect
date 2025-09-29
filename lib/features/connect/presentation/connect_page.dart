// lib/features/connect/pages/connect_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/bottom_navigation.dart';

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
    // Simulate API call
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
                        _buildStatCard('24', 'Online', Icons.people),
                        const SizedBox(width: 12),
                        _buildStatCard('156', 'Member', Icons.group),
                        const SizedBox(width: 12),
                        _buildStatCard('8', 'Nearby', Icons.location_on),
                      ],
                    ),
                  ],
                ),
              ),

              // Tabs with improved design
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 16.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTabIndex = 0;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedTabIndex == 0
                                ? MC.darkBrown
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Terdekat',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _selectedTabIndex == 0
                                  ? Colors.white
                                  : MC.darkBrown,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTabIndex = 1;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedTabIndex == 1
                                ? MC.darkBrown
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Semua Member',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _selectedTabIndex == 1
                                  ? Colors.white
                                  : MC.darkBrown,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Filter chips
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16.0),
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filterOptions.length,
                  itemBuilder: (context, index) {
                    final filter = _filterOptions[index];
                    final isSelected = _selectedFilter == filter;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(filter),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedFilter = selected ? filter : 'Semua';
                          });
                        },
                        backgroundColor: Colors.grey[200],
                        selectedColor: MC.darkBrown,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : MC.darkBrown,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // Search Bar with improved design
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromARGB(30, 0, 0, 0),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Cari member berdasarkan nama atau minat...',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                              },
                              child: Icon(Icons.clear, color: Colors.grey[400]),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {});
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshData,
                  color: MC.darkBrown,
                  child: AnimationLimiter(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: 6,
                      itemBuilder: (context, index) {
                        return AnimationConfiguration.staggeredList(
                          position: index,
                          duration: const Duration(milliseconds: 375),
                          child: SlideAnimation(
                            verticalOffset: 50.0,
                            child: FadeInAnimation(
                              child: _buildMemberCard(index),
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

  Widget _buildStatCard(String count, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  count,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(icon, size: 18, color: Colors.white),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCard(int index) {
    // Sample data for members
    final List<Map<String, dynamic>> members = [
      {
        'name': 'Michael Chen',
        'status': 'Gold Member',
        'distance': '0.5 km',
        'interests': ['Coffee', 'Music', 'Travel'],
        'isConnected': false,
        'isOnline': true,
        'avatar': 'https://randomuser.me/api/portraits/men/32.jpg',
        'lastSeen': 'Sekarang',
      },
      {
        'name': 'Jessica Lee',
        'status': 'Silver Member',
        'distance': '0.8 km',
        'interests': ['Art', 'Photography', 'Books'],
        'isConnected': false,
        'isOnline': true,
        'avatar': 'https://randomuser.me/api/portraits/women/28.jpg',
        'lastSeen': '5 menit lalu',
      },
      {
        'name': 'David Wilson',
        'status': 'Gold Member',
        'distance': '1.2 km',
        'interests': ['Coffee', 'Business', 'Tech'],
        'isConnected': true,
        'isOnline': false,
        'avatar': 'https://randomuser.me/api/portraits/men/36.jpg',
        'lastSeen': '2 jam lalu',
      },
      {
        'name': 'Emma Thompson',
        'status': 'Gold Member',
        'distance': '1.5 km',
        'interests': ['Travel', 'Food', 'Music'],
        'isConnected': false,
        'isOnline': true,
        'avatar': 'https://randomuser.me/api/portraits/women/65.jpg',
        'lastSeen': 'Sekarang',
      },
      {
        'name': 'Robert Garcia',
        'status': 'Silver Member',
        'distance': '2.0 km',
        'interests': ['Sports', 'Music', 'Movies'],
        'isConnected': false,
        'isOnline': false,
        'avatar': 'https://randomuser.me/api/portraits/men/67.jpg',
        'lastSeen': '1 hari lalu',
      },
      {
        'name': 'Sophia Martinez',
        'status': 'Gold Member',
        'distance': '2.5 km',
        'interests': ['Coffee', 'Art', 'Design'],
        'isConnected': false,
        'isOnline': true,
        'avatar': 'https://randomuser.me/api/portraits/women/33.jpg',
        'lastSeen': 'Sekarang',
      },
    ];

    final member = members[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(30, 0, 0, 0),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                // Avatar with online indicator
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: Image.network(
                        member['avatar'],
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 70,
                            height: 70,
                            color: MC.darkBrown.withValues(alpha: 0.1),
                            child: const Icon(
                              Icons.person,
                              size: 35,
                              color: MC.darkBrown,
                            ),
                          );
                        },
                      ),
                    ),
                    // Online indicator
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: member['isOnline'] as bool
                              ? Colors.green
                              : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                // Member Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              member['name'],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: MC.darkBrown,
                              ),
                            ),
                          ),
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: member['status'] == 'Gold Member'
                                  ? Colors.amber[100]
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              member['status'],
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: member['status'] == 'Gold Member'
                                    ? Colors.amber[800]
                                    : Colors.grey[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            member['distance'],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            member['lastSeen'],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Interests
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: (member['interests'] as List<String>).map((
                          interest,
                        ) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: MC.darkBrown.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              interest,
                              style: const TextStyle(
                                fontSize: 11,
                                color: MC.darkBrown,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Handle profile view
                    },
                    icon: const Icon(Icons.person, size: 18),
                    label: const Text('Lihat Profil'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MC.darkBrown,
                      side: const BorderSide(color: MC.darkBrown),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Handle connect action
                      setState(() {
                        member['isConnected'] =
                            !(member['isConnected'] as bool);
                      });
                    },
                    icon: Icon(
                      member['isConnected'] as bool
                          ? Icons.check
                          : Icons.person_add,
                      size: 18,
                    ),
                    label: Text(
                      member['isConnected'] as bool ? 'Terhubung' : 'Connect',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: member['isConnected'] as bool
                          ? Colors.grey[300]
                          : MC.darkBrown,
                      foregroundColor: member['isConnected'] as bool
                          ? Colors.grey[700]
                          : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
