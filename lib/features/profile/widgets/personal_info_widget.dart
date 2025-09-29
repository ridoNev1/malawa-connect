import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme.dart';
import '../providers/profile_provider.dart';

class PersonalInfoWidget extends ConsumerStatefulWidget {
  const PersonalInfoWidget({super.key});

  @override
  ConsumerState<PersonalInfoWidget> createState() => _PersonalInfoWidgetState();
}

class _PersonalInfoWidgetState extends ConsumerState<PersonalInfoWidget> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider).profile;
    _nameController = TextEditingController(text: profile.fullName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Menggunakan ref.read untuk mendapatkan notifier
    final notifier = ref.read(profileProvider.notifier);

    return Form(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Informasi Pribadi',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: MC.darkBrown,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Nama Lengkap',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.person),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Nama tidak boleh kosong';
              }
              return null;
            },
            onChanged: (value) {
              // Memanggil metode dari notifier
              notifier.updateFullName(value);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: '+62 812-3456-7890',
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Nomor Telepon',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.phone),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: '1,250',
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Total Poin',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.stars),
            ),
          ),
        ],
      ),
    );
  }
}
