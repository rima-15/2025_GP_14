import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:madar_app/screens/notifications_page.dart';
import '../main.dart'; //  navigatorKey

class NotificationService {
  static final _fcm = FirebaseMessaging.instance;
  static final _local = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // Permission
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // ANDROID CHANNEL (THIS IS THE FIX)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'madar_channel', //AndroidManifest
      'Madar Notifications',
      description: 'All Madar notifications',
      importance: Importance.max,
      playSound: true,
    );

    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // Local notification init
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        _goToNotificationsPage();
      },
    );

    FirebaseMessaging.onMessage.listen((message) {
      _showLocalNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _goToNotificationsPage();
    });
  }

  static void _goToNotificationsPage() {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NotificationsPage()),
    );
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    const androidDetails = AndroidNotificationDetails(
      'madar_channel',
      'Madar Notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      message.notification?.title,
      message.notification?.body,
      details,
      payload: message.data['type'],
    );
  }

  static Future<void> clearAllSystemNotifications() async {
    await _local.cancelAll();
  }
}
