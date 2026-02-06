import 'package:flutter/material.dart';
import 'package:madar_app/services/fcm_token_service.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:madar_app/screens/signup_page.dart';
import 'package:madar_app/screens/forgot_password_page.dart';
import 'package:madar_app/widgets/MainLayout.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'check_email_page.dart';

// ----------------------------------------------------------------------------
// Sign In Screen
// ----------------------------------------------------------------------------

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formSignInKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  // ---------- Sign In Logic ----------

  Future<void> _signIn() async {
    if (!_formSignInKey.currentState!.validate()) {
      // Focus the first invalid field
      if (_emailCtrl.text.isEmpty ||
          !_emailCtrl.text.contains('@') ||
          !_emailCtrl.text.contains('.')) {
        _emailFocus.requestFocus();
      } else if (_passCtrl.text.isEmpty) {
        _passFocus.requestFocus();
      }
      return;
    }

    setState(() => _loading = true);

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      User user = cred.user!;

      await user.reload();
      user = FirebaseAuth.instance.currentUser!;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final strictVerified =
          (userDoc.data()?['emailVerifiedStrict'] as bool?) ?? false;

      if (!user.emailVerified || !strictVerified) {
        SnackbarHelper.showError(
          context,
          'Your email isn\'t verified. Please check your email first.',
        );

        await Future.delayed(const Duration(seconds: 4));

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => CheckEmailPage(email: _emailCtrl.text.trim()),
            ),
          );
        }

        setState(() => _loading = false);
        return;
      }
      //FCM token
      await FcmTokenService.saveToken(user.uid);

      if (mounted) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainLayout()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          msg = 'Email or password is incorrect';
          break;
        case 'invalid-email':
          msg = 'Invalid email address';
          break;
        case 'user-disabled':
          msg = 'This account is disabled';
          break;
        case 'too-many-requests':
          msg = 'Too many attempts, please try again later';
          break;
        default:
          msg = 'Login error: ${e.message}';
      }
      SnackbarHelper.showError(context, msg);
    } catch (e) {
      SnackbarHelper.showError(context, 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                  topLeft: Radius.circular(AppSpacing.sheetRadius),
                  topRight: Radius.circular(AppSpacing.sheetRadius),
                ),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _formSignInKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Title
                      Text('Welcome back', style: AppTextStyles.largeTitles),
                      SizedBox(height: isSmallScreen ? 30 : 40),

                      // Email Field
                      StyledTextField(
                        controller: _emailCtrl,
                        focusNode: _emailFocus,
                        label: 'Email',
                        hint: 'Enter Email',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please enter email';
                          }
                          if (!v.contains('@') || !v.contains('.')) {
                            return 'Invalid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 25),

                      // Password Field
                      StyledTextField(
                        controller: _passCtrl,
                        focusNode: _passFocus,
                        label: 'Password',
                        hint: 'Enter Password',
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () => setState(() {
                            _obscurePassword = !_obscurePassword;
                          }),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please enter password';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 25),

                      // Forgot Password Link
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'Forget password?',
                            style: AppTextStyles.link,
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),

                      // Sign In Button
                      PrimaryButton(
                        text: 'Sign in',
                        onPressed: _signIn,
                        isLoading: _loading,
                      ),
                      const SizedBox(height: 25),

                      // Sign Up Link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Don\'t have an account? ',
                            style: TextStyle(color: Colors.black45),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SignUpScreen(),
                                ),
                              );
                            },
                            child: Text('Sign up', style: AppTextStyles.link),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
