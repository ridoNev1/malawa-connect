Malawa Connect FE Data Contract (Concise)

Data Schema (Canonical)

```
// Current User (session + profile) (extend from table members);
CurrentUser {
  id: number,
  member_id: string,            // uuid
  location_id: number,          // base location used when offline/inactive
  full_name: string,
  phone_number: string,
  visit_count: number,
  last_visit_at: string,        // ISO
  notes: string|null,
  created_at: string,           // ISO
  total_point: number,
  organization_id: number,
  preference: string,
  interests: string[],
  gallery_images: string[],     // URL or data:image;base64
  profile_image_url: string|null,
  date_of_birth: string|null,   // YYYY-MM-DD
  gender: string|null,
  visibility: boolean,
  search_radius_km: number
}

// Member (Connect + Profile view)
Member {
  id: string,                   // legacy id (stringified)
  member_id: string,            // uuid
  location_id: number,
  name: string,
  avatar: string,               // URL
  isConnected: boolean,
  isOnline: boolean,
  lastSeen: string,
  distance?: string,            // e.g. "0.5 km" (UI hint only)
  age?: number,
  gender?: string,
  preference: string,
  gallery_images: string[],
  profile_image_url: string|null,
  date_of_birth: string|null
}

// Location (Geofence-enabled)
Location {
  id: number,
  name: string,
  address: string,
  lat?: number,
  lng?: number,
  geofence_radius_m?: number,   // default 100
  is_main_warehouse: boolean,
  restaurant_tables: Array<{ id:number, name:string, status:string, capacity:number, deleted_at:string|null, location_id:number }>
}

// Presence summary (current user)
Presence {
  location_id: number,
  location_name: string,
  check_in_time: string,        // ISO
  last_heartbeat_at: string     // ISO
}

// Discount
Discount {
  id: number,
  name: string,
  description: string,
  type: string,                 // e.g. "percentage"
  value: number,
  is_active: boolean,
  created_at: string,           // ISO
  unique_code: string,
  organization_id: number,
  image: string|null,
  valid_until: string           // YYYY-MM-DD
}

// Chat list item
ChatListItem {
  id: string,                   // chat id; in mock equals member legacy id
  name: string,
  avatar: string,
  lastMessage: string,
  lastMessageTime: string,      // ISO
  unreadCount: number,
  isOnline: boolean
}

// Chat room header
ChatRoom {
  id: string,
  name: string,
  avatar: string,
  isOnline: boolean,
  lastSeen: string
}

// Chat message (UI model)
ChatMessage {
  id: string,
  text: string,
  isSentByMe: boolean,
  time: string,                 // e.g. "10:30 AM"
  showDate: boolean,
  showTime: boolean,
  isImage: boolean
}

// Notification
NotificationItem {
  id: string,
  type: 'newMessage'|'connectionRequest'|'connectionAccepted'|'connectionRejected',
  title: string,
  message: string,
  senderId: string,
  senderName: string,
  senderAvatar: string,
  timestamp: string,            // ISO
  isRead: boolean,
  requiresAction: boolean
}

// GET query shapes
MembersQuery {
  tab: 'nearest'|'network',
  status: 'Semua'|'Online'|'Friends'|'Partners',
  search: string,
  page: number,
  pageSize: number,
  locationId?: number,
  radiusKm?: number
}

PaginatedResult<T> {
  items: T[],
  page: number,
  pageSize: number,
  total: number,
  hasMore: boolean
}
```

Database Schema (Target BE)

