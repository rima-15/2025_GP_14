import 'package:flutter/material.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/welcome_page.dart';
import 'package:madar_app/widgets/MainLayout.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:madar_app/api/seed_venues.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:madar_app/api/seed_venue_contacts.dart';
import 'services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:madar_app/screens/notifications_page.dart';

// ----------------------------------------------------------------------------
// Main Entry Point
// ----------------------------------------------------------------------------
// Related to Notification
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Initialize Firebase
  await Firebase.initializeApp();
  // Check if app opened from notification (terminated state)
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();

  //Notification
  await NotificationService.init();

  // DEV-ONLY: Run the venue seeder (controlled by DEV_SEED=true in .env)
  final devSeedRaw = dotenv.maybeGet('DEV_SEED');
  final doSeed = kDebugMode && (devSeedRaw?.toLowerCase() == 'true');

  if (doSeed) {
    final key = dotenv.env['GOOGLE_API_KEY'] ?? '';
    try {
      debugPrint('Running VenueSeeder...');
      await VenueSeeder(key).run();
      debugPrint('VenueSeeder finished.');
    } catch (e, st) {
      debugPrint('VenueSeeder error: $e\n$st');
    }
  }

  // DEV-ONLY: Backfill phone + website (controlled by DEV_SEED_CONTACTS=true)
  final devSeedContactsRaw = dotenv.maybeGet('DEV_SEED_CONTACTS');
  final doSeedContacts =
      kDebugMode && (devSeedContactsRaw?.toLowerCase() == 'true');

  if (doSeedContacts) {
    final key = dotenv.env['GOOGLE_API_KEY'] ?? '';
    try {
      debugPrint('Running VenueContactSeeder...');
      await VenueContactSeeder(
        key,
        onlyIfMissing: true,
        perCallDelayMs: 250,
      ).runOnceForCollection('venues');
      debugPrint('VenueContactSeeder finished.');
    } catch (e, st) {
      debugPrint('VenueContactSeeder error: $e\n$st');
    }
  }

  // Check user state
  final user = FirebaseAuth.instance.currentUser;

  Widget startScreen;

  if (user != null && user.emailVerified) {
    startScreen = const MainLayout();
  } else {
    startScreen = const WelcomeScreen();
  }

  runApp(MadarApp(startScreen: startScreen));
  // If app is opend from notification
  if (initialMessage != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const NotificationsPage()),
      );
    });
  }
}

// ----------------------------------------------------------------------------
// Root App Widget
// ----------------------------------------------------------------------------

class MadarApp extends StatelessWidget {
  final Widget startScreen;
  const MadarApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, //notification key
      title: 'Madar',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      // Remove overscroll glow effect globally
      scrollBehavior: NoGlowScrollBehavior(),
      home: startScreen,
    );
  }
}
