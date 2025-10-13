// lib/widgets/custom_scaffold.dart
import 'package:flutter/material.dart';

const kGreen = Color(0xFF787E65);

class CustomScaffold
    extends StatelessWidget {
  final Widget? child;
  final bool showLogo;
  final String logoPath;

  const CustomScaffold({
    super.key,
    this.child,
    this.showLogo = false,
    this.logoPath =
        'images/MadarLogoVersion2.png',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kGreen,
      appBar: AppBar(
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        backgroundColor:
            Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Column(
          children: [
            if (showLogo) ...[
              const SizedBox(
                height: 16,
              ),
              Image.asset(
                logoPath,
                height: 90,
                fit: BoxFit.contain,
              ),
              const SizedBox(
                height: 12,
              ),
            ],
            Expanded(
              child:
                  child ??
                  const SizedBox(),
            ),
          ],
        ),
      ),
    );
  }
}
