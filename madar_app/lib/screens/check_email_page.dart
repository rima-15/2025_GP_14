import 'dart:async';
import 'package:flutter/material.dart';
import 'package:madar_app/screens/signin_page.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';

// ----------------------------------------------------------------------------
// Check Email Page
// ----------------------------------------------------------------------------

/// Page shown after sign up to prompt user to verify their email
class CheckEmailPage extends StatefulWidget {
  final String email;

  const CheckEmailPage({super.key, required this.email});

  @override
  State<CheckEmailPage> createState() => _CheckEmailPageState();
}

class _CheckEmailPageState extends State<CheckEmailPage> {
  bool _sending = false;
  bool _sentRecently = false;
  int _countdown = 0;
  Timer? _timer;

  // ---------- Resend Verification Email ----------

  Future<void> _resendVerificationEmail() async {
    try {
      setState(() => _sending = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        SnackbarHelper.showError(
          context,
          'Unable to resend. Please sign up again or sign in first.',
        );
        setState(() => _sending = false);
        return;
      }

      await user.sendEmailVerification();

      SnackbarHelper.showSuccess(
        context,
        'Verification email has been resent.',
      );

      // Start a 60-second cooldown after resending
      setState(() {
        _sentRecently = true;
        _countdown = 60;
      });

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_countdown > 1) {
          setState(() => _countdown--);
        } else {
          timer.cancel();
          setState(() {
            _sentRecently = false;
            _countdown = 0;
          });
        }
      });
    } catch (e) {
      String message = e.toString();

      if (message.contains("too-many-requests")) {
        SnackbarHelper.showError(
          context,
          "You've requested too many verification emails. Please wait a minute before trying again.",
        );
      } else {
        SnackbarHelper.showError(
          context,
          "Failed to resend verification email. Please try again shortly.",
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    // Clear any lingering snackbars when leaving the page
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }
    _timer?.cancel();
    super.dispose();
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return CustomScaffold(
      showLogo: true,
      child: Column(
        children: [
          Expanded(flex: 1, child: SizedBox(height: isSmallScreen ? 5 : 10)),
          Expanded(
            flex: 7,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                isSmallScreen ? 40 : 50,
                AppSpacing.xxl,
                AppSpacing.xl + bottomSafeArea,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Email Icon
                  Icon(
                    Icons.email_outlined,
                    size: isSmallScreen ? 70 : 90,
                    color: AppColors.kGreen,
                  ),
                  SizedBox(height: isSmallScreen ? 18 : 24),

                  // Title
                  Text('Verify Email', style: AppTextStyles.pageTitle),
                  const SizedBox(height: 16),

                  // Description
                  const Text(
                    'We have sent a verification email to:',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),

                  // Email Address
                  Text(
                    widget.email,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Instruction Text
                  const Text(
                    'Please verify your email before signing in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const Spacer(),

                  // Resend Verification Email Button
                  SizedBox(
                    width: double.infinity,
                    height: 50, // Fixed height to prevent jumping
                    child: ElevatedButton.icon(
                      onPressed: (_sending || _sentRecently)
                          ? null
                          : _resendVerificationEmail,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.kGreen,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.buttonRadius,
                          ),
                        ),
                        // Gray when loading or disabled (original behavior)
                        disabledBackgroundColor: Colors.grey[300],
                        disabledForegroundColor: Colors.grey[600],
                      ),
                      icon: _sending
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              Icons.refresh,
                              color: _sentRecently
                                  ? Colors.grey[600]
                                  : Colors.white,
                            ),
                      label: Text(
                        _sending
                            ? 'Sending...'
                            : _sentRecently
                            ? 'Try again in $_countdown s'
                            : 'Resend Verification Email',
                        style: TextStyle(
                          color: _sentRecently
                              ? Colors.grey[600]
                              : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Go to Sign In Button
                  PrimaryButton(
                    text: 'Go to Sign In',
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignInScreen(),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
