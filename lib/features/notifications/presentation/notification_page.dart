// lib/features/notification/pages/notification_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../../../shared/widgets/bottom_navigation.dart';
import '../providers/notifications_provider.dart';
import '../../../core/services/supabase_api.dart';

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
      await SupabaseApi.markNotificationReadOrg5(
        id: notification['id'].toString(),
      );
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
        title: Text(notification['title'] ?? 'Permintaan koneksi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (((notification['senderAvatar'] ??
                            notification['sender_avatar']) ??
                        '')
                    .toString()
                    .isNotEmpty)
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(
                      (notification['senderAvatar'] ??
                              notification['sender_avatar'])
                          .toString(),
                    ),
                  )
                else
                  const CircleAvatar(radius: 24, child: Icon(Icons.person)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (notification['senderName'] ??
                                notification['sender_name'] ??
                                'Tidak diketahui')
                            .toString(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        (notification['message'] ?? '').toString(),
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
              await ref
                  .read(notificationsProvider.notifier)
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
              viewProfile(
                (notification['senderId'] ?? notification['sender_id'])
                    ?.toString(),
              );
            },
            child: const Text('Lihat Profil'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              // Pass requesterId (senderId) for accept
              await ref
                  .read(notificationsProvider.notifier)
                  .accept(
                    (notification['senderId'] ?? notification['sender_id'])
                        .toString(),
                  );
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
        child: Consumer(
          builder: (context, ref, _) {
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
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
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
          },
        ),
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
                              formatTime(
                                DateTime.parse(
                                  (notification['created_at'] ??
                                          notification['timestamp'])
                                      .toString(),
                                ),
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notification['message'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),

                        // Show requester detail for connection requests (fallbacks when name missing)
                        if (notification['type']?.toString() ==
                            'connectionRequest') ...[
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () => viewProfile(
                              (notification['senderId'] ??
                                      notification['sender_id'] ??
                                      notification['senderid'])
                                  ?.toString(),
                            ),
                            child: Row(
                              children: [
                                if ((((notification['senderAvatar'] ??
                                                notification['sender_avatar']) ??
                                            notification['senderavatar']) ??
                                        '')
                                    .toString()
                                    .isNotEmpty)
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundImage: NetworkImage(
                                      ((notification['senderAvatar'] ??
                                                  notification['sender_avatar']) ??
                                              notification['senderavatar'])
                                          .toString(),
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.person,
                                    size: 18,
                                    color: MC.darkBrown,
                                  ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Builder(
                                    builder: (context) {
                                      final senderName =
                                          (notification['senderName'] ??
                                                  notification['sender_name'] ??
                                                  notification['sendername'] ??
                                                  '')
                                              .toString()
                                              .trim();
                                      final senderId =
                                          (notification['senderId'] ??
                                                  notification['sender_id'] ??
                                                  notification['senderid'] ??
                                                  '')
                                              .toString();
                                      String label;
                                      if (senderName.isNotEmpty) {
                                        label = senderName;
                                      } else if (senderId.isNotEmpty) {
                                        // show short uuid as fallback
                                        final shortId = senderId.length > 8
                                            ? senderId.substring(0, 8)
                                            : senderId;
                                        label = 'ID: $shortId';
                                      } else {
                                        label = 'Tidak diketahui';
                                      }
                                      return Text(
                                        'Dari: $label',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: MC.darkBrown,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                if ((notification['type']?.toString() ==
                                        'connectionRequest') &&
                                    (notification['isRead'] == true ||
                                        notification['requiresAction'] ==
                                            false)) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: (() {
                                          final r =
                                              (notification['actionResult'] ??
                                                      '')
                                                  .toString();
                                          if (r == 'accepted') {
                                            return Colors.green.withOpacity(
                                              0.12,
                                            );
                                          }
                                          if (r == 'declined') {
                                            return Colors.red.withOpacity(0.12);
                                          }
                                          return Colors.green.withOpacity(0.12);
                                        })(),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        (() {
                                          final r =
                                              (notification['actionResult'] ??
                                                      '')
                                                  .toString();
                                          if (r == 'accepted') {
                                            return 'Connected';
                                          }
                                          if (r == 'declined') return 'Ditolak';
                                          return 'Selesai';
                                        })(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: (() {
                                            final r =
                                                (notification['actionResult'] ??
                                                        '')
                                                    .toString();
                                            if (r == 'accepted') {
                                              return Colors.green.shade700;
                                            }
                                            if (r == 'declined') {
                                              return Colors.red.shade700;
                                            }
                                            return Colors.grey.shade700;
                                          })(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // Action buttons for connection requests (pending + unread)
              if ((notification['type']?.toString() == 'connectionRequest') &&
                  (notification['requiresAction'] == true) &&
                  (notification['isRead'] != true)) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Lihat Profil button
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => viewProfile(
                          (notification['senderId'] ??
                                  notification['sender_id'] ??
                                  notification['senderid'])
                              ?.toString(),
                        ),
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
                        onPressed: () async {
                          await ref
                              .read(notificationsProvider.notifier)
                              .decline(
                                (notification['senderId'] ??
                                        notification['sender_id'] ??
                                        notification['senderid'])
                                    .toString(),
                              );
                          // mark the request notification as read
                          try {
                            await SupabaseApi.markNotificationReadOrg5(
                              id: notification['id'].toString(),
                            );
                          } catch (_) {}
                          setState(() {
                            notification['isRead'] = true;
                            notification['requiresAction'] = false;
                            notification['actionResult'] = 'declined';
                          });
                          if (!mounted) return;
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
                    // Accept button - outline green
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await ref
                              .read(notificationsProvider.notifier)
                              .accept(
                                (notification['senderId'] ??
                                        notification['sender_id'] ??
                                        notification['senderid'])
                                    .toString(),
                              );
                          // mark the request notification as read
                          try {
                            await SupabaseApi.markNotificationReadOrg5(
                              id: notification['id'].toString(),
                            );
                          } catch (_) {}
                          setState(() {
                            notification['isRead'] = true;
                            notification['requiresAction'] = false;
                            notification['actionResult'] = 'accepted';
                          });
                          if (!mounted) return;
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

              // Status chip when already handled (accepted/declined)
            ],
          ),
        ),
      ),
    );
  }
}
