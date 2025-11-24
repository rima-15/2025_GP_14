import 'package:flutter/material.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/welcome_page.dart';
import 'package:madar_app/widgets/MainLayout.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:madar_app/api/seed_venues.dart'; // to save venue info in database
import 'package:flutter/foundation.dart'
    show kDebugMode; // for debug-only logic

// NEW: contacts backfiller (adds venuePhone + venueWebsite via Places Details)
import 'package:madar_app/api/seed_venue_contacts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Load environment variables
  await dotenv.load(fileName: ".env");

  // 2) Initialize Firebase
  await Firebase.initializeApp();

  // 3) DEV-ONLY AUTO LOGIN (anonymous)
  /* final enableDevAutoLogin =
      kDebugMode &&
      (dotenv.maybeGet('DEV_AUTO_LOGIN')?.toLowerCase() == 'true');

  if (enableDevAutoLogin && FirebaseAuth.instance.currentUser == null) {
    try {
      await FirebaseAuth.instance.signInAnonymously();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', true);
    } catch (e) {
      debugPrint('Anonymous sign-in failed: $e');
    }
  }*/

  // 4) Run the venue seeder (debug only, guarded by .env flag)
  final devSeedRaw = dotenv.maybeGet('DEV_SEED');
  debugPrint('DEV_SEED raw: "$devSeedRaw"  kDebugMode=$kDebugMode');
  final doSeed = kDebugMode && (devSeedRaw?.toLowerCase() == 'true');
  debugPrint('Will run seeder? $doSeed');

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

  // NEW: Backfill phone + website ONLY (safe merge). Controlled by DEV_SEED_CONTACTS=true
  final devSeedContactsRaw = dotenv.maybeGet('DEV_SEED_CONTACTS');
  debugPrint(
    'DEV_SEED_CONTACTS raw: "$devSeedContactsRaw"  kDebugMode=$kDebugMode',
  );
  final doSeedContacts =
      kDebugMode && (devSeedContactsRaw?.toLowerCase() == 'true');

  if (doSeedContacts) {
    final key = dotenv.env['GOOGLE_API_KEY'] ?? '';
    try {
      debugPrint('Running VenueContactSeeder (onlyIfMissing=true)…');
      // onlyIfMissing=true ensures we don’t overwrite existing values
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

  // ✅ تحقق من حالة المستخدم و "Remember Me"
  final prefs = await SharedPreferences.getInstance();
  final remember = prefs.getBool('remember_me') ?? false;
  final user = FirebaseAuth.instance.currentUser;

  Widget startScreen;

  if (user != null && user.emailVerified) {
    startScreen = const MainLayout();
  } else {
    startScreen = const WelcomeScreen();
  }

  runApp(MadarApp(startScreen: startScreen));
}

class MadarApp extends StatelessWidget {
  final Widget startScreen;
  const MadarApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Madar',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: startScreen,
    );
  }
}
