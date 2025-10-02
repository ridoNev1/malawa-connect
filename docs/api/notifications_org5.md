# Notifications (Org 5)

Status
- Implemented in DB and wired in FE with Supabase Realtime.

Schema
- Table: `public.notifications`
  - `id` uuid (PK)
  - `user_id` uuid (recipient; equals `customers.member_id`)
  - `sender_id` uuid? (actor)
  - `type` text: `newMessage` | `connectionRequest` | `connectionAccepted` | `connectionRejected`
  - `title` text, `message` text
  - `is_read` bool default false, `requires_action` bool default false
  - `payload` jsonb?
  - `organization_id` bigint default 5
  - `created_at` timestamptz default now()

RLS
- Select: only recipient can view their notifications (Org 5)
- Update: disabled; clients use RPCs to mark as read

RPC
- `get_notifications_org5(p_only_unread boolean = false, p_limit int = 50)` → TABLE
  - Joins sender to `customers` for `senderName`, `senderAvatar`
- Returns fields: `id, type, title, message, senderId, senderName, senderAvatar, created_at, isRead, requiresAction, payload`
- `mark_notification_read_org5(p_id uuid)` → notifications (juga menyetel `requires_action=false`)
- `mark_all_notifications_read_org5()` → int (affected rows)

Integration with Connections
- Focus saat ini: hanya `connectionAccepted` yang menghasilkan notifikasi.
- `accept_connection_request_org5` mengirim notifikasi `connectionAccepted` ke requester.
- Tidak ada notifikasi untuk `connectionRequest` maupun `connectionRejected` (bisa ditambah nanti).

FE Integration
- Provider: `lib/features/notifications/providers/notifications_provider.dart`
  - Fetches via `get_notifications_org5`
  - Marks via `mark_notification_read_org5` and `mark_all_notifications_read_org5`
  - Subscribes to Realtime `postgres_changes` on `public.notifications` filtered by `user_id = current uid` to live-update list and unread count
- API helper: `lib/core/services/supabase_api.dart`
  - Methods `getNotificationsOrg5`, `markNotificationReadOrg5`, `markAllNotificationsReadOrg5`

Realtime Setup (Fallback polling jika Postgres Changes belum tersedia)
- Jika fitur Postgres Changes (replication) belum aktif di project Anda, provider akan melakukan polling setiap 10 detik.
- Saat Anda sudah mendapatkan akses Realtime Postgres Changes, cukup aktifkan untuk schema/table terkait; provider sudah siap mendengarkan `INSERT/UPDATE` pada `public.notifications`.

Example FE (Dart)
```dart
final items = await SupabaseApi.getNotificationsOrg5(onlyUnread: false, limit: 50);
await SupabaseApi.markAllNotificationsReadOrg5();
await SupabaseApi.markNotificationReadOrg5(id: notifId);

// Realtime is auto-wired in notificationsProvider; no extra code needed in widgets.
```
