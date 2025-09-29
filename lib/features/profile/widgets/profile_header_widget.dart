// lib/features/profile/widgets/profile_header_widget.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/theme.dart';
import '../providers/profile_provider.dart';

class ProfileHeaderWidget extends ConsumerWidget {
  const ProfileHeaderWidget({super.key});

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

    return Column(
      children: [
        Stack(
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
                                  color: MC.darkBrown.withValues(alpha: 0.1),
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
                                  color: MC.darkBrown.withValues(alpha: 0.1),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Online di Malawa Cafe - Sudirman',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
      ],
    );
  }
}
