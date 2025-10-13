import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/welcome_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Load .env BEFORE anything reads dotenv.get(...)
  await dotenv.load(fileName: ".env");

  // 2) Init Firebase
  await Firebase.initializeApp();

  runApp(const MadarApp());
}

class MadarApp extends StatelessWidget {
  const MadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Madar',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: const WelcomeScreen(),
    );
  }
}

