// lib/features/profile/providers/profile_provider.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/mock_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_api.dart';
import '../models/profile_models.dart';
import '../../home/providers/home_providers.dart';

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
      // Load from Supabase (Org 5)
      final uid = Supabase.instance.client.auth.currentUser?.id;
      Map<String, dynamic>? me;
      if (uid != null) {
        me = await SupabaseApi.getCustomerByMemberIdOrg5(memberId: uid);
      }
      state = state.copyWith(
        profile: ProfileModel(
          fullName: me?['full_name'] ?? '',
          preference: (me?['preference'] ?? 'Looking for Friends').toString(),
          interests: List<String>.from(me?['interests'] ?? const <String>[]),
          galleryImages: List<String>.from(
            me?['gallery_images'] ?? const <String>[],
          ),
          profileImageUrl: me?['profile_image_url'],
          dateOfBirth: me?['date_of_birth'] != null
              ? DateTime.tryParse(me?['date_of_birth'])
              : null,
          gender: me?['gender'],
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
      final data = await SupabaseApi.getMemberDetailOrg5(id: userId);
      final safe = data ?? const <String, dynamic>{};
      state = state.copyWith(
        profile: ProfileModel(
          fullName: (safe['name'] ?? 'Unknown User').toString(),
          preference: (safe['preference'] ?? 'Looking for Friends').toString(),
          interests: List<String>.from(safe['interests'] ?? const <String>[]),
          galleryImages:
              List<String>.from(safe['gallery_images'] ?? const <String>[]),
          profileImageUrl: safe['avatar'],
          dateOfBirth: safe['date_of_birth'] != null
              ? DateTime.tryParse(safe['date_of_birth'].toString())
              : null,
          gender: safe['gender'],
        ),
      );
    } catch (e) {
      // Fallback to minimal placeholder on error
      state = state.copyWith(
        profile: ProfileModel(
          fullName: 'Unknown User',
          preference: 'Looking for Friends',
          interests: const [],
          galleryImages: const [],
        ),
      );
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> saveProfile() async {
    state = state.copyWith(isSaving: true);
    try {
      final updated = await SupabaseApi.updateCustomerProfileOrg5(
        fullName: state.profile.fullName,
        preference: state.profile.preference,
        interests: state.profile.interests,
        galleryImages: state.profile.galleryImages,
        profileImageUrl: state.profile.profileImageUrl,
        dateOfBirth: state.profile.dateOfBirth,
        gender: state.profile.gender,
      );
      // Update local state with server response if available
      if (updated != null) {
        state = state.copyWith(
          profile: ProfileModel(
            fullName: (updated['full_name'] ?? '').toString(),
            preference: (updated['preference'] ?? 'Looking for Friends')
                .toString(),
            interests: List<String>.from(
              updated['interests'] ?? const <String>[],
            ),
            galleryImages: List<String>.from(
              updated['gallery_images'] ?? const <String>[],
            ),
            profileImageUrl: updated['profile_image_url'],
            dateOfBirth: updated['date_of_birth'] != null
                ? DateTime.tryParse(updated['date_of_birth'].toString())
                : null,
            gender: updated['gender'],
          ),
        );
      }
      // Invalidate home providers so Home reflects latest data
      ref.invalidate(currentUserProvider);
      ref.invalidate(membershipSummaryProvider);
    } catch (e) {
      // Handle error silently
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
        try {
          final url = await SupabaseApi.uploadAvatar(
            bytes: Uint8List.fromList(bytes),
          );
          state = state.copyWith(
            profile: state.profile.copyWith(
              profileImageUrl: url ?? state.profile.profileImageUrl,
            ),
            isLoading: false,
          );
        } catch (_) {
          // Fallback: keep base64 to preserve UI
          final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          state = state.copyWith(
            profile: state.profile.copyWith(profileImageUrl: base64String),
            isLoading: false,
          );
        }
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
        try {
          final url = await SupabaseApi.uploadGalleryImage(
            bytes: Uint8List.fromList(bytes),
          );
          final updatedGalleryImages = List<String>.from(
            state.profile.galleryImages,
          );
          if (url != null) updatedGalleryImages.add(url);
          state = state.copyWith(
            profile: state.profile.copyWith(
              galleryImages: updatedGalleryImages,
            ),
            isLoading: false,
          );
        } catch (_) {
          // Fallback to base64
          final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';
          final updatedGalleryImages = List<String>.from(
            state.profile.galleryImages,
          );
          updatedGalleryImages.add(base64String);
          state = state.copyWith(
            profile: state.profile.copyWith(
              galleryImages: updatedGalleryImages,
            ),
            isLoading: false,
          );
        }
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
