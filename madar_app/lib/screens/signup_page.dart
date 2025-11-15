import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:madar_app/screens/signin_page.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'check_email_page.dart';
import 'package:madar_app/widgets/app_widgets.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formSignupKey = GlobalKey<FormState>();

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  final _firstNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  late FocusNode _passwordFocus;

  bool _loading = false;

  bool _isFirstNameValid = true;
  String? _firstNameError;

  bool _isLastNameValid = true;
  String? _lastNameError;

  bool _isEmailValid = true;
  String? _emailError;

  bool _isPhoneValid = true;
  String? _phoneError;

  bool _isPasswordValid = true;
  String? _passwordError;
  bool _obscurePassword = true;

  // Password requirements
  bool _showPasswordRequirements = false;
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;

  // Name requirements
  bool _showFirstNameRequirements = false;
  bool _showLastNameRequirements = false;
  bool _firstNameHasMinLength = false;
  bool _firstNameStartsWithLetter = false;
  bool _lastNameHasMinLength = false;
  bool _lastNameStartsWithLetter = false;

  @override
  void initState() {
    super.initState();

    _passwordFocus = FocusNode();
    _passwordFocus.addListener(() {
      setState(() => _showPasswordRequirements = _passwordFocus.hasFocus);
    });

    _firstNameFocus.addListener(() {
      setState(() => _showFirstNameRequirements = _firstNameFocus.hasFocus);
    });

    _lastNameFocus.addListener(() {
      setState(() => _showLastNameRequirements = _lastNameFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();

    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Validates all previous fields before allowing the next step
  bool _validatePreviousFields(int step) {
    bool valid = true;

    setState(() {
      if (_firstNameCtrl.text.isEmpty ||
          !_isFirstNameValid ||
          !RegExp(
            r'^[A-Za-z][A-Za-z0-9-]{1,19}$',
          ).hasMatch(_firstNameCtrl.text)) {
        _firstNameError = 'Enter valid First Name';
        _isFirstNameValid = false;
        valid = false;
      }

      if (step > 1 &&
          (_lastNameCtrl.text.isEmpty ||
              !_isLastNameValid ||
              !RegExp(
                r'^[A-Za-z][A-Za-z0-9-]{1,19}$',
              ).hasMatch(_lastNameCtrl.text))) {
        _lastNameError = 'Enter valid Last Name';
        _isLastNameValid = false;
        valid = false;
      }

      if (step > 2 &&
          (_emailCtrl.text.isEmpty ||
              !_isEmailValid ||
              !RegExp(
                r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$",
              ).hasMatch(_emailCtrl.text))) {
        _emailError = 'Enter valid Email';
        _isEmailValid = false;
        valid = false;
      }

      if (step > 3 &&
          (_phoneCtrl.text.isEmpty ||
              !_isPhoneValid ||
              !RegExp(r'^\d{9}$').hasMatch(_phoneCtrl.text))) {
        _phoneError = 'Enter 9 digits';
        _isPhoneValid = false;
        valid = false;
      }

      if (step > 4 &&
          (_passCtrl.text.isEmpty ||
              !_isPasswordValid ||
              _validatePassword(_passCtrl.text) != null)) {
        _passwordError = 'Enter valid password';
        _isPasswordValid = false;
        valid = false;
      }
    });

    if (!valid) {
      if (!_isFirstNameValid) {
        _firstNameFocus.requestFocus();
      } else if (!_isLastNameValid) {
        _lastNameFocus.requestFocus();
      } else if (!_isEmailValid) {
        _emailFocus.requestFocus();
      } else if (!_isPhoneValid) {
        _phoneFocus.requestFocus();
      } else if (!_isPasswordValid) {
        _passwordFocus.requestFocus();
      }
    }

    return valid;
  }

  /// Validates password strength
  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Enter password';
    if (v.length < 8) return 'At least 8 characters';
    if (!RegExp(r'[a-z]').hasMatch(v)) return 'Must contain lowercase letter';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Must contain uppercase letter';
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Must contain a number';
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(v)) {
      return 'Must contain a special character';
    }
    return null;
  }

  /// Handles sign-up process using Firebase Authentication and Firestore
  Future<void> _signUp() async {
    setState(() => _loading = true);

    if (_firstNameCtrl.text.isEmpty ||
        _lastNameCtrl.text.isEmpty ||
        _emailCtrl.text.isEmpty ||
        _phoneCtrl.text.isEmpty ||
        _passCtrl.text.isEmpty ||
        !_isFirstNameValid ||
        !_isLastNameValid ||
        !_isEmailValid ||
        !_isPhoneValid ||
        !_isPasswordValid) {
      SnackbarHelper.showError(
        context,
        'Please fill all fields correctly before signing up',
      );
      _validatePreviousFields(5);
      setState(() => _loading = false);
      return;
    }

    try {
      final email = _emailCtrl.text.trim();
      final fullPhone = '+966${_phoneCtrl.text.trim()}';

      final users = FirebaseFirestore.instance.collection('users');
      final emailExists =
          (await users.where('email', isEqualTo: email).get()).docs.isNotEmpty;
      final phoneExists =
          (await users.where('phone', isEqualTo: fullPhone).get())
              .docs
              .isNotEmpty;

      if (emailExists && phoneExists) {
        SnackbarHelper.showError(
          context,
          'Both email and phone number are already in use',
        );
        setState(() => _loading = false);
        return;
      } else if (emailExists) {
        SnackbarHelper.showError(context, 'Email is already in use');
        setState(() => _loading = false);
        return;
      } else if (phoneExists) {
        SnackbarHelper.showError(context, 'Phone number is already in use');
        setState(() => _loading = false);
        return;
      }

      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: _passCtrl.text,
      );

      final user = cred.user!;
      await user.sendEmailVerification();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('firstName', _firstNameCtrl.text.trim());
      await prefs.setString('lastName', _lastNameCtrl.text.trim());
      await prefs.setString('email', email);
      await prefs.setString('phone', fullPhone);

      //await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => CheckEmailPage(email: email)),
        );
      }
    } catch (e) {
      SnackbarHelper.showError(context, 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Unified input decoration for all fields
  InputDecoration _decorateField({
    required String label,
    required String hint,
    required bool valid,
    String? error,
    Widget? suffix,
    String? prefix,
  }) {
    const Color mainGreen = Color(0xFF787E65);
    //final Color errorColor = Colors.redAccent.shade700; //red
    final Color kError = Color(0xFFC62828);
    const Color normalColor = Colors.grey;

    final OutlineInputBorder normalBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: normalColor),
    );

    final OutlineInputBorder errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: kError, width: 1.8),
    );

    final OutlineInputBorder focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: mainGreen, width: 1.8),
    );

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      suffixIcon: suffix,
      border: normalBorder,
      enabledBorder: valid ? normalBorder : errorBorder,
      focusedBorder: valid ? focusedBorder : errorBorder,
      errorBorder: errorBorder,
      focusedErrorBorder: errorBorder,
      errorText: label == 'Password' ? null : error,
      errorStyle: TextStyle(
        color: kError,
        fontSize: label == 'Password' ? 0 : 13,
      ),
      floatingLabelStyle: TextStyle(
        color: valid ? mainGreen : kError,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  /// Builds requirement list items (used for names and password)
  Widget _buildRequirementItem(String text, bool met) {
    return Row(
      children: [
        Icon(
          met ? Icons.check_circle : Icons.circle_outlined,
          color: met ? const Color(0xFF787E65) : Colors.grey,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: met ? const Color(0xFF787E65) : Colors.grey,
            fontSize: 13,
            fontWeight: met ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScaffold(
      showLogo: true,
      child: Column(
        children: [
          const Expanded(flex: 1, child: SizedBox()),
          Expanded(
            flex: 13,
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
                  key: _formSignupKey,
                  child: Column(
                    children: [
                      const Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF787E65),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // First Name Field
                      TextFormField(
                        controller: _firstNameCtrl,
                        focusNode: _firstNameFocus,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        onChanged: (value) {
                          setState(() {
                            _firstNameHasMinLength = value.length >= 2;
                            _firstNameStartsWithLetter = RegExp(
                              r'^[A-Za-z]',
                            ).hasMatch(value);

                            if (value.isEmpty) {
                              _firstNameError = 'Enter First Name';
                              _isFirstNameValid = false;
                            } else if (!RegExp(r'^[A-Za-z]').hasMatch(value)) {
                              _firstNameError = null;
                              _isFirstNameValid = false;
                            } else if (value.length < 2) {
                              _firstNameError = null;
                              _isFirstNameValid = false;
                            } else if (value.length > 20) {
                              _firstNameError =
                                  'Must be less than 20 characters';
                              _isFirstNameValid = false;
                            } else if (!RegExp(
                              r'^[A-Za-z][A-Za-z0-9-]{1,19}$',
                            ).hasMatch(value)) {
                              _firstNameError =
                                  'Only letters, numbers, and "-" allowed';
                              _isFirstNameValid = false;
                            } else {
                              _firstNameError = null;
                              _isFirstNameValid = true;
                            }
                          });
                        },
                        decoration: _decorateField(
                          label: 'First Name',
                          hint: 'Enter First Name',
                          valid: _isFirstNameValid,
                          error: _firstNameError,
                          suffix:
                              _isFirstNameValid &&
                                  _firstNameCtrl.text.isNotEmpty
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF787E65),
                                )
                              : null,
                        ),
                      ),
                      if (_showFirstNameRequirements) ...[
                        const SizedBox(height: 10),
                        _buildRequirementItem(
                          'Starts with a letter',
                          _firstNameStartsWithLetter,
                        ),
                        _buildRequirementItem(
                          'Has at least 2 characters',
                          _firstNameHasMinLength,
                        ),
                      ],
                      const SizedBox(height: 25),

                      // Last Name Field
                      TextFormField(
                        controller: _lastNameCtrl,
                        focusNode: _lastNameFocus,
                        onTap: () => _validatePreviousFields(1),
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        onChanged: (value) {
                          setState(() {
                            _lastNameHasMinLength = value.length >= 2;
                            _lastNameStartsWithLetter = RegExp(
                              r'^[A-Za-z]',
                            ).hasMatch(value);

                            if (value.isEmpty) {
                              _lastNameError = 'Enter Last Name';
                              _isLastNameValid = false;
                            } else if (!RegExp(r'^[A-Za-z]').hasMatch(value)) {
                              _lastNameError = null;
                              _isLastNameValid = false;
                            } else if (value.length < 2) {
                              _lastNameError = null;
                              _isLastNameValid = false;
                            } else if (value.length > 20) {
                              _lastNameError =
                                  'Must be less than 20 characters';
                              _isLastNameValid = false;
                            } else if (!RegExp(
                              r'^[A-Za-z][A-Za-z0-9-]{1,19}$',
                            ).hasMatch(value)) {
                              _lastNameError =
                                  'Only letters, numbers, and "-" allowed';
                              _isLastNameValid = false;
                            } else {
                              _lastNameError = null;
                              _isLastNameValid = true;
                            }
                          });
                        },
                        decoration: _decorateField(
                          label: 'Last Name',
                          hint: 'Enter Last Name',
                          valid: _isLastNameValid,
                          error: _lastNameError,
                          suffix:
                              _isLastNameValid && _lastNameCtrl.text.isNotEmpty
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF787E65),
                                )
                              : null,
                        ),
                      ),
                      if (_showLastNameRequirements) ...[
                        const SizedBox(height: 10),
                        _buildRequirementItem(
                          'Starts with a letter',
                          _lastNameStartsWithLetter,
                        ),
                        _buildRequirementItem(
                          'Has at least 2 characters',
                          _lastNameHasMinLength,
                        ),
                      ],
                      const SizedBox(height: 25),

                      // Email Field
                      TextFormField(
                        controller: _emailCtrl,
                        focusNode: _emailFocus,
                        onTap: () => _validatePreviousFields(2),
                        keyboardType: TextInputType.emailAddress,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        onChanged: (v) => setState(() {
                          if (v.isEmpty) {
                            _emailError = 'Enter Email';
                            _isEmailValid = false;
                          } else if (!RegExp(
                            r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$",
                          ).hasMatch(v)) {
                            _emailError = 'Invalid email format';
                            _isEmailValid = false;
                          } else {
                            _emailError = null;
                            _isEmailValid = true;
                          }
                        }),
                        decoration: _decorateField(
                          label: 'Email',
                          hint: 'Enter Email',
                          valid: _isEmailValid,
                          error: _emailError,
                          suffix: _isEmailValid && _emailCtrl.text.isNotEmpty
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF787E65),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 25),

                      // Phone Field
                      TextFormField(
                        controller: _phoneCtrl,
                        focusNode: _phoneFocus,
                        onTap: () => _validatePreviousFields(3),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(9),
                        ],
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        onChanged: (v) => setState(() {
                          if (v.isEmpty) {
                            _phoneError = 'Enter phone number';
                            _isPhoneValid = false;
                          } else if (!RegExp(r'^\d{9}$').hasMatch(v)) {
                            _phoneError = 'Enter 9 digits';
                            _isPhoneValid = false;
                          } else {
                            _phoneError = null;
                            _isPhoneValid = true;
                          }
                        }),
                        decoration: _decorateField(
                          label: 'Phone Number',
                          hint: 'Enter 9 digits',
                          valid: _isPhoneValid,
                          error: _phoneError,
                          prefix: '+966 ',
                          suffix: _isPhoneValid && _phoneCtrl.text.isNotEmpty
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF787E65),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 25),

                      // Password Field
                      TextFormField(
                        controller: _passCtrl,
                        focusNode: _passwordFocus,
                        onTap: () => _validatePreviousFields(4),
                        obscureText: _obscurePassword,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        onChanged: (v) => setState(() {
                          _hasMinLength = v.length >= 8;
                          _hasUppercase = RegExp(r'[A-Z]').hasMatch(v);
                          _hasLowercase = RegExp(r'[a-z]').hasMatch(v);
                          _hasNumber = RegExp(r'[0-9]').hasMatch(v);
                          _hasSpecialChar = RegExp(
                            r'[!@#\$%^&*(),.?":{}|<>]',
                          ).hasMatch(v);

                          final err = _validatePassword(v);
                          _passwordError = err;
                          _isPasswordValid = err == null;
                        }),
                        decoration: _decorateField(
                          label: 'Password',
                          hint: 'Enter Password',
                          valid: _isPasswordValid,
                          error: _passwordError,
                          suffix: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey.shade600,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                              if (_isPasswordValid && _passCtrl.text.isNotEmpty)
                                const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF787E65),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_showPasswordRequirements) ...[
                        const SizedBox(height: 10),
                        _buildRequirementItem(
                          'Has at least 8 characters',
                          _hasMinLength,
                        ),
                        _buildRequirementItem(
                          'Includes an uppercase letter',
                          _hasUppercase,
                        ),
                        _buildRequirementItem(
                          'Includes a lowercase letter',
                          _hasLowercase,
                        ),
                        _buildRequirementItem('Includes a number', _hasNumber),
                        _buildRequirementItem(
                          'Includes a special character',
                          _hasSpecialChar,
                        ),
                      ],
                      const SizedBox(height: 25),

                      // Sign Up Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF787E65),
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
                      const SizedBox(height: 25),

                      // Redirect to Sign In
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
