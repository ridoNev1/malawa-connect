// lib/features/notification/pages/notification_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/bottom_navigation.dart';
import '../providers/notifications_provider.dart';
import '../../../core/services/mock_api.dart';

class NotificationPage extends ConsumerStatefulWidget {
  const NotificationPage({super.key});

  @override
  ConsumerState<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends ConsumerState<NotificationPage> {
  @override
  void initState() {
    super.initState();
    // Always refresh when page opened to keep it real
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).refresh();
    });
  }

  String formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} hari yang lalu';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} jam yang lalu';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} menit yang lalu';
    } else {
      return 'Baru saja';
    }
  }

  IconData getIconForType(String type) {
    switch (type) {
      case 'newMessage':
        return Icons.message;
      case 'connectionRequest':
        return Icons.person_add;
      case 'connectionAccepted':
        return Icons.check_circle;
      case 'connectionRejected':
        return Icons.cancel;
      default:
        return Icons.notifications;
    }
  }

  Color getIconColorForType(String type) {
    switch (type) {
      case 'newMessage':
        return Colors.blue;
      case 'connectionRequest':
        return Colors.orange;
      case 'connectionAccepted':
        return Colors.green;
      case 'connectionRejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void handleAction(Map<String, dynamic> notification) async {
    final notifier = ref.read(notificationsProvider.notifier);
    if (notification['type'] == 'connectionRequest' &&
        notification['requiresAction'] == true) {
      _showConnectionActionDialog(notification);
    } else if (notification['isRead'] == false) {
      await MockApi.instance.markNotificationRead(notification['id']);
      await notifier.refresh();
    }
  }

  void viewProfile(String? senderId) {
    if (senderId != null) {
      context.go('/profile/view/$senderId');
    }
  }

  void _showConnectionActionDialog(Map<String, dynamic> notification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(notification['title']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: NetworkImage(notification['senderAvatar']),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification['senderName'] ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        notification['message'],
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(notificationsProvider.notifier)
                  .decline(notification['id']);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Permintaan koneksi ditolak'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Tolak'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              viewProfile(notification['senderId']);
            },
            child: const Text('Lihat Profil'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(notificationsProvider.notifier)
                  .accept(notification['id']);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Permintaan koneksi diterima'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: MC.darkBrown),
            child: const Text('Terima'),
          ),
        ],
      ),
    );
  }

  Future<void> markAllAsRead() async {
    await ref.read(notificationsProvider.notifier).markAllRead();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Semua notifikasi telah ditandai sebagai dibaca'),
      ),
    );
  }

  int get unreadCount {
    final s = ref.watch(notificationsProvider);
    return s.items.where((n) => n['isRead'] == false).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Notifikasi',
          style: TextStyle(color: MC.darkBrown, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (unreadCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: MC.darkBrown,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: markAllAsRead,
            icon: const Icon(Icons.done_all, color: MC.darkBrown),
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer(builder: (context, ref, _) {
          final s = ref.watch(notificationsProvider);
          if (!s.loading && s.items.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(notificationsProvider.notifier).refresh();
            });
          }
          return s.items.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Belum ada notifikasi',
                      style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(notificationsProvider.notifier).refresh(),
                  color: MC.darkBrown,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: s.items.length,
                    itemBuilder: (context, index) {
                      final notification = s.items[index];
                      return _buildNotificationCard(notification);
                    },
                  ),
                );
        }),
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 2,
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

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: notification['isRead'] == true ? Colors.white : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => handleAction(notification),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: getIconColorForType(
                        notification['type'],
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      getIconForType(notification['type']),
                      color: getIconColorForType(notification['type']),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Sender avatar and info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (notification['senderAvatar'] != null) ...[
                              CircleAvatar(
                                radius: 16,
                                backgroundImage: NetworkImage(
                                  notification['senderAvatar'],
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                notification['title'],
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: MC.darkBrown,
                                ),
                              ),
                            ),
                            // Unread indicator
                            if (notification['isRead'] == false)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: MC.darkBrown,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            const SizedBox(width: 8),
                            // Time
                            Text(
                              formatTime(DateTime.parse(
                                  notification['timestamp'].toString())),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notification['message'],
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Action buttons for connection requests - PERUBAHAN DI SINI
              if (notification['type'] == 'connectionRequest' &&
                  notification['requiresAction'] == true) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Lihat Profil button
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => viewProfile(notification['senderId']),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MC.darkBrown,
                          side: const BorderSide(color: MC.darkBrown),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: const Text(
                          'Lihat Profil',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Reject button
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            notification['isRead'] = true;
                            notification['requiresAction'] = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Permintaan koneksi ditolak'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: const Text(
                          'Tolak',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Accept button - PERUBAHAN MENJADI OUTLINE DENGAN WARNA HIJAU
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            notification['isRead'] = true;
                            notification['requiresAction'] = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Permintaan koneksi diterima'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                          side: const BorderSide(color: Colors.green),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: const Text(
                          'Terima',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
