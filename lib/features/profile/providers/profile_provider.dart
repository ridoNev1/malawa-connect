// lib/features/profile/providers/profile_provider.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/mock_api.dart';
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
      final me = await MockApi.instance.getCurrentUser();
      state = state.copyWith(
        profile: ProfileModel(
          fullName: me['full_name'] ?? '',
          preference: (me['preference'] ?? 'Looking for Friends').toString(),
          interests: List<String>.from(me['interests'] ?? const <String>[]),
          galleryImages:
              List<String>.from(me['gallery_images'] ?? const <String>[]),
          profileImageUrl: me['profile_image_url'],
          dateOfBirth: me['date_of_birth'] != null
              ? DateTime.tryParse(me['date_of_birth'])
              : null,
          gender: me['gender'],
        ),
      );
    } catch (e) {
      // Handle error
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  // New method to load user data by ID
  Future<void> loadUserDataById(String userId) async {
    state = state.copyWith(isLoading: true);
    try {
      final data = await MockApi.instance.getMemberById(userId);
      if (data == null) {
        state = state.copyWith(
          profile: ProfileModel(
            fullName: 'Unknown User',
            preference: 'Looking for Friends',
            interests: const [],
            galleryImages: const [],
          ),
        );
      } else {
        state = state.copyWith(
          profile: ProfileModel(
            fullName: data['name'] ?? '',
            preference:
                (data['preference'] ?? 'Looking for Friends').toString(),
            interests:
                List<String>.from(data['interests'] ?? const <String>[]),
            galleryImages:
                List<String>.from(data['gallery_images'] ?? const <String>[]),
            profileImageUrl: data['profile_image_url'],
            dateOfBirth: data['date_of_birth'] != null
                ? DateTime.tryParse(data['date_of_birth'])
                : null,
            gender: data['gender'],
          ),
        );
      }
    } catch (e) {
      // Handle error
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> saveProfile() async {
    state = state.copyWith(isSaving: true);
    try {
      final me = await MockApi.instance.getCurrentUser();
      final memberId = (me['member_id'] ?? me['id']).toString();
      await MockApi.instance.updateProfile(
        userId: memberId,
        payload: state.profile.toJson(),
      );
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

  // New method to update date of birth
  void updateDateOfBirth(DateTime dateOfBirth) {
    state = state.copyWith(
      profile: state.profile.copyWith(dateOfBirth: dateOfBirth),
    );
  }

  // New method to update gender
  void updateGender(String? gender) {
    state = state.copyWith(profile: state.profile.copyWith(gender: gender));
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

  // Actions (printed in MockApi)
  Future<void> blockUser(String userId, {String? reason}) async {
    await MockApi.instance.blockUser(userId: userId, reason: reason);
  }

  Future<void> reportUser(String userId, {String? reason}) async {
    await MockApi.instance.reportUser(userId: userId, reason: reason);
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, ProfileState>(
  ProfileNotifier.new,
);
