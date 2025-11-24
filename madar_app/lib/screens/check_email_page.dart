import 'dart:async';
import 'package:flutter/material.dart';
import 'package:madar_app/screens/signin_page.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:madar_app/widgets/app_widgets.dart';

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

  /// Sends a verification email to the current user
  Future<void> _resendVerificationEmail() async {
    try {
      setState(() {
        _sending = true;
      });

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

      // Start a 30-second cooldown after resending
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
      SnackbarHelper.showError(
        context,
        'Failed to resend verification email: $e',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showLogo: true,
      child: Column(
        children: [
          const Expanded(flex: 1, child: SizedBox(height: 10)),
          Expanded(
            flex: 7,
            child: Container(
              padding: const EdgeInsets.fromLTRB(25, 50, 25, 20),
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
                  const Icon(
                    Icons.email_outlined,
                    size: 90,
                    color: AppColors.kGreen,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Verify Email',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.kGreen,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'We have sent a verification email to:',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
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
                  const Text(
                    'Please verify your email before signing in.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const Spacer(),

                  // Resend Verification Email Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_sending || _sentRecently)
                          ? null
                          : _resendVerificationEmail,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.kGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
                          : const Icon(Icons.refresh, color: Colors.white),
                      label: Text(
                        _sending
                            ? 'Sending...'
                            : _sentRecently
                            ? 'Try again in $_countdown s'
                            : 'Resend Verification Email',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Go to Sign In Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.kGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignInScreen(),
                          ),
                        );
                      },
                      child: const Text('Go to Sign In'),
                    ),
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
