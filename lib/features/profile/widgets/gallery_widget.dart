import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme.dart';
import '../providers/profile_provider.dart';

class GalleryWidget extends ConsumerWidget {
  const GalleryWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final galleryImages = ref.watch(profileProvider).profile.galleryImages;
    final notifier = ref.read(profileProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Galeri Foto',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: MC.darkBrown,
              ),
            ),
            TextButton.icon(
              onPressed: notifier.addGalleryImage,
              icon: const Icon(Icons.add_photo_alternate, size: 18),
              label: const Text('Tambah'),
              style: TextButton.styleFrom(foregroundColor: MC.accentOrange),
            ),
          ],
        ),
        const SizedBox(height: 16),
        galleryImages.isEmpty
            ? const Center(
                child: Text(
                  'Belum ada foto yang ditambahkan',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  // Tambahkan aspek rasio 1:1 untuk membuat grid konsisten
                  childAspectRatio: 1.0,
                ),
                itemCount: galleryImages.length + 1,
                itemBuilder: (context, index) {
                  if (index == galleryImages.length) {
                    return InkWell(
                      onTap: notifier.addGalleryImage,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: MC.darkBrown.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: MC.darkBrown.withValues(alpha: 0.2),
                            style: BorderStyle.solid,
                            width: 2,
                            strokeAlign: BorderSide.strokeAlignOutside,
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate,
                              size: 32,
                              color: MC.darkBrown,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Tambah Foto',
                              style: TextStyle(
                                fontSize: 12,
                                color: MC.darkBrown,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Stack(
                    children: [
                      // Bungkus dengan AspectRatio untuk menjaga aspek rasio
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: galleryImages[index].startsWith('data:image')
                              ? Image.memory(
                                  base64Decode(
                                    galleryImages[index].split(',').last,
                                  ),
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: MC.darkBrown.withValues(
                                        alpha: 0.1,
                                      ),
                                      child: const Icon(
                                        Icons.broken_image,
                                        size: 40,
                                        color: MC.darkBrown,
                                      ),
                                    );
                                  },
                                )
                              : Image.network(
                                  galleryImages[index],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: MC.darkBrown.withValues(
                                        alpha: 0.1,
                                      ),
                                      child: const Icon(
                                        Icons.broken_image,
                                        size: 40,
                                        color: MC.darkBrown,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: InkWell(
                          onTap: () => notifier.removeGalleryImage(index),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ],
    );
  }
}
