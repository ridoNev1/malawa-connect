import 'package:permission_handler/permission_handler.dart';

class NotificationPermissionService {
  static bool _requested = false;

  static Future<bool> ensureRequestedOnce() async {
    if (_requested) {
      final status = await Permission.notification.status;
      return status.isGranted;
    }
    _requested = true;
    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) return true;
    if (status.isDenied || status.isRestricted) {
      final res = await Permission.notification.request();
      return res.isGranted || res.isLimited;
    }
    if (status.isPermanentlyDenied) {
      // Optionally open app settings
      return false;
    }
    return false;
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
