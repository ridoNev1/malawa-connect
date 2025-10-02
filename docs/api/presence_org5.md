# Presence (Org 5) — Check-in / Heartbeat / Checkout

Status
- Implemented in DB and wired in FE.
- FE integration points:
  - Watcher: `lib/features/home/providers/geofence_watcher.dart`
  - Controller: `lib/features/home/providers/presence_controller.dart`
  - Providers: `lib/features/home/providers/home_providers.dart` (`presenceProvider`, `locationsOrg5Provider`)
  - UI: `lib/features/home/presentation/home_page.dart` (LocationCard)

Tujuan
- Mendukung alur check-in/out berbasis lokasi dan TTL online untuk FE, tanpa perlu `active_organization_id`.

## Modifikasi Schema
- Tabel `public.locations` ditambah kolom:
  - `lat` double precision
  - `lng` double precision
  - `geofence_radius_m` int default 100 (NOT NULL)
- Tabel baru `public.user_presence`:
  - `id` uuid (PK), `user_id` uuid (customers.member_id), `location_id` bigint
  - `check_in_at` timestamptz, `last_heartbeat_at` timestamptz, `check_out_at` timestamptz
  - Index: `user_id`, partial `user_id WHERE check_out_at IS NULL`
  - RLS: select/insert/update untuk user sendiri

## RPC
- `presence_check_in_org5(p_location_id bigint) → user_presence`
  - Menutup presence aktif sebelumnya, membuat presence baru pada lokasi di org 5.
- `presence_heartbeat_org5() → void`
  - Update `last_heartbeat_at` pada presence aktif.
- `presence_check_out_org5() → void`
  - Set `check_out_at` pada presence aktif.
- `get_current_presence_org5() → jsonb`
  - Mengembalikan: `{ location_id, location_name, check_in_time, last_heartbeat_at }` untuk presence aktif.
- `get_locations_org5() → TABLE(id, name, address, lat, lng, geofence_radius_m)`
  - Daftar lokasi Org 5 beserta koordinat dan radius geofence.

## Alur FE
1) Geofence lokal di FE (pakai `lat/lng/geofence_radius_m` dari locations)
2) Masuk radius → `presence_check_in_org5(locationId)` → mulai heartbeat 60s
3) Keluar radius → `presence_check_out_org5()` → hentikan heartbeat
4) Tampilkan status di Home/Profile dari `get_current_presence_org5()`
5) Heartbeat memicu re-evaluasi geofence dan refresh presence agar UI selalu sinkron

### Debug di Simulator/Emulator
- iOS Simulator: Features → Location → Custom Location, masukkan lat/lng lokasi (mis. `-6.4272649, 106.9712794`).
- Android Emulator: Extended controls → Location → masukkan lat/lng.
- Alternatif override dari .env (hanya debug):
  - Tambahkan pada `.env`:
    - `GEOFENCE_DEBUG=true`
    - `DEBUG_LAT=-6.4272649`
    - `DEBUG_LNG=106.9712794`
  - FE akan memakai koordinat ini saat evaluasi geofence.

Env terkait
- `HEARTBEAT_SECONDS` (default 60)
- `GEOFENCE_POLL_SECONDS` (default 20)

## Contoh FE (Dart)
```dart
// Check-in
await SupabaseApi.checkIn(locationId: 7);
// Heartbeat (tiap 60s)
await SupabaseApi.heartbeat();
// Check-out
await SupabaseApi.checkOut();
// Presence summary
final p = await SupabaseApi.getCurrentPresence();
// Get locations for geofencing
final locs = await SupabaseApi.getLocationsOrg5();
```

Catatan
- TTL online 120s (untuk status user lain) bisa diturunkan dari `last_heartbeat_at` pada sisi FE atau dibuat view tambahan bila diperlukan.
