import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/bottom_navigation.dart';
import '../widgets/membership_card.dart';
import '../widgets/promo_card.dart';
import '../widgets/location_card.dart';
import '../../../shared/widgets/header_section.dart';
import '../providers/home_providers.dart';
import '../providers/geofence_watcher.dart';
import '../../notifications/providers/notification_permission_provider.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../../core/services/notification_permission_service.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  void _handleNotificationTap(BuildContext context) {
    context.go("/notifications");
  }

  Future<void> _refreshAll(WidgetRef ref) async {
    ref.invalidate(currentUserProvider);
    ref.invalidate(membershipSummaryProvider);
    ref.invalidate(discountsProvider);
    ref.invalidate(presenceProvider);
    ref.invalidate(locationsOrg5Provider);
    ref.invalidate(geofenceWatcherProvider);
    await ref.read(notificationsProvider.notifier).refresh();
  }

  String _formatDuration(DateTime from, DateTime to) {
    final diff = to.difference(from);
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final mins = diff.inMinutes % 60;
    if (days > 0) {
      // Example: 1 hari 2 jam
      if (hours > 0) return '$days hari $hours jam';
      return '$days hari';
    }
    if (hours > 0) {
      // Example: 2 jam 10 menit
      if (mins > 0) return '$hours jam $mins menit';
      return '$hours jam';
    }
    return '$mins menit';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start geofence watcher when Home builds
    ref.watch(geofenceWatcherProvider);
    // Ensure locations RPC is triggered on Home
    ref.watch(locationsOrg5Provider);
    // Ask notification permission (Android 13+/iOS) once
    ref.watch(notificationPermissionProvider);
    final user = Supabase.instance.client.auth.currentUser;
    final notifState = ref.watch(notificationsProvider);
    // Trigger load if empty
    if (!notifState.loading && notifState.items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(notificationsProvider.notifier).refresh();
      });
    }
    final unread = notifState.items.where((n) => n['isRead'] == false).length;
    final currentUser = ref.watch(currentUserProvider).maybeWhen(
          data: (d) => d,
          orElse: () => null,
        );
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () => _refreshAll(ref),
              color: MC.accentOrange,
              backgroundColor: Colors.white,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                HeaderSection(
                  user: user,
                  notificationCount: unread,
                  onNotificationTap: () => _handleNotificationTap(context),
                  // Only pass displayName when full_name is non-empty.
                  displayName: () {
                    if (currentUser == null) return null;
                    final name = (currentUser['full_name'] ?? '').toString().trim();
                    return name.isEmpty ? null : name;
                  }(),
                ),
                // Show banner if notification permission not granted
                ref.watch(notificationPermissionProvider).maybeWhen(
                      data: (granted) => granted
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.amber.withOpacity(0.4)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.notifications_off,
                                        color: Colors.amber),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Aktifkan izin notifikasi untuk menerima pemberitahuan.',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        final ok = await NotificationPermissionService
                                            .ensureRequestedOnce();
                                        if (!ok) {
                                          await NotificationPermissionService
                                              .openSettings();
                                        }
                                      },
                                      child: const Text('AKTIFKAN'),
                                    )
                                  ],
                                ),
                              ),
                            ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                const SizedBox(height: 24),
                ref
                    .watch(membershipSummaryProvider)
                    .when(
                      data: (data) => MembershipCard(
                        membershipType: data['membershipType'] ?? '-',
                        points: data['points'] ?? 0,
                        validUntil: data['validUntil'] ?? '-',
                      ),
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (e, st) => const SizedBox.shrink(),
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
                    // Container(
                    //   padding: const EdgeInsets.symmetric(
                    //     horizontal: 12,
                    //     vertical: 6,
                    //   ),
                    //   decoration: BoxDecoration(
                    //     color: MC.accentOrange.withValues(alpha: 0.1),
                    //     borderRadius: BorderRadius.circular(20),
                    //   ),
                    //   child: const Row(
                    //     mainAxisSize: MainAxisSize.min,
                    //     children: [
                    //       Text(
                    //         'Lihat Semua',
                    //         style: TextStyle(
                    //           fontSize: 14,
                    //           color: MC.accentOrange,
                    //           fontWeight: FontWeight.w600,
                    //         ),
                    //       ),
                    //       SizedBox(width: 4),
                    //       Icon(
                    //         Icons.arrow_forward_ios,
                    //         color: MC.accentOrange,
                    //         size: 14,
                    //       ),
                    //     ],
                    //   ),
                    // ),
                  ],
                ),
                const SizedBox(height: 16),
                ref
                    .watch(discountsProvider)
                    .when(
                      data: (discounts) {
                        if (discounts.isEmpty) {
                          return Container(
                            height: 140,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: MC.accentOrange.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: MC.accentOrange.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.local_offer_outlined,
                                    color: MC.accentOrange,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Belum ada promo & diskon',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: MC.darkBrown,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Pantau halaman ini untuk penawaran terbaru dari Malawa.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return SizedBox(
                          height: 220,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: discounts.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 16),
                            itemBuilder: (_, i) {
                              final d = discounts[i];
                              return PromoCard(
                                title: d['name'] ?? '-',
                                description: (d['description'] ?? '')
                                        .toString()
                                        .isEmpty
                                    ? (d['unique_code'] ?? '')
                                    : d['description'] ?? '',
                                validUntil:
                                    (d['valid_until'] ?? '—').toString(),
                                isPrimary: i % 2 == 1,
                              );
                            },
                          ),
                        );
                      },
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (e, st) => Container(
                        height: 140,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.2),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline, color: Colors.red),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Promo belum dapat dimuat saat ini. Coba tarik untuk menyegarkan.',
                                style: TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 24),
                ref.watch(presenceProvider).when(
                      data: (presence) {
                        if (presence == null) {
                          return const LocationCard(
                            cafeName: 'Di luar jangkauan',
                            checkInTime: '-',
                            duration: '-',
                            isInside: false,
                          );
                        }
                        final t = DateTime.tryParse(
                                  (presence['check_in_time'] ?? '').toString(),
                                )?.toLocal() ??
                            DateTime.now();
                        final hhmm =
                            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                        final duration = _formatDuration(t, DateTime.now());
                        return LocationCard(
                          cafeName: (presence['location_name'] ?? '-').toString(),
                          checkInTime: hhmm,
                          duration: duration,
                          isInside: true,
                        );
                      },
                      loading: () => const LocationCard(
                        cafeName: 'Memeriksa lokasi…',
                        checkInTime: '-',
                        duration: '-',
                        isInside: false,
                        statusMessage: 'Memeriksa jangkauan lokasi',
                      ),
                      error: (e, st) => const LocationCard(
                        cafeName: 'Tidak dapat memuat lokasi',
                        checkInTime: '-',
                        duration: '-',
                        isInside: false,
                        statusMessage: 'Anda berada di luar jangkauan cafe',
                      ),
                    ),
              ],
              ),
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
          ),
        ],
      ),
    );
  }
}
