// lib/features/profile/widgets/interests_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme.dart';
import '../providers/profile_provider.dart';

class InterestsWidget extends ConsumerWidget {
  const InterestsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interests = ref.watch(profileProvider).profile.interests;
    final notifier = ref.read(profileProvider.notifier);

    void _showAddInterestDialog() {
      final TextEditingController controller = TextEditingController();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tambah Minat'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Masukkan minat baru'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () {
                final newInterest = controller.text.trim();
                notifier.addInterest(newInterest);
                Navigator.pop(context);
              },
              child: const Text('Tambah'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Minat',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: MC.darkBrown,
              ),
            ),
            TextButton.icon(
              onPressed: _showAddInterestDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tambah'),
              style: TextButton.styleFrom(foregroundColor: MC.accentOrange),
            ),
          ],
        ),
        const SizedBox(height: 16),
        interests.isEmpty
            ? const Center(
                child: Text(
                  'Belum ada minat yang ditambahkan',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: interests.map((interest) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: MC.darkBrown.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          interest,
                          style: const TextStyle(
                            color: MC.darkBrown,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => notifier.removeInterest(interest),
                          borderRadius: BorderRadius.circular(12),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: MC.darkBrown,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }
}