```
-- 1) profiles (aka customers)
profiles (
  id                  int primary key,            -- legacy
  member_id           uuid unique not null,       -- for app relations
  full_name           text,
  phone_number        text unique,
  location_id         int,                        -- base location when offline
  preference          text,
  interests           text[],                     -- or jsonb
  gallery_images      text[],                     -- or separate table
  profile_image_url   text,
  date_of_birth       date,
  gender              text,
  visibility          boolean default true,
  search_radius_km    numeric default 3,
  total_point         int default 0,
  organization_id     int,
  last_visit_at       timestamptz,
  notes               text,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
)

-- 2) locations
locations (
  id                  int primary key,
  name                text not null,
  address             text,
  lat                 double precision,
  lng                 double precision,
  geofence_radius_m   int default 100,
  is_main_warehouse   boolean default false,
  created_at          timestamptz default now()
)

-- 3) user_presence
user_presence (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid references profiles(member_id) on delete cascade,
  location_id         int references locations(id),
  check_in_at         timestamptz default now(),
  last_heartbeat_at   timestamptz,
  check_out_at        timestamptz
)

-- 4) connections
connections (
  id                  uuid primary key default gen_random_uuid(),
  requester_id        uuid references profiles(member_id) on delete cascade,
  addressee_id        uuid references profiles(member_id) on delete cascade,
  status              text check (status in ('pending','accepted','declined','blocked')),
  message             text,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
)

-- 5) chat
chat_rooms (
  id                  uuid primary key default gen_random_uuid(),
  is_group            boolean default false,
  last_message_id     uuid,
  last_message_text   text,
  last_message_at     timestamptz,
  last_sender_id      uuid,
  created_at          timestamptz default now()
)
chat_participants (
  chat_id             uuid references chat_rooms(id) on delete cascade,
  user_id             uuid references profiles(member_id) on delete cascade,
  unread_count        int default 0,
  archived            boolean default false,
  primary key (chat_id, user_id)
)
chat_messages (
  id                  uuid primary key default gen_random_uuid(),
  chat_id             uuid references chat_rooms(id) on delete cascade,
  sender_id           uuid references profiles(member_id) on delete cascade,
  text                text,
  is_image            boolean default false,
  image_url           text,
  created_at          timestamptz default now()
)

-- 6) discounts
discounts (
  id                  uuid primary key default gen_random_uuid(),
  name                text,
  description         text,
  type                text,
  value               numeric,
  is_active           boolean,
  unique_code         text unique,
  organization_id     int,
  image               text,
  valid_until         date,
  created_at          timestamptz default now()
)
```

Mock API Endpoints (and file path)

- File: `lib/core/services/mock_api.dart`
- GET
  - getCurrentUser() → CurrentUser
  - getMembers(query: MembersQuery) → PaginatedResult<Member>
  - getMemberById(userId: string) → Member|null (id or member_id)
  - getLocations({search?}) → Location[]
  - getDiscounts({search?}) → Discount[]
  - getPresence() → Presence|null
  - getChatList({search?}) → ChatListItem[]
  - getChatById(chatId: string) → ChatListItem|null
  - getChatMessages(chatId: string) → ChatMessage[]
  - getNotifications() → NotificationItem[]
- Mutations/Actions
  - checkIn({locationId: int}) → void
  - checkOut() → void
  - heartbeat() → void
  - updateProfile({userId: string, payload: CurrentUser fields}) → void
  - toggleVisibility({visible: bool}) → void
  - updateSearchRadius({radiusKm: number}) → void
  - sendFriendRequest({toUserId: string, message?: string}) → void
  - acceptFriendRequest({requestId: string}) → void
  - declineFriendRequest({requestId: string}) → void
  - unfriend({userId: string}) → void
  - blockUser({userId: string, reason?: string}) → void  (affects mock filters)
  - reportUser({userId: string, reason?: string}) → void
  - sendMessage({chatId: string, text: string, isImage: bool}) → void
  - markChatAsRead(chatId: string) → void
  - getOrCreateDirectChatByUserId(userId: string) → ChatListItem
  - markNotificationRead(id: string) → void
  - markAllNotificationsRead() → void
  - acceptConnectionRequest(notificationId: string) → void
  - declineConnectionRequest(notificationId: string) → void

Provider Map (caller → provider → file → MockApi)

- Home
  - currentUserProvider → home_providers.dart → getCurrentUser
  - membershipSummaryProvider → home_providers.dart (derives from current user)
  - discountsProvider → home_providers.dart → getDiscounts
  - presenceProvider → home_providers.dart → getPresence
  - presenceControllerProvider → presence_controller.dart → checkIn/checkOut/heartbeat
  - geofenceWatcherProvider → geofence_watcher.dart → uses LocationService + presenceController
  - notificationPermissionProvider → notifications/providers/notification_permission_provider.dart
  - notificationsProvider → notifications/providers/notifications_provider.dart → notifications APIs

- Connect
  - membersProvider → connect/providers/members_provider.dart → getMembers
  - memberByIdProvider → connect/providers/member_detail_provider.dart → getMemberById

- Profile
  - profileProvider → profile/providers/profile_provider.dart → getCurrentUser / getMemberById / updateProfile / blockUser / reportUser

