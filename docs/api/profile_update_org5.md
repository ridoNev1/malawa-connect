# Profile Update (Org 5) — API & Storage

Status
- Implemented in DB and wired in FE.
- FE integration points:
  - `lib/features/profile/providers/profile_provider.dart` → load/save profile, upload avatar/galeri
  - `lib/core/services/supabase_api.dart` → upload + RPC helpers

Tujuan
- Memungkinkan FE memperbarui profil `public.customers` dan mengunggah gambar profil/galeri ke Supabase Storage tanpa perlu `active_organization_id` di JWT.

## Storage: Buckets `memberavatars` dan `membergallery`
- Buckets: `memberavatars` (public) untuk avatar, `membergallery` (public) untuk galeri
- Struktur path:
  - Avatar: `org5/<member_id>/profile.jpg`
  - Galeri: `org5/<member_id>/gallery/<timestamp>.jpg`
- Kebijakan RLS (pada `storage.objects`):
  - Insert/Update/Delete hanya untuk file di folder milik sendiri (prefix `org5/<auth.uid()>/*`).
  - Select: bucket public; tersedia juga policy select untuk `authenticated`.

Contoh FE (Dart)
```dart
// Upload avatar (bucket: memberavatars)
final url = await SupabaseApi.uploadAvatar(bytes: imageBytes);
// Upload gallery image (bucket: membergallery)
final url2 = await SupabaseApi.uploadGalleryImage(bytes: imageBytes);
```

## RPC: update_customer_profile_org5
- Path: Postgres RPC (public)
- Security: SECURITY DEFINER; granted ke `authenticated` dan `service_role`.
- Parameter (semua opsional; hanya yang dikirim yang akan di-update):
  - `p_full_name` text
  - `p_preference` text
  - `p_interests` text[]
  - `p_gallery_images` text[]
  - `p_profile_image_url` text
  - `p_date_of_birth` date (YYYY-MM-DD)
  - `p_gender` text
  - `p_visibility` boolean
  - `p_search_radius_km` numeric
  - `p_location_id` bigint
  - `p_notes` text
- Target baris: `customers.member_id = auth.uid()` dan `organization_id = 5`.
- Return: row `public.customers` terbaru.

Contoh FE (Dart)
```dart
await SupabaseApi.updateCustomerProfileOrg5(
  fullName: state.profile.fullName,
  preference: state.profile.preference,
  interests: state.profile.interests,
  galleryImages: state.profile.galleryImages,
  profileImageUrl: state.profile.profileImageUrl,
  dateOfBirth: state.profile.dateOfBirth,
  gender: state.profile.gender,
);
```

## Alur Simpan Profil di FE
1) Pengguna memilih foto → FE unggah ke `avatars` → dapatkan public URL
2) FE panggil `update_customer_profile_org5` dengan field-field yang diperbarui (termasuk URL baru)
3) FE refresh state profil bila perlu

Env terkait
- `.env` (opsional untuk debug/testing geofence & heartbeat yang mempengaruhi pengalaman profil di Home)
  - `HEARTBEAT_SECONDS` (default 60)
  - `GEOFENCE_POLL_SECONDS` (default 20)

## Catatan
- Jika ingin bucket privat: atur `public => false` saat create_bucket dan gunakan `createSignedUrl` untuk menampilkan gambar.
- Field numeric/date harus dikirim dengan format yang benar; date gunakan `YYYY-MM-DD`.
