import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/bottom_navigation.dart';
import '../../../shared/homepage/membership_card.dart';
import '../../../shared/homepage/promo_card.dart';
import '../../../shared/homepage/location_card.dart';
import '../../../shared/widgets/header_section.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _handleNotificationTap(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fitur notifikasi akan segera hadir')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                HeaderSection(
                  user: user,
                  notificationCount: 3,
                  onNotificationTap: () => _handleNotificationTap(context),
                ),
                const SizedBox(height: 24),

                const MembershipCard(
                  membershipType: 'Gold Member',
                  points: 1250,
                  validUntil: '31 Des 2023',
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Promo & Diskon',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: MC.darkBrown,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: MC.accentOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Lihat Semua',
                            style: TextStyle(
                              fontSize: 14,
                              color: MC.accentOrange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: MC.accentOrange,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 220,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 2,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (_, i) {
                      return PromoCard(
                        title: i == 0 ? 'Gratis Dessert' : 'Diskon 20%',
                        description: i == 0
                            ? 'Min. pembelian 150rb'
                            : 'Untuk semua menu minuman',
                        validUntil: '${i == 0 ? '30' : '15'} Nov 2023',
                        isPrimary: i == 1,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                const LocationCard(
                  cafeName: 'Malawa Cafe - Sudirman',
                  checkInTime: '14:30',
                  duration: '1 jam 15 menit',
                ),
              ],
            ),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: AppBottomNavigation(
              currentIndex: 0,
              onTap: (index) {
                switch (index) {
                  case 0:
                    context.go('/');
                    break;
                  case 1:
                    // Navigate to connect
                    break;
                  case 2:
                    // Navigate to chat
                    break;
                  case 3:
                    context.go('/profiles');
                    break;
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
