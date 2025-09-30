import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/notification_permission_service.dart';

final notificationPermissionProvider = FutureProvider<bool>((ref) async {
  return await NotificationPermissionService.ensureRequestedOnce();
});

