// lib/features/profile/widgets/profile_header_widget.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:malawa_connect/core/services/mock_api.dart';
import '../../../core/theme/theme.dart';
import '../providers/profile_provider.dart';
import '../../../core/services/supabase_api.dart';
import '../../home/providers/home_providers.dart';
import '../../connect/providers/member_detail_provider.dart';

class ProfileHeaderWidget extends ConsumerWidget {
  final bool isEditable;
  final String? userId;
  final bool isConnected;
  final Function(bool)? onConnectionChanged;

  const ProfileHeaderWidget({
    super.key,
    this.isEditable = true,
    this.userId,
    this.isConnected = false,
    this.onConnectionChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).profile;
    final notifier = ref.read(profileProvider.notifier);

    void showImagePicker() {
      showModalBottomSheet(
        context: context,
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera),
                title: const Text('Ambil Foto'),
                onTap: () async {
                  Navigator.pop(context);
                  await notifier.pickProfileImage(source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Pilih dari Galeri'),
                onTap: () async {
                  Navigator.pop(context);
                  await notifier.pickProfileImage(source: ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      );
    }

    void showFullScreenImage() {
      if (profile.profileImageUrl == null) return;

      Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, animation, secondaryAnimation) {
            return FullScreenProfileImagePage(
              imageUrl: profile.profileImageUrl!,
              tag: 'profile_image',
              userId: userId, // Pass userId to the full screen page
            );
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }

    return Column(
      children: [
        Stack(
          children: [
            GestureDetector(
              onTap: showFullScreenImage,
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: MC.darkBrown.withValues(alpha: 0.2),
                        width: 4,
                      ),
                    ),
                    child: ClipOval(
                      child: profile.profileImageUrl != null
                          ? profile.profileImageUrl!.startsWith('data:image')
                                ? Image.memory(
                                    base64Decode(
                                      profile.profileImageUrl!.split(',').last,
                                    ),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: MC.darkBrown.withValues(
                                          alpha: 0.1,
                                        ),
                                        child: const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: MC.darkBrown,
                                        ),
                                      );
                                    },
                                  )
                                : Image.network(
                                    profile.profileImageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: MC.darkBrown.withValues(
                                          alpha: 0.1,
                                        ),
                                        child: const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: MC.darkBrown,
                                        ),
                                      );
                                    },
                                  )
                          : Container(
                              color: MC.darkBrown.withValues(alpha: 0.1),
                              child: const Icon(
                                Icons.person,
                                size: 60,
                                color: MC.darkBrown,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (isEditable)
              Positioned(
                bottom: 0,
                right: 0,
                child: InkWell(
                  onTap: showImagePicker,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: MC.darkBrown,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          profile.fullName.isNotEmpty ? profile.fullName : 'Loading...',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: MC.darkBrown,
          ),
        ),
        const SizedBox(height: 4),
        // Online indicator (current user uses presenceProvider; other user uses memberByIdProvider)
        if (isEditable)
          Consumer(
            builder: (context, ref, _) {
              return ref
                  .watch(presenceProvider)
                  .when(
                    data: (presence) {
                      final online = presence != null;
                      if (online) {
                        final label =
                            'Online di ${presence['location_name'] ?? '-'}';
                        return _OnlineBadge(online: true, label: label);
                      }
                      // Offline: show last visit time from currentUserProvider if available
                      final cu = ref
                          .watch(currentUserProvider)
                          .maybeWhen(data: (d) => d, orElse: () => null);
                      String label = 'Terakhir mengunjungi cafe';
                      final iso = cu?['last_visit_at']?.toString();
                      final dt = iso != null ? DateTime.tryParse(iso) : null;
                      if (dt != null) {
                        final formatted = DateFormat(
                          'dd MMM yyyy HH:mm',
                        ).format(dt.toLocal());
                        label = 'Terakhir mengunjungi cafe $formatted';
                      }
                      return _OnlineBadge(online: false, label: label);
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (e, st) => const SizedBox.shrink(),
                  );
            },
          )
        else if (userId != null)
          Consumer(
            builder: (context, ref, _) {
              final memberAsync = ref.watch(memberByIdProvider(userId!));
              final locsAsync = ref.watch(profileLocationsProvider);
              return memberAsync.when(
                data: (m) {
                  final online = (m?['isOnline'] as bool?) == true;
                  String label;
                  if (online) {
                    // Prefer location_name from RPC; fallback to local lookup by id
                    String locName = (m?['location_name'] ?? '').toString();
                    if (locName.isEmpty) {
                      final locId = m?['location_id'] as int?;
                      if (locsAsync.hasValue) {
                        final locs = locsAsync.value!;
                        final found = locs.firstWhere(
                          (e) => e['id'] == locId,
                          orElse: () => {},
                        );
                        if (found.isNotEmpty)
                          locName = (found['name'] ?? '-').toString();
                      }
                    }
                    if (locName.isEmpty) locName = '-';
                    label = 'Online di $locName';
                  } else {
                    String rel = '-';
                    final iso = m?['lastSeen']?.toString();
                    if (iso != null && iso.isNotEmpty) {
                      try {
                        final dt = DateTime.parse(iso).toLocal();
                        final now = DateTime.now();
                        final diff = now.difference(dt);
                        if (diff.inSeconds < 60) rel = 'Baru saja';
                        else if (diff.inMinutes < 60) rel = '${diff.inMinutes} menit yang lalu';
                        else if (diff.inHours < 24) rel = '${diff.inHours} jam yang lalu';
                        else if (diff.inDays < 7) rel = '${diff.inDays} hari yang lalu';
                        else {
                          final weeks = (diff.inDays / 7).floor();
                          if (weeks < 5) rel = '$weeks minggu yang lalu';
                          else {
                            final months = (diff.inDays / 30).floor();
                            if (months < 12) rel = '$months bulan yang lalu';
                            else rel = '${(diff.inDays / 365).floor()} tahun yang lalu';
                          }
                        }
                      } catch (_) {}
                    }
                    label = 'Terakhir mengunjungi cafe $rel';
                  }
                  return _OnlineBadge(online: online, label: label);
                },
                loading: () => const SizedBox.shrink(),
                error: (e, st) => const SizedBox.shrink(),
              );
            },
          )
        else
          const SizedBox.shrink(),

        // Add connection button for view-only mode
        if (!isEditable) ...[
          const SizedBox(height: 16),
          isConnected
              ? _buildConnectedButton(context)
              : _buildRequestConnectButton(context),
        ],

        // Add some additional info for view-only mode
        if (!isEditable) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, color: Colors.green, size: 16),
                SizedBox(width: 6),
                Text(
                  'Member Terverifikasi',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRequestConnectButton(BuildContext context) {
    return OutlinedButton(
      onPressed: () {
        if (onConnectionChanged != null) {
          onConnectionChanged!(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permintaan koneksi telah dikirim'),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: MC.darkBrown,
        side: const BorderSide(color: MC.darkBrown),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_add, size: 18),
          SizedBox(width: 8),
          Text(
            'Request Connect',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedButton(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'disconnect' && onConnectionChanged != null) {
          onConnectionChanged!(false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Koneksi telah diputus'),
              backgroundColor: Colors.orange,
            ),
          );
        } else if (value == 'message') {
          if (userId != null) {
            if (MockApi.instance.isBlocked(userId!)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Tidak bisa mengirim pesan ke user yang diblokir',
                  ),
                ),
              );
            } else {
              _openChat(context, userId!);
            }
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'message',
          child: Row(
            children: [
              Icon(Icons.message),
              SizedBox(width: 8),
              Text('Kirim Pesan'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'disconnect',
          child: Row(
            children: [
              Icon(Icons.person_remove, color: Colors.red),
              SizedBox(width: 8),
              Text('Putus Koneksi', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green[300]!),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 18),
            SizedBox(width: 8),
            Text(
              'Connected',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: Colors.green),
          ],
        ),
      ),
    );
  }

  Future<void> _openChat(BuildContext context, String userId) async {
    // Ensure a chat exists with this user, then navigate
    final chat = await MockApi.instance.getOrCreateDirectChatByUserId(userId);
    if (context.mounted) {
      context.push('/chat/room/${chat['id']}');
    }
  }
}

class _OnlineBadge extends StatelessWidget {
  final bool online;
  final String label;
  const _OnlineBadge({required this.online, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: online ? Colors.green : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.black54),
        ),
      ],
    );
  }
}

final profileLocationsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  try {
    final list = await SupabaseApi.getLocationsOrg5();
    return list;
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
});

// Full screen profile image page
class FullScreenProfileImagePage extends StatelessWidget {
  final String imageUrl;
  final String tag;
  final String? userId; // Add userId parameter

  const FullScreenProfileImagePage({
    super.key,
    required this.imageUrl,
    required this.tag,
    this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Hero(
              tag: tag,
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4,
                child: imageUrl.startsWith('data:image')
                    ? Image.memory(
                        base64Decode(imageUrl.split(',').last),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: MC.darkBrown.withValues(alpha: 0.1),
                            child: const Icon(
                              Icons.person,
                              size: 100,
                              color: MC.darkBrown,
                            ),
                          );
                        },
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: MC.darkBrown.withValues(alpha: 0.1),
                            child: const Icon(
                              Icons.person,
                              size: 100,
                              color: MC.darkBrown,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 40, left: 16, right: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () async {
                      bool popped = await Navigator.of(context).maybePop();
                      if (!popped) {
                        if (userId != null) {
                          context.go('/profile/view/$userId');
                        } else {
                          context.go('/connect');
                        }
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),

                  // More options
                  PopupMenuButton<String>(
                    icon: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.more_vert, color: Colors.white),
                    ),
                    onSelected: (value) {
                      if (value == 'download') {
                        // Handle download
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Fitur download akan segera hadir!'),
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'download',
                        child: Row(
                          children: [
                            Icon(Icons.download),
                            SizedBox(width: 8),
                            Text('Download Gambar'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom info bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.zoom_in, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Pinch to zoom',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
