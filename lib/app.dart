import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/theme.dart';
import 'core/app_bootstrap.dart';

class MalawaApp extends StatelessWidget {
  const MalawaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: AppBootstrap(
        child: MaterialApp.router(
          title: 'Malawa Connect',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
