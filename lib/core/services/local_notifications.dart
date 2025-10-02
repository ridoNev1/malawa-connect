import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOSInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iOSInit);
    await _plugin.initialize(initSettings);

    // Create a default channel on Android
    const androidChannel = AndroidNotificationChannel(
      'default_channel',
      'General Notifications',
      description: 'Default channel for in-app notifications',
      importance: Importance.defaultImportance,
    );
    await _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  static Future<void> show({
    int id = 0,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'default_channel',
      'General Notifications',
      channelDescription: 'Default channel for in-app notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iOSDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iOSDetails);
    await _plugin.show(id, title, body, details);
  }
}

