import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GpsTrackingService
//
// Runs a foreground service that reads GPS every 5 minutes and writes
// location.gpsLat, location.gpsLng, location.gpsUpdatedAt to the current
// user's Firestore document.
//
// Lifecycle:
//   - Call GpsTrackingService.initialize() once in main()
//   - Call GpsTrackingService.start()    when active tracking requests exist
//   - Call GpsTrackingService.stop()     when no active tracking requests exist
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> gpsServiceOnStart(
  ServiceInstance service,
) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();

  debugPrint(
    '[GPS-SERVICE] Background isolate started',
  );

  service.on('stop').listen((_) {
    service.stopSelf();
    debugPrint(
      '[GPS-SERVICE] Stop command received',
    );
  });

  if (service
      is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  await GpsTrackingService.uploadGps();

  Timer.periodic(
    const Duration(minutes: 5),
    (_) async {
      try {
        debugPrint(
          '[GPS-SERVICE] periodic tick',
        );
        await GpsTrackingService.uploadGps();
      } catch (e) {
        debugPrint(
          '[GPS-SERVICE] periodic error: $e',
        );
      }
    },
  );
}

@pragma('vm:entry-point')
Future<bool> gpsServiceOnIosBackground(
  ServiceInstance service,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

class GpsTrackingService {
  static const int _intervalMinutes = 5;

  static Future<void>
  initialize() async {
    final service =
        FlutterBackgroundService();

    await service.configure(
      androidConfiguration:
          AndroidConfiguration(
            onStart: gpsServiceOnStart,
            autoStart: false,
            isForegroundMode: true,
            notificationChannelId:
                'madar_gps_channel',
            initialNotificationTitle:
                'Madar',
            initialNotificationContent:
                'Tracking venue presence...',
            foregroundServiceNotificationId:
                888,
            foregroundServiceTypes: [
              AndroidForegroundType
                  .location,
            ],
          ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: gpsServiceOnStart,
        onBackground:
            gpsServiceOnIosBackground,
      ),
    );
  }

  static Future<void> start() async {
    try {
      debugPrint(
        '[GPS-SERVICE] start() entered',
      );

      final service =
          FlutterBackgroundService();
      final isRunning = await service
          .isRunning();
      debugPrint(
        '[GPS-SERVICE] isRunning before start = $isRunning',
      );

      if (isRunning) {
        debugPrint(
          '[GPS-SERVICE] already running -> skip',
        );
        return;
      }

      var permission =
          await Geolocator.checkPermission();
      debugPrint(
        '[GPS-SERVICE] permission before request = $permission',
      );

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
        debugPrint(
          '[GPS-SERVICE] permission after request = $permission',
        );
      }

      if (permission ==
          LocationPermission
              .deniedForever) {
        debugPrint(
          '[GPS-SERVICE] deniedForever -> cannot start',
        );
        return;
      }

      if (permission ==
          LocationPermission.denied) {
        debugPrint(
          '[GPS-SERVICE] still denied -> cannot start',
        );
        return;
      }

      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();
      debugPrint(
        '[GPS-SERVICE] location service enabled = $serviceEnabled',
      );

      if (!serviceEnabled) {
        debugPrint(
          '[GPS-SERVICE] location service disabled -> cannot start',
        );
        return;
      }

      debugPrint(
        '[GPS-SERVICE] calling startService()...',
      );
      await service.startService();
      debugPrint(
        '[GPS-SERVICE] Started',
      );
    } catch (e, st) {
      debugPrint(
        '[GPS-SERVICE] start() ERROR: $e',
      );
      debugPrint('$st');
    }
  }

  static Future<void> stop() async {
    final service =
        FlutterBackgroundService();
    final isRunning = await service
        .isRunning();

    if (isRunning) {
      service.invoke('stop');
      debugPrint(
        '[GPS-SERVICE] Stopped',
      );
    }
  }

  static Future<bool>
  isRunning() async {
    return FlutterBackgroundService()
        .isRunning();
  }

  static Future<void>
  uploadGps() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();
      final userDocId = prefs.getString(
        'gps_user_doc_id',
      );

      if (userDocId == null ||
          userDocId.isEmpty) {
        debugPrint(
          '[GPS-SERVICE] No user docId found — skipping upload',
        );
        return;
      }

      final permission =
          await Geolocator.checkPermission();
      if (permission ==
              LocationPermission
                  .denied ||
          permission ==
              LocationPermission
                  .deniedForever) {
        debugPrint(
          '[GPS-SERVICE] Location permission denied — skipping',
        );
        return;
      }

      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint(
          '[GPS-SERVICE] Location service disabled — skipping',
        );
        return;
      }

      final position =
          await Geolocator.getCurrentPosition(
            desiredAccuracy:
                LocationAccuracy.high,
            timeLimit: const Duration(
              seconds: 15,
            ),
          );

      debugPrint(
        '[GPS-SERVICE] Got position: ${position.latitude}, ${position.longitude}',
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .update({
            'location.gpsLat':
                position.latitude,
            'location.gpsLng':
                position.longitude,
            'location.gpsUpdatedAt':
                FieldValue.serverTimestamp(),
          });

      debugPrint(
        '[GPS-SERVICE] ✅ Uploaded GPS for $userDocId: '
        '${position.latitude}, ${position.longitude}',
      );
    } catch (e) {
      debugPrint(
        '[GPS-SERVICE] ❌ Error uploading GPS: $e',
      );
    }
  }
}
