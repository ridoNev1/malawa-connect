import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/connect/providers/inapp_presence_provider.dart';

class AppBootstrap extends ConsumerWidget {
  final Widget child;
  const AppBootstrap({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch in-app presence globally so heartbeat/broadcast is always active while app runs
    ref.watch(inAppPresenceProvider);
    return child;
  }
}

