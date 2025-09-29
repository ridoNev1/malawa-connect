// lib/features/profile/models/profile_models.dart
class ProfileModel {
  final String fullName;
  final String preference;
  final List<String> interests;
  final List<String> galleryImages;
  String? profileImageUrl;

  ProfileModel({
    required this.fullName,
    required this.preference,
    required this.interests,
    required this.galleryImages,
    this.profileImageUrl,
  });

  ProfileModel copyWith({
    String? fullName,
    String? preference,
    List<String>? interests,
    List<String>? galleryImages,
    String? profileImageUrl,
  }) {
    return ProfileModel(
      fullName: fullName ?? this.fullName,
      preference: preference ?? this.preference,
      interests: interests ?? this.interests,
      galleryImages: galleryImages ?? this.galleryImages,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'full_name': fullName,
      'preference': preference,
      'interests': interests,
      'gallery_images': galleryImages,
      'profile_image_url': profileImageUrl,
    };
  }
}
