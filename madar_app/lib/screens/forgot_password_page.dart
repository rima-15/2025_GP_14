import 'package:flutter/material.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';

// ----------------------------------------------------------------------------
// Forgot Password Screen
// ----------------------------------------------------------------------------

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  bool _loading = false;

  @override
  void dispose() {
    // Clear any lingering snackbars when leaving the page
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }
    _emailCtrl.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  // ---------- Send Password Reset Email ----------

  Future<void> _sendPasswordResetEmail() async {
    if (!_formKey.currentState!.validate()) {
      _emailFocus.requestFocus();
      return;
    }

    setState(() => _loading = true);

    try {
      final email = _emailCtrl.text.trim();

      // Check if email exists in database
      final usersRef = FirebaseFirestore.instance.collection('users');
      final userQuery = await usersRef.where('email', isEqualTo: email).get();

      if (userQuery.docs.isEmpty) {
        SnackbarHelper.showError(context, 'No account found with this email');
        setState(() => _loading = false);
        return;
      }

      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (mounted) {
        SnackbarHelper.showSuccess(
          context,
          'Password reset link sent!\nPlease check your email: $email',
        );

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'No account found with this email';
          break;
        case 'invalid-email':
          msg = 'Invalid email address';
          break;
        case 'too-many-requests':
          msg = 'Too many requests. Please try again later';
          break;
        default:
          msg = 'Error occurred: ${e.message}';
      }
      SnackbarHelper.showError(context, msg);
    } catch (e) {
      SnackbarHelper.showError(
        context,
        'Unexpected error occurred, please try again',
      );
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
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text('Forgot Password', style: AppTextStyles.pageTitle),
                      const SizedBox(height: 10),

                      // Description
                      Text(
                        "Enter the email associated with your account and we'll send you a password reset link.",
                        style: TextStyle(color: Colors.grey[700], fontSize: 15),
                      ),
                      const SizedBox(height: 30),

                      // Email Field
                      StyledTextField(
                        controller: _emailCtrl,
                        focusNode: _emailFocus,
                        label: 'Email',
                        hint: 'Enter your email',
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!v.contains('@') || !v.contains('.')) {
                            return 'Invalid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 30),

                      // Send Reset Link Button
                      PrimaryButton(
                        text: 'Send reset link',
                        onPressed: _sendPasswordResetEmail,
                        isLoading: _loading,
                      ),
                      const SizedBox(height: 20),

                      // Back to Sign In Link
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Back to Sign In',
                            style: AppTextStyles.link,
                          ),
                        ),
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
