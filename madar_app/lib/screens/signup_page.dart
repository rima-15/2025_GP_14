import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:madar_app/screens/signin_page.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'check_email_page.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formSignupKey = GlobalKey<FormState>();
  bool agreePersonalData = true;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  //error messages style
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

  String? _validatePhone(String? v) {
    if (v == null || v.isEmpty) return 'Enter phone number';
    if (!RegExp(r'^\d{9}$').hasMatch(v)) {
      return 'Enter 9 digits after +966';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Enter password';
    if (v.length < 8) return 'At least 8 characters';
    if (!RegExp(r'[a-z]').hasMatch(v)) return 'Must contain lowercase';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Must contain uppercase';
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Must contain a number';
    return null;
  }

  Future<void> _signUp() async {
    if (!_formSignupKey.currentState!.validate() || !agreePersonalData) return;

    setState(() => _loading = true);

    try {
      final fullPhone = '+966${_phoneCtrl.text}';

      //Phone num check
      final phoneDoc = await FirebaseFirestore.instance
          .collection('phoneNumbers')
          .doc(fullPhone)
          .get();

      final bool phoneExists = phoneDoc.exists;

      UserCredential? cred;
      bool emailExists = false;

      // Create an account
      try {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          emailExists = true;
        } else {
          rethrow;
        }
      }

      // email and phone already in use
      if (emailExists && phoneExists) {
        if (mounted) {
          _showErrorMessage('Both email and phone number are already in use');
        }
        return;
      }

      // phone in use
      if (phoneExists) {
        if (cred != null) {
          await cred.user!.delete();
        }

        if (mounted) {
          _showErrorMessage('Phone number is already in use');
        }
        return;
      }

      // email in use
      if (emailExists) {
        if (mounted) {
          _showErrorMessage('Email is already in use');
        }
        return;
      }

      // all good ? save user
      final user = cred!.user!;

      final batch = FirebaseFirestore.instance.batch();

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      batch.set(userRef, {
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': fullPhone,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final phoneRef = FirebaseFirestore.instance
          .collection('phoneNumbers')
          .doc(fullPhone);
      batch.set(phoneRef, {
        'uid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      await user.sendEmailVerification();
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CheckEmailPage(email: _emailCtrl.text.trim()),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Something went wrong';
      if (e.code == 'email-already-in-use') msg = 'Email is already in use';
      if (e.code == 'invalid-email') msg = 'Invalid email format';
      if (e.code == 'weak-password') msg = 'Password is too weak';

      if (mounted) {
        _showErrorMessage(msg);
      }
    } on FirebaseException catch (e) {
      String msg = 'Something went wrong';
      if (e.code == 'permission-denied') msg = 'Permission denied';
      if (e.code == 'unavailable') msg = 'Service unavailable';

      if (mounted) {
        _showErrorMessage(msg);
      }

      try {
        await FirebaseAuth.instance.currentUser?.delete();
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        _showErrorMessage('An unexpected error occurred');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showLogo: true,
      child: Column(
        children: [
          const Expanded(flex: 1, child: SizedBox(height: 10)),
          Expanded(
            flex: 13,
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
                  key: _formSignupKey,
                  child: Column(
                    children: [
                      Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF787E65),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // First Name
                      TextFormField(
                        controller: _firstNameCtrl,
                        decoration: InputDecoration(
                          label: const Text('First Name'),
                          hintText: 'Enter First Name',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Enter First Name' : null,
                      ),
                      const SizedBox(height: 25),

                      // Last Name
                      TextFormField(
                        controller: _lastNameCtrl,
                        decoration: InputDecoration(
                          label: const Text('Last Name'),
                          hintText: 'Enter Last Name',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Enter Last Name' : null,
                      ),
                      const SizedBox(height: 25),

                      // Email (محسّن للتحقق من الصيغة)
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: InputDecoration(
                          label: const Text('Email'),
                          hintText: 'Enter Email',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'Enter Email';
                          final email = v.trim();
                          final emailRegex = RegExp(
                            r"^[\w\.\-]+@[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}$",
                          );
                          if (!emailRegex.hasMatch(email))
                            return 'Invalid email format';
                          return null;
                        },
                      ),
                      const SizedBox(height: 25),

                      // Phone Number
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(9),
                        ],
                        decoration: InputDecoration(
                          label: const Text('Phone Number'),
                          prefixText: '+966 ',
                          hintText: 'Enter 9 digits',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: _validatePhone,
                      ),
                      const SizedBox(height: 25),

                      // Password
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          label: const Text('Password'),
                          hintText: 'Enter Password',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: _validatePassword,
                      ),
                      const SizedBox(height: 25),

                      // Sign Up button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF787E65),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _loading ? null : _signUp,
                          child: _loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text('Sign up'),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Already have account
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Already have an account?'),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SignInScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              ' Sign in',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF787E65),
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
}
