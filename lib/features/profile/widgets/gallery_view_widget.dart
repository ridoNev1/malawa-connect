// lib/features/profile/widgets/gallery_view_widget.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme.dart';
import '../providers/profile_provider.dart';

class GalleryViewWidget extends ConsumerWidget {
  const GalleryViewWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final galleryImages = ref.watch(profileProvider).profile.galleryImages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Galeri Foto',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: MC.darkBrown,
          ),
        ),
        const SizedBox(height: 16),

        galleryImages.isEmpty
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 48,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Belum ada foto yang ditambahkan',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              )
            : Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: MC.darkBrown.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.collections,
                            color: MC.darkBrown,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${galleryImages.length} Foto',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.0,
                          ),
                      itemCount: galleryImages.length,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () {
                            _showFullScreenImage(context, galleryImages, index);
                          },
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 1.0,
                                  child:
                                      galleryImages[index].startsWith(
                                        'data:image',
                                      )
                                      ? Image.memory(
                                          base64Decode(
                                            galleryImages[index]
                                                .split(',')
                                                .last,
                                          ),
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Container(
                                                  color: MC.darkBrown
                                                      .withValues(alpha: 0.1),
                                                  child: const Icon(
                                                    Icons.broken_image,
                                                    size: 40,
                                                    color: MC.darkBrown,
                                                  ),
                                                );
                                              },
                                        )
                                      : (() {
                                          final String url = galleryImages[index];
                                          final bool valid = url.isNotEmpty &&
                                              (url.startsWith('http://') ||
                                                  url.startsWith('https://'));
                                          if (valid) {
                                            return Image.network(
                                              url,
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              height: double.infinity,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Container(
                                                  color: MC.darkBrown
                                                      .withValues(alpha: 0.1),
                                                  child: const Icon(
                                                    Icons.broken_image,
                                                    size: 40,
                                                    color: MC.darkBrown,
                                                  ),
                                                );
                                              },
                                            );
                                          }
                                          return Container(
                                            color:
                                                MC.darkBrown.withValues(alpha: 0.1),
                                            child: const Icon(
                                              Icons.broken_image,
                                              size: 40,
                                              color: MC.darkBrown,
                                            ),
                                          );
                                        })(),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
      ],
    );
  }

  void _showFullScreenImage(
      BuildContext context, List<String> images, int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FullScreenGalleryPage(
            images: images,
            initialIndex: index,
            tag: 'gallery_$index', // Unique tag for hero animation
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

// Full screen gallery page
class FullScreenGalleryPage extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final String tag;

  const FullScreenGalleryPage({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.tag,
  });

  @override
  State<FullScreenGalleryPage> createState() => _FullScreenGalleryPageState();
}

class _FullScreenGalleryPageState extends State<FullScreenGalleryPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen gallery with swipe capability
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4,
                  child: widget.images[index].startsWith('data:image')
                      ? Image.memory(
                          base64Decode(widget.images[index].split(',').last),
                          fit: BoxFit.contain,
                        )
                      : (() {
                          final String url = widget.images[index];
                          final bool valid = url.isNotEmpty &&
                              (url.startsWith('http://') ||
                                  url.startsWith('https://'));
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
                                    Icons.broken_image,
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
                              Icons.broken_image,
                              size: 100,
                              color: MC.darkBrown,
                            ),
                          );
                        })(),
                ),
              );
            },
          ),

          // Top app bar with back button and image counter
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

                  // Image counter
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
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

          // Bottom info bar with thumbnail preview
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
              child: Column(
                children: [
                  // Thumbnail preview
                  SizedBox(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.images.length,
                      itemBuilder: (context, index) {
                        final isSelected = index == _currentIndex;
                        return GestureDetector(
                          onTap: () {
                            _pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: widget.images[index].startsWith('data:image')
                                  ? Image.memory(
                                      base64Decode(
                                          widget.images[index].split(',').last),
                                      fit: BoxFit.cover,
                                    )
                                  : (() {
                                      final String url = widget.images[index];
                                      final bool valid = url.isNotEmpty &&
                                          (url.startsWith('http://') ||
                                              url.startsWith('https://'));
                                      if (valid) {
                                        return Image.network(
                                          url,
                                          fit: BoxFit.cover,
                                        );
                                      }
                                      return Container(
                                        color: MC.darkBrown.withValues(alpha: 0.1),
                                        child: const Icon(
                                          Icons.broken_image,
                                          color: MC.darkBrown,
                                        ),
                                      );
                                    })(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Zoom hint
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.zoom_in, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Pinch to zoom • Swipe to browse',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
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
