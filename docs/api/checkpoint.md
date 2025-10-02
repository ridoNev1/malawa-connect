# API Checkpoint — Implemented vs Pending

Tanggal: 2025-10-02 (checkpoint cleanup — update 2)

Ringkas Status
- Fokus Org 5; semua RPC prefiks `*_org5` tidak mengganggu aplikasi lain.
- FE terhubung ke Supabase untuk login sync, profil, storage gambar, presence/geofence, connections, chat, dan notifications (Realtime Postgres Changes + fallback polling).

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
- Notifications
  - Tabel `notifications` (+ RLS)
  - RPC: `get_notifications_org5`, `mark_notification_read_org5`, `mark_all_notifications_read_org5`
  - Integrasi Connections: `send/accept/decline` menulis notifikasi counterpart
  - Integrasi Chat: `send_message_org5` membuat notifikasi `newMessage` untuk participant lain
  - FE: `notificationsProvider` pakai Supabase + Realtime Postgres Changes, menampilkan `newMessage`
  - Foreground local notifications (in‑app) via `flutter_local_notifications` saat INSERT di `public.notifications`
  - Fallback polling 10s bila Postgres Changes belum aktif
- Connections (Connect list/detail)
  - RPC: `get_members_org5` (dedup latest connection per peer), `get_member_detail_org5` (menambahkan `connection_status`, `connection_type`)
  - DB: `get_members_org5` menambahkan fallback lokasi dari presence terakhir (bila `customers.location_id` NULL) → `location_name`
  - FE: Connect list membaca `location_name`; MemberCard gunakan ikon gender yang tepat
- Chat (Org 5)
  - DB: `chat_rooms`, `chat_participants`, `chat_messages`, `chat_read_state` + RLS + RPC
    - RPC: `get_or_create_direct_chat_org5`, `get_chat_list_org5`, `get_room_header_org5`, `get_messages_org5`, `send_message_org5`, `mark_read_org5`
    - `send_message_org5`: set `last_message_text='[image]'` bila `is_image=true`; insert notifikasi `newMessage`
    - `get_room_header_org5`: kembalikan `peer_id`, `isOnline`, `lastSeen`, serta `locationId`/`locationName` (presence-first)
  - Storage: bucket privat `chatimages`; FE render gambar via signed URL dari `createSignedUrl`
  - FE: Chat list/room terhubung RPC + Realtime Channels (client broadcast) untuk update instan

Pending (Belum dikerjakan / masih MockApi)
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
- In-app presence (avatar-only)
  - FE: Realtime Channels broadcast `active` setiap 10s → indikator nempel avatar hanya saat user benar-benar membuka app
  - Indikator online lain tetap mengikuti presence TTL (geofence)
- Android back gesture
  - Manifest: `android:enableOnBackInvokedCallback="true"`

Referensi File DB & FE
- Migrations: `docs/migrations/2025-10-01-*.sql`, `docs/migrations/2025-10-02-notifications-org5.sql`, `docs/migrations/2025-10-02-chat-org5.sql`
- API docs: `docs/api/login_flow_org5.md`, `docs/api/profile_update_org5.md`, `docs/api/presence_org5.md`, `docs/api/notifications_org5.md`

Catatan Dev — Local Notifications
- Setelah menambah plugin `flutter_local_notifications`, lakukan full rebuild (bukan hot restart):
  1) `flutter clean && flutter pub get`
  2) Stop app sepenuhnya, jalankan `flutter run`
  3) iOS: jalankan `pod install` di `ios/`
- Runtime permission Android 13+: pastikan izin POST_NOTIFICATIONS diapprove (provider izin di FE sudah menanganinya).
