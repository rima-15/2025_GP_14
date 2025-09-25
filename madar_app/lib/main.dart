import 'package:flutter/material.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:madar_app/screens/welcome_page.dart';

void main() {
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
