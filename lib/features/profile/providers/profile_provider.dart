// lib/features/profile/providers/profile_provider.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../models/profile_models.dart';

class ProfileState {
  final ProfileModel profile;
  final bool isLoading;
  final bool isSaving;

  ProfileState({
    required this.profile,
    this.isLoading = false,
    this.isSaving = false,
  });

  ProfileState copyWith({
    ProfileModel? profile,
    bool? isLoading,
    bool? isSaving,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

class ProfileNotifier extends Notifier<ProfileState> {
  @override
  ProfileState build() {
    return ProfileState(
      profile: ProfileModel(
        fullName: '',
        preference: 'Looking for Friends',
        interests: [],
        galleryImages: [],
      ),
    );
  }

  final ImagePicker _picker = ImagePicker();

  Future<void> loadUserData() async {
    state = state.copyWith(isLoading: true);
    try {
      await Future.delayed(const Duration(seconds: 1));
      state = state.copyWith(
        profile: ProfileModel(
          fullName: 'Sarah Johnson',
          preference: 'Looking for Friends',
          interests: ['Coffee', 'Music', 'Travel', 'Photography', 'Art'],
          galleryImages: [
            'https://picsum.photos/seed/gallery1/200/200.jpg',
            'https://picsum.photos/seed/gallery2/200/200.jpg',
            'https://picsum.photos/seed/gallery3/200/200.jpg',
            'https://picsum.photos/seed/gallery4/200/200.jpg',
            'https://picsum.photos/seed/gallery5/200/200.jpg',
          ],
          profileImageUrl: 'https://randomuser.me/api/portraits/women/44.jpg',
        ),
      );
    } catch (e) {
      // Handle error
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  // TAMBAHKAN METODE INI
  Future<void> saveProfile() async {
    state = state.copyWith(isSaving: true);
    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));
      // Success
    } catch (e) {
      // Handle error
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }

  void updateFullName(String fullName) {
    state = state.copyWith(profile: state.profile.copyWith(fullName: fullName));
  }

  void updatePreference(String preference) {
    state = state.copyWith(
      profile: state.profile.copyWith(preference: preference),
    );
  }

  void addInterest(String interest) {
    if (interest.isNotEmpty && !state.profile.interests.contains(interest)) {
      final updatedInterests = List<String>.from(state.profile.interests);
      updatedInterests.add(interest);
      state = state.copyWith(
        profile: state.profile.copyWith(interests: updatedInterests),
      );
    }
  }

  void removeInterest(String interest) {
    final updatedInterests = List<String>.from(state.profile.interests);
    updatedInterests.remove(interest);
    state = state.copyWith(
      profile: state.profile.copyWith(interests: updatedInterests),
    );
  }

  Future<void> pickProfileImage({required ImageSource source}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 70,
      );

      if (image != null) {
        state = state.copyWith(isLoading: true);

        final bytes = await image.readAsBytes();
        final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';

        state = state.copyWith(
          profile: state.profile.copyWith(profileImageUrl: base64String),
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> addGalleryImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (image != null) {
        state = state.copyWith(isLoading: true);

        final bytes = await image.readAsBytes();
        final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';

        final updatedGalleryImages = List<String>.from(
          state.profile.galleryImages,
        );
        updatedGalleryImages.add(base64String);

        state = state.copyWith(
          profile: state.profile.copyWith(galleryImages: updatedGalleryImages),
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  void removeGalleryImage(int index) {
    final updatedGalleryImages = List<String>.from(state.profile.galleryImages);
    updatedGalleryImages.removeAt(index);
    state = state.copyWith(
      profile: state.profile.copyWith(galleryImages: updatedGalleryImages),
    );
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, ProfileState>(
  ProfileNotifier.new,
);
