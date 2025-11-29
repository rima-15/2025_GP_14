import 'package:flutter/material.dart';
import 'package:madar_app/theme/theme.dart';

// ----------------------------------------------------------------------------
// Custom Scaffold
// ----------------------------------------------------------------------------

/// Custom scaffold with green background used for auth screens
/// Shows optional logo at top and wraps content in SafeArea
class CustomScaffold extends StatelessWidget {
  final Widget? child;
  final bool showLogo;
  final String logoPath;

  const CustomScaffold({
    super.key,
    this.child,
    this.showLogo = false,
    this.logoPath = 'images/MadarLogoVersion2.png',
  });

  @override
  Widget build(BuildContext context) {
    // Responsive logo height based on screen size
    final screenHeight = MediaQuery.of(context).size.height;
    final logoHeight = screenHeight < 700 ? 70.0 : 90.0;
    final logoTopPadding = screenHeight < 700 ? 12.0 : 16.0;
    final logoBottomPadding = screenHeight < 700 ? 8.0 : 12.0;

    // Get bottom safe area padding for nav bar
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: kGreen,
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // White background that covers the bottom safe area
          // This ensures no green shows below the white content
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: bottomSafeArea + 100, // Extra height to be safe
            child: Container(color: Colors.white),
          ),
          // Main content
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (showLogo) ...[
                  SizedBox(height: logoTopPadding),
                  Image.asset(
                    logoPath,
                    height: logoHeight,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(height: logoBottomPadding),
                ],
                Expanded(child: child ?? const SizedBox()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
