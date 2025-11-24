import 'package:flutter/material.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:madar_app/widgets/app_widgets.dart';

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
    _emailCtrl.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _sendPasswordResetEmail() async {
    if (!_formKey.currentState!.validate()) {
      // Focus email field if validation fails
      _emailFocus.requestFocus();
      return;
    }

    setState(() => _loading = true);

    try {
      final email = _emailCtrl.text.trim();

      //
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
    } finally {}
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
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Forgot Password',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppColors.kGreen,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Enter the email associated with your account and we'll send you a password reset link.",
                        style: TextStyle(color: Colors.grey[700], fontSize: 15),
                      ),
                      const SizedBox(height: 30),
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

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.kGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _loading ? null : _sendPasswordResetEmail,
                          child: _loading
                              ? LayoutBuilder(
                                  builder: (context, constraints) {
                                    final size = (constraints.maxHeight * 0.6)
                                        .clamp(16.0, 24.0); // Between 16-24
                                    return SizedBox(
                                      width: size,
                                      height: size,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    );
                                  },
                                )
                              : const Text(
                                  "Send reset link",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Back to Sign In',
                            style: TextStyle(
                              color: AppColors.kGreen,
                              fontWeight: FontWeight.bold,
                            ),
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
