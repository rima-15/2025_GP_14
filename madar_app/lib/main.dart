import 'package:flutter/material.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/welcome_page.dart';
import 'package:madar_app/widgets/MainLayout.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:madar_app/dev/seed_venues.dart'; // to save venue info in database
import 'package:flutter/foundation.dart'
    show kDebugMode; // for debug-only logic

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Load .env BEFORE anything reads dotenv.get(...)
  await dotenv.load(fileName: ".env");

  // 2) Init Firebase
  await Firebase.initializeApp();

  // 3) DEV-ONLY AUTO LOGIN (anonymous)
  final enableDevAutoLogin =
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
  }

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

  // ✅ تحقق من حالة المستخدم و "Remember Me"
  final prefs = await SharedPreferences.getInstance();
  final remember = prefs.getBool('remember_me') ?? false;
  final user = FirebaseAuth.instance.currentUser;

  // نحدد الصفحة اللي يبدأ منها التطبيق
  Widget startScreen;
  if (remember && user != null) {
    // المستخدم مفعّل "Remember Me" وموجود في Firebase
    startScreen = const MainLayout();
  } else {
    // المستخدم مو مفعّل remember أو ما سجّل دخول
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
