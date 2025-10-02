# Chat (Org 5) — RPC + DB Broadcast Realtime

Status
- Designed for realtime without Postgres Changes or DB extension: uses Realtime Channels (client broadcast).
- DB is source of truth via RPC; client broadcasts carry deltas for instant UI.

Schema
- Tables
  - `chat_rooms(id uuid pk, is_group bool, last_message_text text, last_message_at timestamptz, created_at timestamptz)`
  - `chat_participants(chat_id uuid, user_id uuid, unread_count int, archived bool, pk(chat_id,user_id))`
  - `chat_messages(id uuid pk, chat_id uuid, sender_id uuid, text text, is_image bool, image_url text, created_at timestamptz)`
  - `chat_read_state(chat_id uuid, user_id uuid, last_read_at timestamptz, last_read_message_id uuid, pk(chat_id,user_id))`
- RLS
  - `is_chat_participant(chat_id, user_id=auth.uid())` guards SELECT/INSERT/UPDATE.
- Indexes
  - `chat_messages(chat_id, created_at desc)`, `chat_participants(user_id)`, `chat_rooms(last_message_at desc)`

Storage (Images)
- Bucket: `chatimages` (private)
- Path: `org5/<chat_id>/<timestamp>.jpg`
- Policy: allow select/insert when `is_chat_participant(chat_id_from_path(name))`.

Realtime Design (Channels)
- Channel names
  - Room: `room:<chat_id>` — events: `message`, `read` (optional)
  - User: `user:<user_id>` — events: `chat_update` (list preview/unread)
- Client responsibility
  - After `send_message_org5` succeeds, client broadcasts to `room:<chat_id>` with the new message and to `user:<peer_uid>` (or subscribe to all rooms) for list preview/unread.
  - Periodic light refetch on screen focus as a safety net.

RPC
- `get_or_create_direct_chat_org5(peer_id)` → `chat_rooms`
- `get_chat_list_org5(search?, limit=20, offset=0)` → TABLE(id, name, avatar, lastMessage, lastMessageTime, unreadCount, isOnline)
- `get_room_header_org5(chat_id)` → JSONB(id, name, avatar, peer_id, isOnline, lastSeen)
- `get_messages_org5(chat_id, limit=50, before?)` → TABLE(id, text, isImage, imageUrl, created_at, isMine)
- `send_message_org5(chat_id, text, is_image=false, image_url?, client_id?)` → `chat_messages`
  - Inserts message, updates `chat_rooms.last_message_*`, increments `unread_count` for other participants
  - Client broadcasts the `message` and `chat_update` events after success
- `mark_read_org5(chat_id)` → int
  - Upserts `chat_read_state` and sets `chat_participants.unread_count=0` for current user
  - Broadcasts `room:<chat_id>` event `read` with payload `{ chat_id, user_id, last_read_at }`

Client Integration (Flutter)
- Subscribe
  - `client.channel('room:$chatId').onBroadcast((e) { if (e.event=='message') append(e.payload.message); }).subscribe();`
  - `client.channel('user:$uid').onBroadcast((e) { if (e.event=='chat_update') updateList(e.payload); }).subscribe();`
- Send (optimistic)
  - Generate `clientId = Uuid().v4()`
  - Append optimistic; call `send_message_org5(chatId, text, false, null, clientId)`
  - On broadcast/return, reconcile by id/client_id
  - Additionally broadcast to `user:<peer_id>` event `chat_update` to update the peer’s list instantly
- Mark read
  - On room open/focus: call `mark_read_org5(chatId)`;
  - Optionally listen to user channel updates for `unreadCount` in the list

Security
- All RPCs set `SECURITY DEFINER` and are REVOKEd from `PUBLIC/anon`; only `authenticated` and `service_role` can execute.

Notes
- DB presence (online) is derived from `user_presence` TTL 120s, as in presence RPCs.
- This design works without enabling Postgres Changes replication or DB extensions; realtime is delivered via client Channels. Images stored in private bucket `chatimages` use signed URLs on render.
