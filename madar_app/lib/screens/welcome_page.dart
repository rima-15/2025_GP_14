import 'package:flutter/material.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/screens/signin_page.dart';
import 'package:madar_app/screens/signup_page.dart';
import 'package:madar_app/theme/theme.dart';

// ----------------------------------------------------------------------------
// Welcome Screen
// ----------------------------------------------------------------------------

/// Initial welcome screen with sign in/sign up options
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return CustomScaffold(
      showLogo: false,
      child: Column(
        children: [
          // ---------- Logo Section ----------
          Expanded(
            flex: 1,
            child: Center(
              child: Image.asset(
                'images/MadarLogoVersion2.png',
                height: isSmallScreen ? 70 : 90,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // ---------- Content Section ----------
          Expanded(
            flex: 1,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                isSmallScreen ? 24 : 30,
                AppSpacing.xxl,
                AppSpacing.xl + MediaQuery.of(context).padding.bottom,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppSpacing.sheetRadius),
                  topRight: Radius.circular(AppSpacing.sheetRadius),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Title
                    Text(
                      'Welcome!',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.pageTitle.copyWith(
                        fontSize: isSmallScreen ? 24 : 28,
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 6 : 8),

                    // Subtitle
                    Text(
                      'Find venues, meet friends, and explore with confidence!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: isSmallScreen ? 14 : 15,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 24 : 30),

                    // Sign In Button
                    SecondaryButton(
                      text: 'Sign in',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignInScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Sign Up Button
                    PrimaryButton(
                      text: 'Sign up',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignUpScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
