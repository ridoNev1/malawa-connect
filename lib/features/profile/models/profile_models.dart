// lib/features/profile/models/profile_models.dart

class ProfileModel {
  final String fullName;
  final String preference;
  final List<String> interests;
  final List<String> galleryImages;
  String? profileImageUrl;
  final DateTime? dateOfBirth;
  final String? gender;

  ProfileModel({
    required this.fullName,
    required this.preference,
    required this.interests,
    required this.galleryImages,
    this.profileImageUrl,
    this.dateOfBirth,
    this.gender,
  });

  ProfileModel copyWith({
    String? fullName,
    String? preference,
    List<String>? interests,
    List<String>? galleryImages,
    String? profileImageUrl,
    DateTime? dateOfBirth,
    String? gender,
  }) {
    return ProfileModel(
      fullName: fullName ?? this.fullName,
      preference: preference ?? this.preference,
      interests: interests ?? this.interests,
      galleryImages: galleryImages ?? this.galleryImages,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
    );
  }

  // Helper method untuk menghitung usia
  int? get age {
    if (dateOfBirth == null) return null;

    final now = DateTime.now();
    int age = now.year - dateOfBirth!.year;

    // Periksa apakah ulang tahun sudah lewat tahun ini
    if (now.month < dateOfBirth!.month ||
        (now.month == dateOfBirth!.month && now.day < dateOfBirth!.day)) {
      age--;
    }

    return age;
  }

  Map<String, dynamic> toJson() {
    return {
      'full_name': fullName,
      'preference': preference,
      'interests': interests,
      'gallery_images': galleryImages,
      'profile_image_url': profileImageUrl,
      'date_of_birth': dateOfBirth?.toIso8601String(),
      'gender': gender,
    };
  }
}
