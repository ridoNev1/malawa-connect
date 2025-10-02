// lib/features/connect/widgets/member_card_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/theme.dart';
import '../providers/members_provider.dart';
import '../../../core/services/supabase_api.dart';
import '../providers/inapp_presence_provider.dart';

class MemberCardWidget extends ConsumerWidget {
  final Map<String, dynamic> member;

  const MemberCardWidget({super.key, required this.member});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String _relativeTime(String? iso) {
      if (iso == null || iso.isEmpty) return '-';
      DateTime? dt;
      try {
        dt = DateTime.parse(iso).toLocal();
      } catch (_) {
        return '-';
      }
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return 'Baru saja';
      if (diff.inMinutes < 60) return '${diff.inMinutes} menit yang lalu';
      if (diff.inHours < 24) return '${diff.inHours} jam yang lalu';
      if (diff.inDays < 7) return '${diff.inDays} hari yang lalu';
      final weeks = (diff.inDays / 7).floor();
      if (weeks < 5) return '$weeks minggu yang lalu';
      final months = (diff.inDays / 30).floor();
      if (months < 12) return '$months bulan yang lalu';
      final years = (diff.inDays / 365).floor();
      return '$years tahun yang lalu';
    }

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
                // Avatar with in-app indicator and tap to enlarge
                GestureDetector(
                  onTap: () {
                    _showFullScreenImage(context, member['avatar']);
                  },
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(50),
                        child: (() {
                          final String url = (member['avatar'] ?? '')
                              .toString();
                          final bool valid =
                              url.isNotEmpty &&
                              (url.startsWith('http://') ||
                                  url.startsWith('https://'));
                          if (valid) {
                            return Image.network(
                              url,
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
                            );
                          }
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
                        })(),
                      ),
                      // In-app indicator attached to avatar only
                      Consumer(builder: (context, ref, _) {
                        final u = (member['member_id'] ?? '').toString();
                        final inApp = ref.watch(inAppPresenceProvider).activeUids.contains(u);
                        return Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: inApp ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
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
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            (member['location_name']?.toString().isNotEmpty ??
                                    false)
                                ? member['location_name'].toString()
                                : '-',
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
                            _relativeTime(member['lastSeen']?.toString()),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Age & Gender (better icon mapping)
                      if (member['age'] != null || member['gender'] != null)
                        Row(
                          children: [
                            Builder(builder: (context) {
                              final g = (member['gender'] ?? '').toString().toLowerCase();
                              IconData icon;
                              Color color;
                              if (g.contains('laki') || g == 'male' || g == 'm') {
                                icon = Icons.male_rounded;
                                color = Colors.blueAccent;
                              } else if (g.contains('perempuan') || g == 'female' || g == 'f') {
                                icon = Icons.female_rounded;
                                color = Colors.pinkAccent;
                              } else {
                                icon = Icons.person_outline;
                                color = Colors.grey[500]!;
                              }
                              return Icon(icon, size: 14, color: color);
                            }),
                            const SizedBox(width: 4),
                            Text(
                              member['age'] != null
                                  ? '${member['age']} tahun'
                                  : '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            if (member['age'] != null && member['gender'] != null)
                              const Text(' • ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(
                              (member['gender'] ?? '').toString(),
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      // Interests
                      Builder(
                        builder: (context) {
                          final interests =
                              (member['interests'] as List?)
                                  ?.map((e) => e.toString())
                                  .toList() ??
                              const <String>[];
                          if (interests.isEmpty) return const SizedBox.shrink();
                          return Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: interests.map((interest) {
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
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Actions: Connect/Unfriend + View Profile
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.go('/profile/view/${member['id']}');
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
                const SizedBox(width: 8),
                Expanded(child: _buildConnectButton(context, ref)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectButton(BuildContext context, WidgetRef ref) {
    final status = (member['connection_status'] ?? '').toString();
    final peerId = (member['member_id'] ?? '').toString();
    if (peerId.isEmpty) {
      return const SizedBox.shrink();
    }
    if (status == 'accepted') {
      return OutlinedButton.icon(
        onPressed: () async {
          // Capture messenger before async awaits to avoid ancestor lookup after disposal
          final messenger = ScaffoldMessenger.maybeOf(context);
          try {
            await SupabaseApi.unfriendOrg5(peerId: peerId);
            // Refresh lists + derived counts
            await ref.read(membersProvider.notifier).refresh();
            messenger?.showSnackBar(
              const SnackBar(content: Text('Koneksi diputuskan')),
            );
          } catch (e) {
            messenger?.showSnackBar(
              SnackBar(content: Text('Gagal memutuskan: $e')),
            );
          }
        },
        icon: const Icon(Icons.link_off, size: 18),
        label: const Text('Putuskan'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red[700],
          side: BorderSide(color: Colors.red[700]!),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    if (status == 'pending') {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_empty, size: 18),
        label: const Text('Menunggu'),
      );
    }
    // Default: can send request
    return FilledButton.icon(
      onPressed: () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        try {
          await SupabaseApi.sendConnectionRequestOrg5(
            addresseeId: peerId,
            connectionType: 'friend',
          );
          await ref.read(membersProvider.notifier).refresh();
          messenger?.showSnackBar(
            const SnackBar(content: Text('Permintaan koneksi dikirim')),
          );
        } catch (e) {
          messenger?.showSnackBar(
            SnackBar(content: Text('Gagal mengirim permintaan: $e')),
          );
        }
      },
      icon: const Icon(Icons.person_add_alt, size: 18),
      label: const Text('Koneksi'),
      style: FilledButton.styleFrom(
        backgroundColor: MC.darkBrown,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FullScreenImagePage(
            imageUrl: imageUrl,
            tag: imageUrl, // Unique tag for hero animation
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

// Full screen image page
class FullScreenImagePage extends StatefulWidget {
  final String imageUrl;
  final String tag;

  const FullScreenImagePage({
    super.key,
    required this.imageUrl,
    required this.tag,
  });

  @override
  State<FullScreenImagePage> createState() => _FullScreenImagePageState();
}

class _FullScreenImagePageState extends State<FullScreenImagePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen image with zoom capability
          Center(
            child: Hero(
              tag: widget.tag,
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4,
                child: (() {
                  final String url = widget.imageUrl.trim();
                  final bool valid =
                      url.isNotEmpty &&
                      (url.startsWith('http://') || url.startsWith('https://'));
                  if (valid) {
                    return Image.network(
                      url,
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
                    );
                  }
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
                })(),
              ),
            ),
          ),

          // Top app bar with back button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 40, left: 16, right: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
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
