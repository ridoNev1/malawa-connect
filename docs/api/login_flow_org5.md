# Login Flow (Org 5) — API RPC

Status
- Implemented in DB and wired in FE.
- FE integration points:
  - `lib/features/auth/presentation/otp_page.dart` → call `auth_sync_customer_login_org5` after OTP verify
  - `lib/core/services/supabase_api.dart` → helpers
  - `lib/features/home/providers/home_providers.dart` → `currentUserProvider`

Tujuan
- Menghubungkan FE setelah OTP ke data nyata di tabel `public.customers` tanpa perlu klaim `active_organization_id`.
- Default organisasi: 5.

## RPC: auth_sync_customer_login_org5
- Path: Postgres RPC (public)
- Security: SECURITY DEFINER, di-grant ke `authenticated` dan `service_role`.
- Parameter
  - `p_phone` text — nomor telepon dalam format `62XXXXXXXXXX` (tanpa plus)
  - `p_full_name` text? — opsional
  - `p_location_id` bigint? — opsional
- Perilaku
  - Jika ada baris `customers` dengan `phone_number = p_phone` di org 5 (atau baris lama org NULL): update baris, set `member_id = auth.uid()` dan `organization_id = 5`.
  - Jika tidak ada: insert baris baru dengan `organization_id = 5` dan `member_id = auth.uid()`.
- Return: 1 row dari `public.customers` (hasil upsert).

Contoh FE (Dart)
```dart
final phone62 = '62$cleanPhone';
await Supabase.instance.client
    .rpc('auth_sync_customer_login_org5', params: {
  'p_phone': phone62,
  // 'p_full_name': 'John Doe',
  // 'p_location_id': 7,
});
```

Catatan: Tidak perlu set klaim `active_organization_id` untuk RPC ini.

Env terkait
- `.env` Supabase standar: `SUPABASE_URL`, `SUPABASE_ANON_KEY`
- Tidak membutuhkan `active_organization_id` di JWT.

## RPC: get_customer_detail_by_member_id_org5
- Path: Postgres RPC (public)
- Security: SECURITY DEFINER, di-grant ke `authenticated` dan `service_role`.
- Parameter
  - `p_member_id` uuid — biasanya `supabase.auth.currentUser!.id`
- Perilaku
  - Ambil 1 baris dari `public.customers` untuk `organization_id = 5` yang cocok dengan `member_id`.
- Return: 1 row dari `public.customers`.

Contoh FE (Dart)
```dart
final uid = Supabase.instance.client.auth.currentUser!.id;
final data = await Supabase.instance.client
    .rpc('get_customer_detail_by_member_id_org5', params: {
  'p_member_id': uid,
});
// data is Map<String, dynamic> (row customers)
```

## Alur FE Setelah OTP
1) Verifikasi OTP (Supabase Auth)
2) Panggil `auth_sync_customer_login_org5(p_phone)` untuk menautkan/menyisipkan baris `customers` org 5
3) Muat profil current user via `get_customer_detail_by_member_id_org5(p_member_id)`

## Field Utama di public.customers (relevan FE)
- `full_name`, `phone_number`, `member_id` (uuid), `organization_id` (5), `location_id`
- `preference`, `interests` (text[]), `gallery_images` (text[]), `profile_image_url`
- `date_of_birth`, `gender`, `visibility`, `search_radius_km`, `total_point`, `created_at`, `last_visit_at`, `notes`

## Format Nomor Telepon
- Simpan sebagai `62XXXXXXXXXX` (tanpa tanda `+`).
- OTP Supabase boleh diverifikasi dengan `+62...`, namun RPC gunakan `62...` agar konsisten dengan penyimpanan.
