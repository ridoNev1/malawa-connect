// lib/features/profile/widgets/personal_info_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../providers/profile_provider.dart';

class PersonalInfoWidget extends ConsumerStatefulWidget {
  const PersonalInfoWidget({super.key});

  @override
  ConsumerState<PersonalInfoWidget> createState() => _PersonalInfoWidgetState();
}

class _PersonalInfoWidgetState extends ConsumerState<PersonalInfoWidget> {
  late TextEditingController _nameController;
  DateTime? _selectedDate;
  String? _selectedGender;

  final List<String> _genderOptions = ['Laki-laki', 'Perempuan'];

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider).profile;
    _nameController = TextEditingController(text: profile.fullName);
    _selectedDate = profile.dateOfBirth;
    _selectedGender = profile.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime(1990),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      ref.read(profileProvider.notifier).updateDateOfBirth(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
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

          // Tanggal Lahir Field
          InkWell(
            onTap: () => _selectDate(context),
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Tanggal Lahir',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.calendar_today),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedDate != null
                        ? DateFormat('dd MMMM yyyy').format(_selectedDate!)
                        : 'Pilih tanggal lahir',
                    style: TextStyle(
                      fontSize: 16,
                      color: _selectedDate != null
                          ? Colors.black87
                          : Colors.grey,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Jenis Kelamin Field
          DropdownButtonFormField<String>(
            value: _selectedGender,
            decoration: InputDecoration(
              labelText: 'Jenis Kelamin',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.person_outline),
            ),
            hint: const Text('Pilih jenis kelamin'),
            isExpanded: true,
            items: _genderOptions.map((String value) {
              return DropdownMenuItem<String>(value: value, child: Text(value));
            }).toList(),
            onChanged: (newValue) {
              setState(() {
                _selectedGender = newValue;
              });
              notifier.updateGender(newValue);
            },
          ),
        ],
      ),
    );
  }
}