- Chat
  - chatListProvider → chat/providers/chat_list_provider.dart → getChatList / markChatAsRead
  - chatRoomProviderFamily → chat/providers/chat_room_provider.dart → getChatMessages / sendMessage / getChatById

- Notifications
  - notificationsProvider → notifications/providers/notifications_provider.dart → getNotifications / markAll / accept/decline

Nearest Filter Logic (recap)
- If presence active: base = presence.location_id
- Else: base = currentUser.location_id
- getMembers('nearest') filters members by base location.

**Identifiers**

- `id` (number): legacy PK from existing table.
- `member_id` (uuid string): app-level identifier. Prefer `member_id` for writes and cross-references. `id` remains for compatibility.

**Current User (Session)**

- Fields
  - `id` number, `member_id` string(uuid)
  - `location_id` int (base location used when user is offline/inactive)
  - `full_name` string, `phone_number` string
  - `visit_count` int, `last_visit_at` ISO string, `created_at` ISO string
  - `notes` string|null, `total_point` int, `organization_id` int
  - `preference` string, `interests` string[], `gallery_images` string[]
  - `profile_image_url` string|null, `date_of_birth` YYYY-MM-DD|null, `gender` string|null
  - `visibility` bool, `search_radius_km` number
- Example
  {"id":9,"member_id":"11111111-1111-4111-8111-111111111111","full_name":"Rido Testing","phone_number":"081217873551","visit_count":1,"last_visit_at":"2025-09-18T16:27:35.846213+00:00","notes":null,"created_at":"2025-09-18T16:27:35.846213+00:00","total_point":107,"organization_id":5,"preference":"Looking for Friends","interests":["Coffee","Music","Travel"],"gallery_images":[],"profile_image_url":"https://randomuser.me/api/portraits/men/12.jpg","date_of_birth":"1991-09-10","gender":"Laki-laki","visibility":true,"search_radius_km":3.0}

**Member (Connect + Profile View)**

- Fields
  - `id` string, `member_id` string(uuid)
  - `location_id` int (member’s current/base location)
  - `name` string, `avatar` string(URL)
  - `distance` string like "0.5 km" (nearest tab)
  - `interests` string[], `preference` string
  - `isConnected` bool, `isOnline` bool, `lastSeen` string
  - `age` int, `gender` string, `profile_image_url` string|null
  - `gallery_images` string[], `date_of_birth` YYYY-MM-DD|null
- Example
  {"id":"1","member_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","name":"Michael Chen","distance":"0.5 km","interests":["Coffee","Music","Travel"],"isConnected":false,"isOnline":true,"avatar":"https://randomuser.me/api/portraits/men/32.jpg","lastSeen":"Sekarang","age":35,"gender":"Laki-laki","preference":"Looking for Friends","gallery_images":["https://..."],"profile_image_url":"https://...","date_of_birth":"1988-08-20"}

**Locations**

- Fields
  - `id` int, `name` string, `address` string, `is_main_warehouse` bool
  - `lat` number (optional), `lng` number (optional)
  - `geofence_radius_m` int (optional, default 100) — radius lingkaran geofence untuk check‑in otomatis
  - `restaurant_tables`: [{`id` int, `name` string, `status` string, `capacity` int, `deleted_at` ISO|null, `location_id` int}]

**Presence (Current)**

- Fields
  - `location_id` int, `location_name` string, `check_in_time` ISO string

**Home (Derived Fields in FE)**

- Membership Summary (from Current User)
  - `membershipType` string (derived from `total_point` tier)
  - `points` int (from `total_point`)
  - `joinedAt` string (dd MMM yyyy) — derived from `created_at`
  - Note: In code, the provider currently passes this value via key `validUntil` for backward compatibility with the widget API. UI label shows “Bergabung pada”.
- Presence Duration
  - UI computes a human-readable duration from `check_in_time` → now, e.g. "2 jam 10 menit", "15 menit", "1 hari 2 jam".

**Geofencing & Online (Client Expectations)**

- FE collects current device location (lat/lng) dengan izin lokasi.
- FE menentukan check‑in otomatis jika berada di dalam lingkaran geofence suatu cabang:
  - inside if distance(device, location.lat/lng) <= `geofence_radius_m`.
  - default radius jika null: 100 meter.
- `search_radius_km` (di Current User) dipakai untuk pencarian Connect (bukan geofence check‑in).
- Online definition (ringkas): presence aktif (check_out null) + heartbeat masih dalam TTL.

