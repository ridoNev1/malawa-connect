// lib/features/profile/pages/profile_view_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/bottom_navigation.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_header_widget.dart';
import '../widgets/personal_info_view_widget.dart';
import '../widgets/preference_view_widget.dart';
import '../widgets/interests_view_widget.dart';
import '../widgets/gallery_view_widget.dart';

class ProfileViewPage extends ConsumerStatefulWidget {
  final String userId;

  const ProfileViewPage({super.key, required this.userId});

  @override
  ConsumerState<ProfileViewPage> createState() => _ProfileViewPageState();
}

class _ProfileViewPageState extends ConsumerState<ProfileViewPage> {
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    // Load user data based on userId
    Future.microtask(
      () => ref.read(profileProvider.notifier).loadUserDataById(widget.userId),
    );
  }

  void _handleConnectionChanged(bool isConnected) {
    setState(() {
      _isConnected = isConnected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileProvider);

    if (state.isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Profil Member',
            style: TextStyle(color: MC.darkBrown, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/connect');
              }
            },
            icon: const Icon(Icons.arrow_back, color: MC.darkBrown),
          ),
        ),
        body: Center(child: CircularProgressIndicator(color: MC.darkBrown)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Profil Member',
          style: TextStyle(color: MC.darkBrown, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/connect');
            }
          },
          icon: const Icon(Icons.arrow_back, color: MC.darkBrown),
        ),
        actions: [
          IconButton(
            onPressed: () {
              // Handle message action
              _showMessageDialog(context);
            },
            icon: const Icon(Icons.message, color: MC.darkBrown),
          ),
          IconButton(
            onPressed: () {
              // Handle more options
              _showMoreOptions(context);
            },
            icon: const Icon(Icons.more_vert, color: MC.darkBrown),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ProfileHeaderWidget(
              isEditable: false,
              userId: widget.userId,
              isConnected: _isConnected,
              onConnectionChanged: _handleConnectionChanged,
            ),
            const SizedBox(height: 32),
            const PersonalInfoViewWidget(),
            const SizedBox(height: 32),
            const PreferenceViewWidget(),
            const SizedBox(height: 32),
            const InterestsViewWidget(),
            const SizedBox(height: 32),
            const GalleryViewWidget(),
            const SizedBox(height: 100),
          ],
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

  void _showMessageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kirim Pesan'),
        content: const Text('Fitur chat akan segera hadir!'),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Blokir User'),
              onTap: () {
                context.pop();
                _showBlockDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.report),
              title: const Text('Laporkan User'),
              onTap: () {
                context.pop();
                _showReportDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Blokir User'),
        content: const Text('Apakah Anda yakin ingin memblokir user ini?'),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              context.pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User telah diblokir')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Blokir'),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Laporkan User'),
        content: const Text('Apakah Anda yakin ingin melaporkan user ini?'),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              context.pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User telah dilaporkan')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Laporkan'),
          ),
        ],
      ),
    );
  }
}
