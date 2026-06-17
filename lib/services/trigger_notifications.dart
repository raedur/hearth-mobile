import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _channelId = 'hearth_alerts';
const _channelName = 'Hearth Alerts';

/// Requests notification permission on Android 13+ and iOS.
/// Call this once after the user logs in.
Future<void> requestNotificationPermission() async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  // Android 13+
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  // iOS
  await plugin
      .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, sound: true);
}

/// Shows a local notification when a background trigger (geofence or WiFi)
/// fails because the session has expired and couldn't be refreshed.
/// Called from background isolates so must be self-contained.
Future<void> showTriggerAuthFailedNotification() async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await plugin.show(
    997,
    'Hearth',
    'A location trigger failed — open Hearth to reconnect.',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
        autoCancel: true,
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );
}