**Mock Presence API (Implemented in FE)**

- checkIn({ locationId: int }) → creates active presence and sets last_heartbeat_at.
- heartbeat() → updates last_heartbeat_at on active presence.
- checkOut() → closes active presence.
- set_visibility({ visible: bool }) → available via profile actions; FE can call to hide status.
- Providers
  - `presenceProvider` (Future; current user presence summary)
  - `presenceControllerProvider` (Notifier; actions: checkIn, checkOut, startHeartbeat, stopHeartbeat, beatOnce)
  - `memberByIdProvider(userId)` (Future; returns member map with isOnline/lastSeen for profile view)

**Profile Online Indicator (UI)**

- Current user profile: uses `presenceProvider` → shows "Online di <location>" or "Offline".
- Other user profile: uses `memberByIdProvider(userId)` → shows Online/Last seen based on member mock data.

**Discounts**

- Fields
  - `id` int, `name` string, `description` string, `type` string, `value` number
  - `is_active` bool, `created_at` ISO string, `unique_code` string
  - `organization_id` int, `image` string|null, `valid_until` YYYY-MM-DD

**Chat List Item**

- Fields
  - `id` string(uuid), `name` string, `avatar` string
  - `lastMessage` string, `lastMessageTime` ISO string
  - `unreadCount` int, `isOnline` bool

**Chat Room (Header)**

- Fields
  - `id` string(uuid), `name` string, `avatar` string
  - `isOnline` bool, `lastSeen` string

**Chat Message (UI Model)**

- Fields
  - `id` string, `text` string, `isSentByMe` bool
  - `time` string (e.g. "10:30 AM"), `showDate` bool, `showTime` bool
  - `isImage` bool

**Blocking (Mock Behavior)**

- FE stores a simple blocked list in MockApi. Calls to `blockUser({ userId })` add both the legacy `id` and `member_id` (if known) to the block set.
- `getMembers` and `getChatList` exclude blocked users/chats.

**Chat Pagination (Mock)**

- Initial `loadMessages()` loads current page; `loadMore()` prepends mock older messages while `hasMore` is true (limited to a few pages for demo).

**Nearest Filter Logic (Connect)**

- Jika presence aktif: gunakan `presence.location_id` sebagai base untuk tab "nearest".
- Jika offline/tidak aktif: gunakan `currentUser.location_id` sebagai base.
- BE nanti cukup filter `members.location_id == base_location_id` untuk tab nearest.

**Notifications (Mock + Permission)**

- Permission
  - Android 13+: `POST_NOTIFICATIONS` is declared and requested at runtime via `permission_handler`.
  - iOS: permission requested at runtime via `permission_handler` (no extra Info.plist key needed for push prompt; runtime API triggers the dialog).
  - FE hook: `notificationPermissionProvider` is watched in Home to request once.
- Data
  - MockApi exposes: `getNotifications()`, `markAllNotificationsRead()`, `acceptConnectionRequest(id)`, `declineConnectionRequest(id)`.
  - Provider: `notificationsProvider` with actions `refresh`, `markAllRead`, `accept`, `decline`.

**Members GET Query (Client)**

- `MembersQuery`
  - `tab`: 'nearest' | 'network'
  - `status`: 'Semua' | 'Online' | 'Friends' | 'Partners'
  - `search`: string, `page`: int, `pageSize`: int
  - `locationId`?: int, `radiusKm`?: number
- `PaginatedResult<T>`
  - `items`: T[], `page`: int, `pageSize`: int, `total`: int, `hasMore`: bool

**Action Payloads (Client → BE)**

- Use `member_id` for `userId` where applicable.
- Examples
  - updateProfile: { userId: member_id, data: ProfileJson }
  - sendFriendRequest: { toUserId: member_id, message?: string }
  - acceptFriendRequest: { requestId: uuid }, declineFriendRequest: { requestId: uuid }
  - unfriend: { userId: member_id }, blockUser: { userId: member_id, reason?: string }
  - reportUser: { userId: member_id, reason?: string }
  - sendMessage: { chatId: uuid, text: string, isImage: bool }
  - markChatAsRead: { chatId: uuid }
  - checkIn: { locationId: int }, checkOut: {}

**Notes**

- Client still uses `id` in some routes today; BE should support lookups by either `id` or `member_id` during transition.
- All new writes/relationships should prefer `member_id` (uuid).
