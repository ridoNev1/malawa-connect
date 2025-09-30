# Lib Directory Overview

This document summarizes the structure and responsibilities of the `lib/` folder for Malawa Connect. It focuses on the layers, shared infrastructure, and feature modules that collaborate around the centralized mock API described in the project documentation.

## Application Entry Points

- `lib/main.dart` initializes Flutter bindings, loads environment variables via `flutter_dotenv`, prepares the Supabase client, and boots the widget tree with `MalawaApp`.
- `lib/app.dart` wraps the app in a global `ProviderScope` (Riverpod v3) and configures a `MaterialApp.router` that uses the shared theme and GoRouter instance.

## Core Layer

- `lib/core/router/app_router.dart` declares the global `GoRouter` with routes for auth, home, connect, chat, notifications, and profile flows. It also contains a lightweight decision page that redirects based on the Supabase session state.
- `lib/core/services/mock_api.dart` exposes an in-memory backend used throughout the app. It stores canonical data for the current user, members, locations, discounts, chats, presence, and notifications, and offers read/write helpers that mimic the target backend contract.
- `lib/core/services/location_service.dart` centralizes geolocation access for geofencing logic, while `lib/core/services/notification_permission_service.dart` and `lib/core/services/supabase_client.dart` provide platform integrations for notifications and Supabase respectively.
- `lib/core/theme/theme.dart` defines the shared color palette, typography, and component themes that are reused by all feature screens.
- `lib/core/config` contains configuration primitives (e.g., constants) that can be injected into features without duplicating magic numbers.

## Shared Widgets

- `lib/shared/widgets` hosts reusable UI components such as headers, cards, buttons, and list items that appear across multiple feature flows. These widgets are designed to consume Riverpod-provided data and theming from the core layer to keep feature widgets lean.

## Feature Modules

Each folder under `lib/features` owns a vertical slice: presentation widgets, state providers, and any feature-specific models.

- **Auth (`lib/features/auth`)**: Screens for login and OTP verification drive Supabase-based authentication before handing off to the home experience.
- **Home (`lib/features/home`)**: Providers aggregate current user, membership, discounts, presence, and notification badge information. Presentation code renders the dashboard, membership card, and live presence duration, and wires geofence triggers through the presence controller.
- **Connect (`lib/features/connect`)**: `MembersNotifier` orchestrates tab switching, filters, debounced search, pagination, and derived statistics for the member directory. UI widgets render nearest/network tabs, filter chips, and list items that respond to provider state.
- **Profile (`lib/features/profile`)**: Providers fetch either the current user or another member, expose actions for updating profile data, blocking, and reporting, and drive gallery/online indicator widgets for both edit and view modes.
- **Chat (`lib/features/chat`)**: Chat list and room providers fetch paginated messages, mark conversations as read, and relay send-message actions back to the mock API. Presentation files compose the chat list, room timeline, and message composer widgets while honoring online presence metadata.
- **Notifications (`lib/features/notifications`)**: Riverpod state manages notification fetching, pull-to-refresh, mark-all, and connection request actions. Pages render grouped cards and update the global unread badge that surfaces on the home header.

## Relationship to Mock Documentation

The structures above align with the feature rundown in `features_summary.md` and the data contracts in `moc_fe.md`. Each module relies on the shared `MockApi` to follow the canonical schema for members, presence, chats, notifications, and discounts while the UI mirrors the workflows called out in the summary document.
