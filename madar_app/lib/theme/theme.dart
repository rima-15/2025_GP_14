import 'package:flutter/material.dart';

// ----------------------------------------------------------------------------
// App Colors
// ----------------------------------------------------------------------------
const kGreen = Color(0xFF787E65);
const kBg = Color.fromARGB(255, 255, 255, 255);

// ----------------------------------------------------------------------------
// Custom Scroll Behavior - Removes overscroll glow effect
// ----------------------------------------------------------------------------

/// Custom scroll behavior that removes the purple/blue glow effect
/// when scrolling past the bounds of a scrollable widget.
class NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Return child without any overscroll indicator (no glow)
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // Use clamping physics for a clean, no-bounce effect
    return const ClampingScrollPhysics();
  }
}

// ----------------------------------------------------------------------------
// Responsive Utilities
// ----------------------------------------------------------------------------

/// Returns responsive value based on screen width
/// Does NOT change your design - just adapts spacing/sizing for different screens
class Responsive {
  static double screenWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  /// Returns true if screen is considered small (< 360dp)
  static bool isSmallScreen(BuildContext context) => screenWidth(context) < 360;

  /// Returns true if screen is considered large (> 600dp)
  static bool isLargeScreen(BuildContext context) => screenWidth(context) > 600;

  /// Responsive horizontal padding (16 on small, 24 on normal, 32 on large)
  static double horizontalPadding(BuildContext context) {
    final width = screenWidth(context);
    if (width < 360) return 16.0;
    if (width > 600) return 32.0;
    return 24.0;
  }

  /// Responsive value that scales with screen width
  /// baseValue is the design value for a 375dp screen
  static double value(BuildContext context, double baseValue) {
    final width = screenWidth(context);
    final scale = (width / 375).clamp(0.85, 1.2);
    return baseValue * scale;
  }

  /// Responsive font size (keeps visual hierarchy, just adjusts for screen)
  static double fontSize(BuildContext context, double baseSize) {
    final width = screenWidth(context);
    if (width < 360) return baseSize * 0.9;
    if (width > 600) return baseSize * 1.1;
    return baseSize;
  }
}

// ----------------------------------------------------------------------------
// Consistent Spacing Constants
// ----------------------------------------------------------------------------
class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;

  // Standard page padding
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: 24.0);
  static const EdgeInsets pageVerticalPadding = EdgeInsets.symmetric(
    vertical: 20.0,
  );

  // Form field spacing
  static const double fieldSpacing = 20.0;
  static const double sectionSpacing = 32.0;

  // Button vertical padding
  static const double buttonVerticalPadding = 14.0;

  // Border radius
  static const double buttonRadius = 10.0;
  static const double cardRadius = 12.0;
  static const double containerRadius = 16.0;
  static const double sheetRadius = 35.0;
}

// ----------------------------------------------------------------------------
// Consistent Text Styles
// ----------------------------------------------------------------------------
class AppTextStyles {
  // Page titles (Welcome!, Get Started, etc.)
  static const TextStyle pageTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: kGreen,
  );

  // Large page titles
  static const TextStyle largeTitles = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w900,
    color: kGreen,
  );

  // Section headers
  static const TextStyle sectionHeader = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Color(0xFF9E9E9E),
    letterSpacing: 0.5,
  );

  // App bar titles
  static const TextStyle appBarTitle = TextStyle(
    color: kGreen,
    fontWeight: FontWeight.w600,
    fontSize: 18,
  );

  // Body text
  static const TextStyle body = TextStyle(
    fontSize: 15,
    color: Colors.black87,
    height: 1.5,
  );

  // Body text secondary
  static TextStyle bodySecondary = TextStyle(
    fontSize: 15,
    color: Colors.grey[700],
    height: 1.4,
  );

  // Button text
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );

  // Link text
  static const TextStyle link = TextStyle(
    fontWeight: FontWeight.bold,
    color: kGreen,
  );

  // Caption/helper text
  static TextStyle caption = TextStyle(fontSize: 13, color: Colors.grey[600]);

  // Error text
  static const TextStyle error = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: Color(0xFFC62828),
  );
}

// ----------------------------------------------------------------------------
// Theme Builder
// ----------------------------------------------------------------------------
ThemeData buildAppTheme() {
  final base = ThemeData.light();
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: base.colorScheme.copyWith(primary: kGreen, secondary: kGreen),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      foregroundColor: Colors.black87,
      titleTextStyle: AppTextStyles.appBarTitle,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.buttonVerticalPadding,
          horizontal: AppSpacing.lg,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        ),
        textStyle: AppTextStyles.button,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: kGreen, width: 2),
        foregroundColor: kGreen,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.buttonVerticalPadding,
          horizontal: AppSpacing.lg,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        ),
        textStyle: AppTextStyles.button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kGreen),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        borderSide: const BorderSide(color: kGreen, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        borderSide: const BorderSide(color: Color(0xFFC62828)),
      ),
      hintStyle: const TextStyle(color: Colors.black26),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}
