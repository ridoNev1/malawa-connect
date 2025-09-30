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
  initialLocation: '/decide',
  routes: [
    GoRoute(path: '/decide', builder: (_, __) => const _DecidePage()),
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
    // Update chat routes
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

class _DecidePage extends StatelessWidget {
  const _DecidePage();
  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    Future.microtask(() {
      if (session == null) {
        context.go('/login');
      } else {
        context.go('/');
      }
    });
    return const Scaffold(body: SizedBox.shrink());
  }
}
