# Lib Directory Overview

This document summarizes the structure and responsibilities of the `lib/` folder for Malawa Connect. It focuses on the layers, shared infrastructure, and feature modules that now primarily integrate with Supabase. A lightweight Mock API remains only for a few development fallbacks.

## Application Entry Points

- `lib/main.dart` initializes Flutter bindings, loads environment variables via `flutter_dotenv`, prepares the Supabase client, and boots the widget tree with `MalawaApp`.
- `lib/app.dart` wraps the app in a global `ProviderScope` (Riverpod v3) and configures a `MaterialApp.router` that uses the shared theme and GoRouter instance.

## Core Layer

- `lib/core/router/app_router.dart` declares the global `GoRouter` with routes for auth, home, connect, chat, notifications, and profile flows. It also contains a lightweight decision page that redirects based on the Supabase session state.
- `lib/core/services/mock_api.dart` now provides a minimal in-memory backend used only for:
  - Chat demo data (chat list, messages) pending DB migration
  - Block/report mock actions inside profile
  - Fallback `getLocations()` when unauthenticated/offline
  The previous mock endpoints (members, discounts, presence, notifications) have been removed in favor of Supabase RPCs.
- `lib/core/services/location_service.dart` centralizes geolocation access for geofencing logic, while `lib/core/services/notification_permission_service.dart` and `lib/core/services/supabase_client.dart` provide platform integrations for notifications and Supabase respectively.
- `lib/core/theme/theme.dart` defines the shared color palette, typography, and component themes that are reused by all feature screens.
- `lib/core/config` contains configuration primitives (e.g., constants) that can be injected into features without duplicating magic numbers.

## Shared Widgets

- `lib/shared/widgets` hosts reusable UI components such as headers, cards, buttons, and list items that appear across multiple feature flows. These widgets are designed to consume Riverpod-provided data and theming from the core layer to keep feature widgets lean.

## Feature Modules

Each folder under `lib/features` owns a vertical slice: presentation widgets, state providers, and any feature-specific models. Most slices now consume Supabase RPCs directly.

- **Auth (`lib/features/auth`)**: Screens for login and OTP verification drive Supabase-based authentication before handing off to the home experience.
- **Home (`lib/features/home`)**: Providers aggregate current user, membership, discounts, presence, and notification badge information. Presentation code renders the dashboard, membership card, and live presence duration, and wires geofence triggers through the presence controller.
- **Connect (`lib/features/connect`)**: `MembersNotifier` orchestrates tab switching, filters, debounced search, pagination, and derived statistics for the member directory. DB `get_members_org5` kini menambahkan fallback lokasi dari presence terakhir (bila `customers.location_id` kosong) dan deduplikasi koneksi. UI MemberCard menampilkan ikon gender yang tepat dan dot “in‑app active” (Realtime broadcast) pada avatar.
- **Profile (`lib/features/profile`)**: Providers fetch either the current user or another member, expose actions for updating profile data, blocking, and reporting, and drive gallery/online indicator widgets for both edit and view modes.
- **Chat (`lib/features/chat`)**: Chat list and room providers terhubung RPC Supabase; menampilkan placeholder `[image]` pada list untuk pesan gambar (dipetakan UI menjadi “Mengirim gambar”). Room merender gambar via signed URL dari bucket privat `chatimages`. Header room mengandalkan `get_room_header_org5` (peer_id, lokasi presence, status online). Broadcast Realtime digunakan untuk update instan.
- **Notifications (`lib/features/notifications`)**: Riverpod state manages notification fetching, pull-to-refresh, mark-all, dan actions. Mendengarkan Realtime postgres_changes untuk INSERT pada `public.notifications`, serta menampilkan `newMessage`. Foreground local notifications (in‑app) menggunakan `flutter_local_notifications` saat adanya notifikasi baru.

## Relationship to Mock Documentation

Legacy docs (`features_summary.md`, `moc_fe.md`) described a fully mocked stack. The codebase has transitioned to Supabase for auth, profile, presence/geofence, locations, discounts, connections, chat, and notifications. Mock API tersisa hanya untuk aksi block/report (sementara) dan beberapa fallback dev.

## In‑App Presence (Avatar‑only)
- Realtime Channels: channel `'app:presence:org5'` digunakan untuk broadcast `{ uid }` setiap 10 detik saat app aktif. FE menyimpan `activeUids` dengan TTL ~20 detik.
- Dot avatar (hijau/abu‑abu) hanya merefleksikan “app sedang dibuka”, terpisah dari status online berdasarkan geofence/presence TTL.
