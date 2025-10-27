import 'package:flutter/material.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:madar_app/screens/signup_page.dart';
import 'package:madar_app/screens/forgot_password_page.dart';
import 'package:madar_app/widgets/MainLayout.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formSignInKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  final Color green = const Color(0xFF787E65);

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // error message
  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        backgroundColor: Colors.redAccent.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        elevation: 6,
      ),
    );
  }

  Future<void> _signIn() async {
    if (!_formSignInKey.currentState!.validate()) {
      _showErrorMessage('Please fill all fields correctly');
      return;
    }

    setState(() => _loading = true);

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      final user = cred.user!;
      await user.reload();

      if (!user.emailVerified) {
        try {
          await user.sendEmailVerification();
        } catch (_) {}
        await FirebaseAuth.instance.signOut();

        _showErrorMessage(
          'Email not verified! Please verify your email first.',
        );
        setState(() => _loading = false);
        return;
      }

      // ✅ إذا فعّل الإيميل، نضيف بياناته لأول مرة إلى Firestore
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final doc = await userRef.get();

      if (!doc.exists) {
        final prefs = await SharedPreferences.getInstance();

        await userRef.set({
          'firstName': prefs.getString('firstName') ?? '',
          'lastName': prefs.getString('lastName') ?? '',
          'email': prefs.getString('email') ?? user.email,
          'phone': prefs.getString('phone') ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });

        await prefs.clear(); // نحذفها بعد الحفظ
      }

      if (mounted) {
        Navigator.pushReplacement(
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
      _showErrorMessage(msg);
    } catch (e) {
      _showErrorMessage('Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _obscurePassword = true; //eye icon

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
                  topLeft: Radius.circular(35),
                  topRight: Radius.circular(35),
                ),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _formSignInKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Welcome back',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: green,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Email
                      TextFormField(
                        controller: _emailCtrl,
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please enter email';
                          }
                          if (!v.contains('@') || !v.contains('.')) {
                            return 'Invalid email';
                          }
                          return null;
                        },
                        decoration: _input('Email', 'Enter Email'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 25),

                      // Password
                      // Password
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscurePassword,
                        obscuringCharacter: '*',
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please enter password';
                          }
                          if (v.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'Password',
                          hintText: 'Enter Password',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
                        ),
                      ),

                      const SizedBox(height: 25),

                      // Forgot password
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
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: green,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),

                      // Sign in button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _loading ? null : _signIn,
                          child: _loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  'Sign in',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 25),

                      // Sign up link
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
                            child: Text(
                              'Sign up',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: green,
                              ),
                            ),
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

  InputDecoration _input(String label, String hint) {
    return InputDecoration(
      label: Text(label),
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black26),
      border: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
