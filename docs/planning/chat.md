# Chat Realtime Plan (Org 5)

Goal
- Migrate chat list + chat room from Mock to Supabase with realtime updates, without Postgres Changes replication.

Approach
- Use Realtime Channels (client broadcast); DB remains source of truth via RPCs.
- FE subscribes to two channels:
  - `user:<uid>` for list preview/unread updates
  - `room:<chat_id>` for message timeline + read receipts

DB Tasks
- Create tables: `chat_rooms`, `chat_participants`, `chat_messages`, `chat_read_state` (with indexes).
- Add RLS with helper `is_chat_participant(chat_id, user_id=auth.uid())`.
- Storage bucket `chatimages` (private) + path `org5/<chat_id>/<timestamp>.jpg`; policies based on participant.
- RPCs (SECURITY DEFINER):
  1) `get_or_create_direct_chat_org5(peer_id)`
  2) `get_chat_list_org5(search?, limit, offset)`
  3) `get_room_header_org5(chat_id)`
  4) `get_messages_org5(chat_id, limit, before?)`
  5) `send_message_org5(chat_id, text, is_image?, image_url?, client_id?)`
  6) `mark_read_org5(chat_id)` — resets unread
- REVOKE EXECUTE from PUBLIC/anon; GRANT to authenticated/service_role.

FE Tasks
- Add SupabaseApi methods for all RPCs above.
- Chat List Provider
  - Load via `get_chat_list_org5`
  - Subscribe to `user:<uid>` broadcast → update lastMessage/unread; resort
- Chat Room Provider
  - Load header via `get_room_header_org5`
  - Load messages via `get_messages_org5`
  - Subscribe to `room:<chat_id>` broadcast for event `message` → append; event `read` (optional)
  - Sending message: optimistic + `send_message_org5` + client broadcast to `room:<chat_id>` + reconcile by `id/client_id`
  - On open/focus: call `mark_read_org5`
- Typing indicator (phase 2): client → client broadcast on `room:<chat_id>`

Validation
- Two devices/users:
  - A send → B sees timeline update instantly via `room:<chat_id>`
  - List at A & B updates last message + unread via `user:<uid>`
  - B opens room → `mark_read_org5` resets unread; A gets optional `read` event

Risks & Mitigation
- Broadcast delivery isn’t persisted → periodic light refetch (on focus) as safety net.
- Signed URL expiry → cache + refresh on demand.

Next Steps
- [x] Add migration `2025-10-02-chat-org5.sql` (tables, RLS, RPCs, broadcast, storage policies)
- [x] Add docs `docs/api/chat_org5.md`
- [ ] Implement SupabaseApi helpers (chat)
- [ ] Migrate FE providers (list/room) to Supabase + subscribe
- [ ] Add typing indicator + read receipts (optional)
- [ ] Wire notifications `newMessage` using the same broadcast pattern
