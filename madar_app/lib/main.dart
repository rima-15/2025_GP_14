import 'package:flutter/material.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/welcome_page.dart';
import 'package:madar_app/widgets/MainLayout.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Load environment variables
  await dotenv.load(fileName: ".env");

  // 2) Initialize Firebase
  await Firebase.initializeApp();

  final user = FirebaseAuth.instance.currentUser;

  Widget startScreen;
  if (user != null) {
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
