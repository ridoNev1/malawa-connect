import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:malawa_connect/features/chat/presentation/chat_list_page.dart';
import 'package:malawa_connect/features/chat/presentation/chat_room_page.dart';
import 'package:malawa_connect/features/connect/presentation/connect_page.dart';
import 'package:malawa_connect/features/notifications/presentation/notification_page.dart';
import 'package:malawa_connect/features/profile/presentation/profile_page.dart';
import 'package:malawa_connect/features/profile/presentation/profile_view_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/otp_page.dart';
import '../../features/home/presentation/home_page.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  // React to auth changes
  refreshListenable:
      _GoRouterRefreshStream(Supabase.instance.client.auth.onAuthStateChange),
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final loggingIn = state.matchedLocation == '/login';
    final onOtp = state.matchedLocation == '/otp';

    if (session == null) {
      // Allow login and otp (otp requires phone param)
      if (loggingIn) return null;
      if (onOtp) {
        final phone = state.uri.queryParameters['phone'];
        return (phone == null || phone.isEmpty) ? '/login' : null;
      }
      return '/login';
    }

    // If logged in, prevent going back to login/otp
    if (loggingIn || onOtp) return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
    GoRoute(
      path: '/otp',
      builder: (_, state) {
        final phone = state.uri.queryParameters['phone'] ?? '';
        return OtpPage(phone: phone);
      },
    ),
    GoRoute(path: '/', builder: (_, __) => const HomePage()),
    GoRoute(
      path: '/profiles',
      builder: (context, state) => const ProfilePage(),
    ),
    GoRoute(
      path: '/profile/view/:userId',
      builder: (context, state) {
        final userId = state.pathParameters['userId']!;
        return ProfileViewPage(userId: userId);
      },
    ),
    GoRoute(path: '/connect', builder: (context, state) => const ConnectPage()),
    GoRoute(path: '/chat', builder: (context, state) => const ChatListPage()),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationPage(),
    ),
    GoRoute(
      path: '/chat/room/:chatId',
      builder: (context, state) {
        final chatId = state.pathParameters['chatId'] ?? '';
        return ChatRoomPage(chatId: chatId);
      },
    ),
  ],
);

// Local refresh listenable for a Stream to work with GoRouter versions
// that don't export GoRouterRefreshStream.
class _GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
