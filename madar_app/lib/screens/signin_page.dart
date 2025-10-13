import 'package:flutter/material.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:madar_app/screens/signup_page.dart';
import 'package:madar_app/screens/forgot_password_page.dart';
import 'package:madar_app/widgets/MainLayout.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ جديد

class SignInScreen
    extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() =>
      _SignInScreenState();
}

class _SignInScreenState
    extends State<SignInScreen> {
  final _formSignInKey =
      GlobalKey<FormState>();
  final _emailCtrl =
      TextEditingController();
  final _passCtrl =
      TextEditingController();
  bool rememberPassword =
      false; // يبدأ False
  bool _loading = false;
  final Color green = const Color(
    0xFF787E65,
  );

  @override
  void initState() {
    super.initState();
    _checkAutoLogin(); // ✅ تسجيل دخول تلقائي لو Remember Me مفعّل
  }

  // ✅ تحقق إذا المستخدم مفعّل "Remember Me" و Logged In
  Future<void> _checkAutoLogin() async {
    final prefs =
        await SharedPreferences.getInstance();
    final remember =
        prefs.getBool('remember_me') ??
        false;
    final currentUser = FirebaseAuth
        .instance
        .currentUser;

    if (remember &&
        currentUser != null) {
      // المستخدم مفعّل Remember Me وموجود في Firebase
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const MainLayout(),
        ),
      );
    }
  }

  // ✅ حفظ حالة Remember Me بعد تسجيل الدخول
  Future<void> _saveRememberMe(
    bool value,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();
    await prefs.setBool(
      'remember_me',
      value,
    );
  }

  void _showErrorSnackBar(
    String message,
  ) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior:
            SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _signIn() async {
    if (!_formSignInKey.currentState!
        .validate()) {
      _showErrorSnackBar(
        'Please fill all fields correctly',
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final cred = await FirebaseAuth
          .instance
          .signInWithEmailAndPassword(
            email: _emailCtrl.text
                .trim(),
            password: _passCtrl.text,
          );

      final user = cred.user!;
      await user.reload();

      if (!user.emailVerified) {
        try {
          await user
              .sendEmailVerification();
        } catch (_) {}
        await FirebaseAuth.instance
            .signOut();

        _showErrorSnackBar(
          'Email not verified! Please verify your email first.',
        );
        setState(
          () => _loading = false,
        );
        return;
      }

      // ✅ إذا فعّل Remember Me نحفظ حالته
      await _saveRememberMe(
        rememberPassword,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const MainLayout(),
          ),
        );
      }
    } on FirebaseAuthException catch (
      e
    ) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg =
              'No account found with this email';
          break;
        case 'wrong-password':
          msg = 'Wrong password';
          break;
        case 'invalid-email':
          msg = 'Invalid email address';
          break;
        case 'user-disabled':
          msg =
              'This account is disabled';
          break;
        case 'too-many-requests':
          msg =
              'Too many attempts, please try again later';
          break;
        default:
          msg =
              'Login error: ${e.message}';
      }
      _showErrorSnackBar(msg);
    } catch (e) {
      _showErrorSnackBar(
        'Unexpected error: $e',
      );
    } finally {
      if (mounted)
        setState(
          () => _loading = false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showLogo: true,
      child: Column(
        children: [
          const Expanded(
            flex: 1,
            child: SizedBox(height: 10),
          ),
          Expanded(
            flex: 7,
            child: Container(
              padding:
                  const EdgeInsets.fromLTRB(
                    25,
                    50,
                    25,
                    20,
                  ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.only(
                      topLeft:
                          Radius.circular(
                            40,
                          ),
                      topRight:
                          Radius.circular(
                            40,
                          ),
                    ),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _formSignInKey,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .center,
                    children: [
                      Text(
                        'Welcome back',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight:
                              FontWeight
                                  .w900,
                          color: green,
                        ),
                      ),
                      const SizedBox(
                        height: 40,
                      ),

                      // Email
                      TextFormField(
                        controller:
                            _emailCtrl,
                        validator: (v) {
                          if (v ==
                                  null ||
                              v.isEmpty)
                            return 'Please enter email';
                          if (!v.contains(
                                '@',
                              ) ||
                              !v.contains(
                                '.',
                              ))
                            return 'Invalid email';
                          return null;
                        },
                        decoration: _input(
                          'Email',
                          'Enter Email',
                        ),
                        keyboardType:
                            TextInputType
                                .emailAddress,
                      ),
                      const SizedBox(
                        height: 25,
                      ),

                      // Password
                      TextFormField(
                        controller:
                            _passCtrl,
                        obscureText:
                            true,
                        obscuringCharacter:
                            '*',
                        validator: (v) {
                          if (v ==
                                  null ||
                              v.isEmpty)
                            return 'Please enter password';
                          if (v.length <
                              6)
                            return 'Password must be at least 6 characters';
                          return null;
                        },
                        decoration: _input(
                          'Password',
                          'Enter Password',
                        ),
                      ),
                      const SizedBox(
                        height: 25,
                      ),

                      // Remember + Forgot
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value:
                                    rememberPassword,
                                onChanged: (v) {
                                  setState(
                                    () => rememberPassword =
                                        v ??
                                        false,
                                  );
                                },
                                activeColor:
                                    green,
                              ),
                              const Text(
                                'Remember me',
                                style: TextStyle(
                                  color:
                                      Colors.black45,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ForgotPasswordScreen(),
                                ),
                              );
                            },
                            child: Text(
                              'Forget password?',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    green,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 25,
                      ),

                      // Sign in
                      SizedBox(
                        width: double
                            .infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                green,
                            foregroundColor:
                                Colors
                                    .white,
                            padding:
                                const EdgeInsets.symmetric(
                                  vertical:
                                      14,
                                ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                    10,
                                  ),
                            ),
                          ),
                          onPressed:
                              _loading
                              ? null
                              : _signIn,
                          child:
                              _loading
                              ? const CircularProgressIndicator(
                                  color:
                                      Colors.white,
                                )
                              : const Text(
                                  'Sign in',
                                  style: TextStyle(
                                    fontSize:
                                        16,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(
                        height: 25,
                      ),

                      // Sign up
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .center,
                        children: [
                          const Text(
                            'Don\'t have an account? ',
                            style: TextStyle(
                              color: Colors
                                  .black45,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const SignUpScreen(),
                                ),
                              );
                            },
                            child: Text(
                              'Sign up',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                                color:
                                    green,
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

  InputDecoration _input(
    String label,
    String hint,
  ) {
    return InputDecoration(
      label: Text(label),
      hintText: hint,
      hintStyle: const TextStyle(
        color: Colors.black26,
      ),
      border: OutlineInputBorder(
        borderSide: const BorderSide(
          color: Colors.black12,
        ),
        borderRadius:
            BorderRadius.circular(10),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(
          color: Colors.black12,
        ),
        borderRadius:
            BorderRadius.circular(10),
      ),
    );
  }
}
