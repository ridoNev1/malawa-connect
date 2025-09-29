import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:malawa_connect/features/profile/presentation/profile_page.dart';
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
    GoRoute(path: '/profiles', builder: (_, __) => const ProfilePage()),
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
