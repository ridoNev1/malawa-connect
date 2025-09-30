# Features Summary (Mock API Integrated)

This document lists all features currently implemented in the app, how they fetch/state from the centralized mock API, and important behavior notes for testing.

**Core Infrastructure**
- Centralized mock source: `lib/core/services/mock_api.dart`
  - Current user (with `id`, `member_id`, and `location_id`), members, locations (lat/lng + geofence_radius_m), presence, discounts, chat list/messages, notifications.
  - GET support with filter/search/pagination. Actions print payloads and mutate in-memory mock state.
- Routing: `lib/core/router/app_router.dart` with routes for home, connect, chat list, chat room, profile (edit/view), notifications.
- Riverpod v3 providers: Notifier/NotifierProvider usage, with `autoDispose` where page reset is expected.

**Auth**
- OTP via Supabase: request/verify. Providers: `lib/features/auth/providers.dart`.
- On successful session, app navigates to home.

**Home**
- Header shows full name (from `currentUser.full_name`) and unread notifications count (from `notificationsProvider`).
- Membership card: shows membership tier from points, points, and join date (from `currentUser.created_at`).
- Discounts carousel: data from `MockApi.getDiscounts()` via `discountsProvider`.
- Presence card: shows cafe name and live duration from `presenceProvider`.
- Geofencing
  - Services: `LocationService` (geolocator), `geofenceWatcherProvider`, `presenceControllerProvider`.
  - Auto check-in when inside a location geofence, heartbeat every 60s, auto check-out when leaving radius.
  - iOS/Android permissions already configured.

**Connect**
- Members list via `membersProvider` (MockApi.getMembers with `MembersQuery`).
- Features: tabs (nearest/network), filters (Semua/Friends/Partners/Online), search (debounced), pagination (load more on scroll), stats (Online/Member/Nearby) from provider state.
- Blocked filtering: members excluded if blocked via profile action.
- Reset on navigation: provider `autoDispose` ensures fresh state after you leave and return.
- Nearest filter: if presence active, uses `presence.location_id`; otherwise uses `currentUser.location_id`.

**Profile**
- Current user: `profileProvider.loadUserData()` consumes `MockApi.getCurrentUser()`.
- Other user view: `profileProvider.loadUserDataById(userId)` consumes `MockApi.getMemberById()`.
- Actions
  - Save: `MockApi.updateProfile(userId: member_id, payload)`.
  - Block/Report: `MockApi.blockUser()`, `MockApi.reportUser()`.
- Online indicator
  - Current user: `presenceProvider` → “Online di <location>” or “Offline”.
  - Other user: `memberByIdProvider(userId)` → Online/Last seen.
- Gallery
  - Full-screen gallery renders actual `profile.galleryImages` (URL or base64); removed static picsum.

**Chat**
- Chat list: `chatListProvider.loadChatRooms()` → `MockApi.getChatList()`.
- Room header: tappable; opens the profile of the other user (`/profile/view/:id`).
- Messages: `chatRoomProviderFamily(chatRoom).loadMessages()` → `MockApi.getChatMessages(chatId)`.
- Send text/image: `MockApi.sendMessage(chatId, text, isImage)`; list lastMessage updates; unread counts handled.
- Pagination: on scroll-to-top, prepends older mock messages a few times.
- Mark read: `chatListProvider.markAsRead(chatId)` → `MockApi.markChatAsRead`.
- Blocked users: chat list hides blocked; message button from profile disabled for blocked targets.

**Notifications**
- Page uses `notificationsProvider` and MockApi for list + actions.
- Actions: accept/decline connection requests mutate the list; mark-all marks all as read.
- Home header badge shows live unread count.
- Notification permission (Android 13+/iOS) requested once on Home (ready for future push integration).

**Discounts**
- Carousel reads from `MockApi.getDiscounts()`; image is optional.

**Locations & Presence**
- Locations have `lat`, `lng`, `geofence_radius_m` for auto check-in/out.
- Presence object includes `check_in_time` and `last_heartbeat_at`.
- Base location for nearest filter: `presence.location_id` if active else `currentUser.location_id`.

**Blocking**
- `MockApi.blockUser({userId})` adds both legacy `id` and `member_id` to an in-memory blocklist.
- `getMembers`/`getChatList` exclude blocked entities.

**Debounced Search**
- Connect search: 350ms debounce.
- Chat list search: 300ms debounce.

**Permissions**
- Location: Android manifest + iOS Info.plist keys in place.
- Notifications: Android POST_NOTIFICATIONS + runtime request; iOS runtime request.

**No Remaining Static UI Data**
- All sample content now flows from `MockApi` and providers:
  - Members, Chats, Messages, Profile, Discounts, Presence, Notifications.
  - Removed picsum/static arrays in widgets; image seeds only exist inside MockApi data.

**Testing Checklist**
- Home: Name, unread badge, membership, discounts, presence duration update; notification tap opens list.
- Connect: Reset after navigation; filters, search, pagination, stats update; blocks hide users.
- Profile: Online indicator, gallery full-screen; block/report actions; message to open chat.
- Chat: Header tap → profile; send text/image; pagination on top; unread resets.
- Notifications: Pull to refresh; accept/decline; mark-all; badge updates on Home.

**Key Files**
- MockApi: `lib/core/services/mock_api.dart`
- Connect: `lib/features/connect/providers/members_provider.dart`, `.../presentation/connect_page.dart`
- Chat: `lib/features/chat/providers/*`, `.../presentation/chat_*`
- Profile: `lib/features/profile/providers/profile_provider.dart`, `.../widgets/*`, `.../presentation/*`
- Home: `lib/features/home/presentation/home_page.dart`, `.../providers/*`, `lib/shared/widgets/header_section.dart`
- Notifications: `lib/features/notifications/providers/*`, `.../presentation/notification_page.dart`
- Location: `lib/core/services/location_service.dart`, `lib/features/home/providers/geofence_watcher.dart`
