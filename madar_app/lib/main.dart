import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/welcome_page.dart';
import 'package:madar_app/widgets/MainLayout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables first (safe to ignore if .env is missing)
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {}

  // Firebase init
  await Firebase.initializeApp();

  // Remember-me + auth check
  final prefs = await SharedPreferences.getInstance();
  final remember = prefs.getBool('remember_me') ?? false;
  final user = FirebaseAuth.instance.currentUser;

  final Widget startScreen = (remember && user != null)
      ? const MainLayout()
      : const WelcomeScreen();

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
