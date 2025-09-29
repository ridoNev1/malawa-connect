// lib/features/profile/pages/profile_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/bottom_navigation.dart';
import '../../../shared/widgets/logout_dialog.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_header_widget.dart';
import '../widgets/personal_info_widget.dart';
import '../widgets/preference_widget.dart';
import '../widgets/interests_widget.dart';
import '../widgets/gallery_widget.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(profileProvider.notifier).loadUserData());
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await Future.delayed(const Duration(seconds: 1));
      if (context.mounted) {
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logout gagal: $e')));
      }
    }
  }

  void _showLogoutDialog(BuildContext context) {
    LogoutDialog.show(context, onLogout: () => _logout(context));
  }

  @override
  Widget build(BuildContext context) {
    // Menggunakan ref.watch untuk mendapatkan state
    final state = ref.watch(profileProvider);
    final notifier = ref.read(profileProvider.notifier);

    if (state.isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: MC.darkBrown)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Profil Saya',
          style: TextStyle(color: MC.darkBrown, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => _showLogoutDialog(context),
            icon: const Icon(Icons.logout, color: MC.darkBrown),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const ProfileHeaderWidget(),
            const SizedBox(height: 32),
            const PersonalInfoWidget(),
            const SizedBox(height: 32),
            const PreferenceWidget(),
            const SizedBox(height: 32),
            const InterestsWidget(),
            const SizedBox(height: 32),
            const GalleryWidget(),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: state.isSaving ? null : () => notifier.saveProfile(),
                style: FilledButton.styleFrom(
                  backgroundColor: MC.darkBrown,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: state.isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Simpan Perubahan',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 3,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/');
              break;
            case 1:
              break;
            case 2:
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
