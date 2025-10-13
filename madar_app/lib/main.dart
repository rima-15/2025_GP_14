import 'package:flutter/material.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/welcome_page.dart';
import 'package:madar_app/widgets/MainLayout.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Load .env BEFORE anything reads dotenv.get(...)
  await dotenv.load(fileName: ".env");

  // 2) Init Firebase
  await Firebase.initializeApp();

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
