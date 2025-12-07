import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:madar_app/screens/signin_page.dart';
import 'package:madar_app/widgets/custom_scaffold.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'check_email_page.dart';

// ----------------------------------------------------------------------------
// Sign Up Screen
// ----------------------------------------------------------------------------

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formSignupKey = GlobalKey<FormState>();

  // Controllers
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // Focus Nodes
  final _firstNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  late FocusNode _passwordFocus;

  bool _loading = false;

  // Validation States
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

  // Password Requirements
  bool _showPasswordRequirements = false;
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;

  // Name Requirements
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

  // ---------- Validation Methods ----------

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
    if (!RegExp(r'[^A-Za-z0-9 ]').hasMatch(v)) {
      return 'Must contain a special character';
    }
    return null;
  }

  // ---------- Sign Up Logic ----------

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
      //await user.sendEmailVerification();

      // Create Firestore user immediately after Sign Up
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        'email': email,
        'phone': fullPhone,
        'emailVerifiedStrict': false, // <-- NEW ATTRIBUTE
      });
      await user.sendEmailVerification();

      if (mounted) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => CheckEmailPage(email: email)),
        );
      }
    } catch (e) {
      if (e is FirebaseAuthException) {
        if (e.code == 'email-already-in-use') {
          SnackbarHelper.showError(context, 'Email is already in use');
        } else {
          SnackbarHelper.showError(
            context,
            e.message ?? 'Something went wrong',
          );
        }
      } else {
        SnackbarHelper.showError(context, 'Something went wrong');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- UI Helper Methods ----------

  /// Unified input decoration for all fields
  InputDecoration _decorateField({
    required String label,
    required String hint,
    required bool valid,
    String? error,
    Widget? suffix,
    String? prefix,
  }) {
    final OutlineInputBorder normalBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      borderSide: const BorderSide(color: Colors.grey),
    );

    final OutlineInputBorder errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      borderSide: const BorderSide(color: AppColors.kError, width: 1),
    );

    final OutlineInputBorder focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      borderSide: const BorderSide(color: AppColors.kGreen, width: 1.8),
    );

    final OutlineInputBorder focusedErrorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      borderSide: const BorderSide(color: AppColors.kError, width: 1.8),
    );

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      suffixIcon: suffix,
      border: normalBorder,
      enabledBorder: valid ? normalBorder : errorBorder,
      focusedBorder: valid ? focusedBorder : focusedErrorBorder,
      errorBorder: errorBorder,
      focusedErrorBorder: errorBorder,
      errorText: label == 'Password' ? null : error,
      errorStyle: TextStyle(
        color: AppColors.kError,
        fontSize: label == 'Password' ? 0 : 13,
      ),
      floatingLabelStyle: TextStyle(
        color: valid ? AppColors.kGreen : AppColors.kError,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  /// Builds requirement list items for names and password
  Widget _buildRequirementItem(String text, bool met) {
    return Row(
      children: [
        Icon(
          met ? Icons.check_circle : Icons.circle_outlined,
          color: met ? AppColors.kGreen : Colors.grey,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: met ? AppColors.kGreen : Colors.grey,
            fontSize: 13,
            fontWeight: met ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return CustomScaffold(
      showLogo: true,
      child: Column(
        children: [
          const Expanded(flex: 1, child: SizedBox()),
          Expanded(
            flex: 13,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                isSmallScreen ? 40 : 50,
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
                child: Form(
                  key: _formSignupKey,
                  child: Column(
                    children: [
                      // Title
                      Text('Get Started', style: AppTextStyles.largeTitles),
                      SizedBox(height: isSmallScreen ? 30 : 40),

                      // First Name Field
                      _buildFirstNameField(),
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
                      _buildLastNameField(),
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
                      _buildEmailField(),
                      const SizedBox(height: 25),

                      // Phone Field
                      _buildPhoneField(),
                      const SizedBox(height: 25),

                      // Password Field
                      _buildPasswordField(),
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
                      PrimaryButton(
                        text: 'Sign up',
                        onPressed: _signUp,
                        isLoading: _loading,
                      ),
                      const SizedBox(height: 25),

                      // Sign In Link
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
                            child: Text(' Sign in', style: AppTextStyles.link),
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

  // ---------- Field Builders ----------

  Widget _buildFirstNameField() {
    return TextFormField(
      controller: _firstNameCtrl,
      focusNode: _firstNameFocus,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (value) {
        setState(() {
          _firstNameHasMinLength = value.length >= 2;
          _firstNameStartsWithLetter = RegExp(r'^[A-Za-z]').hasMatch(value);

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
            _firstNameError = 'Must be less than 20 characters';
            _isFirstNameValid = false;
          } else if (!RegExp(r'^[A-Za-z][A-Za-z0-9-]{1,19}$').hasMatch(value)) {
            _firstNameError = 'Only letters, numbers, and "-" allowed';
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
        suffix: _isFirstNameValid && _firstNameCtrl.text.isNotEmpty
            ? const Icon(Icons.check_circle, color: AppColors.kGreen)
            : null,
      ),
    );
  }

  Widget _buildLastNameField() {
    return TextFormField(
      controller: _lastNameCtrl,
      focusNode: _lastNameFocus,
      onTap: () => _validatePreviousFields(1),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (value) {
        setState(() {
          _lastNameHasMinLength = value.length >= 2;
          _lastNameStartsWithLetter = RegExp(r'^[A-Za-z]').hasMatch(value);

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
            _lastNameError = 'Must be less than 20 characters';
            _isLastNameValid = false;
          } else if (!RegExp(r'^[A-Za-z][A-Za-z0-9-]{1,19}$').hasMatch(value)) {
            _lastNameError = 'Only letters, numbers, and "-" allowed';
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
        suffix: _isLastNameValid && _lastNameCtrl.text.isNotEmpty
            ? const Icon(Icons.check_circle, color: AppColors.kGreen)
            : null,
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
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
            ? const Icon(Icons.check_circle, color: AppColors.kGreen)
            : null,
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
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
            ? const Icon(Icons.check_circle, color: AppColors.kGreen)
            : null,
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
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
        _hasSpecialChar = RegExp(r'[^A-Za-z0-9 ]').hasMatch(v);

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
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey.shade600,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
            if (_isPasswordValid && _passCtrl.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.check_circle, color: AppColors.kGreen),
              ),
          ],
        ),
      ),
    );
  }
}
