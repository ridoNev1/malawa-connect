// lib/features/profile/widgets/preference_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme.dart';
import '../providers/profile_provider.dart';

class PreferenceWidget extends ConsumerWidget {
  const PreferenceWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(profileProvider).profile.preference;
    final notifier = ref.read(profileProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Preferensi',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: MC.darkBrown,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  notifier.updatePreference('Looking for Friends');
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: preference == 'Looking for Friends'
                        ? MC.darkBrown
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: MC.darkBrown),
                  ),
                  child: Text(
                    'Looking for Friends',
                    style: TextStyle(
                      color: preference == 'Looking for Friends'
                          ? Colors.white
                          : MC.darkBrown,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: InkWell(
                onTap: () {
                  notifier.updatePreference('Looking for Partners');
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: preference == 'Looking for Partners'
                        ? MC.darkBrown
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: MC.darkBrown),
                  ),
                  child: Text(
                    'Looking for Partners',
                    style: TextStyle(
                      color: preference == 'Looking for Partners'
                          ? Colors.white
                          : MC.darkBrown,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
