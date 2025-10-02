# API Checkpoint — Implemented vs Pending

Tanggal: 2025-10-01

Ringkas Status
- Fokus Org 5; semua RPC prefiks `*_org5` tidak mengganggu aplikasi lain.
- FE sudah terhubung ke Supabase untuk login sync, profil, storage gambar, dan presence/geofence.

Implemented (DB + FE wired)
- Login/Customer
  - RPC `auth_sync_customer_login_org5(p_phone, p_full_name?, p_location_id?)` → Upsert `public.customers` (org=5), set `member_id=auth.uid()`
  - RPC `get_customer_detail_by_member_id_org5(p_member_id)` → 1 row customers
  - FE: `lib/features/auth/presentation/otp_page.dart`, `lib/core/services/supabase_api.dart`, `lib/features/home/providers/home_providers.dart`
- Profile + Storage
  - Bucket `memberavatars` (avatar) dan `membergallery` (galeri) + RLS prefix `org5/<uid>/*`
  - RPC `update_customer_profile_org5(...)` → update kolom profil customers
  - FE: `lib/core/services/supabase_api.dart` (upload + update), `lib/features/profile/providers/profile_provider.dart`
- Presence/Locations (Geofence)
  - Tabel `user_presence` (+ RLS), alter `locations` tambah `lat`, `lng`, `geofence_radius_m`
  - RPC: `presence_check_in_org5`, `presence_heartbeat_org5`, `presence_check_out_org5`, `get_current_presence_org5`, `get_locations_org5`
  - FE: `geofence_watcher.dart`, `presence_controller.dart`, `home_providers.dart`, `home_page.dart`, `location_card.dart`
  - Debug/env: `HEARTBEAT_SECONDS`, `GEOFENCE_POLL_SECONDS`, `GEOFENCE_DEBUG`, `DEBUG_LAT`, `DEBUG_LNG`

Pending (Belum dikerjakan / masih MockApi)
- Notifications
  - DB: butuh tabel `notifications` + RLS + RPC (list, mark-all, accept/decline connection request)
  - FE: ganti `notificationsProvider` dari MockApi ke Supabase
- Connections (social graph)
  - DB: tabel `connections` + RLS + RPC (send/accept/decline/unfriend)
  - FE: ganti Connect (members list/filters) agar memakai DB; online TTL via presence TTL view
- Chat
  - DB: `chat_rooms`, `chat_participants`, `chat_messages`, `chat_read_state` + RLS + RPC/helper queries
  - FE: ganti seluruh provider chat list/room/messages + unread
- Block/Report
  - DB: endpoint (tabel atau flag) untuk block/report user + filter di queries anggota/chat/notifikasi
  - FE: ganti aksi block/report MockApi
- Profile view (user lain)
  - DB: get member by id/member_id; join presence TTL untuk isOnline/lastSeen
  - FE: ganti `memberByIdProvider` MockApi
- Seeding lokasi
  - Lengkapi `lat/lng/geofence_radius_m` untuk semua lokasi Org 5

Selesai (tambahan)
- Discounts (Home carousel)
  - DB: RPC `get_discounts_org5()` + kolom opsional `image`, `valid_until`
  - FE: `discountsProvider` pakai Supabase

Catatan Rekomendasi Selanjutnya
- Tambahkan view `app_member_presence_v` untuk menghitung `is_online` (TTL 120s) dan `last_seen` agar FE mudah konsumsi pada Connect/Chat.
- Standardisasi `member_id = auth.uid()` di seluruh relasi baru (connections/chat/notifications) untuk konsistensi.
- Pastikan indeks mendukung query utama (locations by org, presence by user, discounts by org, dsb).

Referensi File DB & FE
- Migrations: `docs/migrations/2025-10-01-*.sql`
- API docs: `docs/api/login_flow_org5.md`, `docs/api/profile_update_org5.md`, `docs/api/presence_org5.md`
