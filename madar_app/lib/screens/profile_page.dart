import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:madar_app/screens/welcome_page.dart';
import 'package:madar_app/screens/check_email_page.dart';

const kGreen = Color(0xFF787E65);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _hasChanges = false;
  String _originalFirstName = '';
  String _originalLastName = '';
  String _originalEmail = '';
  String _originalPhone = '';

  // Error borders
  bool _emailError = false;
  bool _phoneError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();

    // Listen for changes to enable/disable save button
    _firstNameCtrl.addListener(_checkChanges);
    _lastNameCtrl.addListener(_checkChanges);
    _emailCtrl.addListener(_checkChanges);
    _phoneCtrl.addListener(_checkChanges);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _checkChanges() {
    final hasChanges =
        _firstNameCtrl.text != _originalFirstName ||
        _lastNameCtrl.text != _originalLastName ||
        _emailCtrl.text != _originalEmail ||
        _phoneCtrl.text != _originalPhone;

    if (hasChanges != _hasChanges) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _originalFirstName = data['firstName'] ?? '';
          _originalLastName = data['lastName'] ?? '';
          _originalEmail = data['email'] ?? '';
          final fullPhone = data['phone'] ?? '';
          _originalPhone = fullPhone.startsWith('+966')
              ? fullPhone.substring(4)
              : fullPhone;

          _firstNameCtrl.text = _originalFirstName;
          _lastNameCtrl.text = _originalLastName;
          _emailCtrl.text = _originalEmail;
          _phoneCtrl.text = _originalPhone;

          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to load profile data');
        setState(() => _loading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _emailError = message.toLowerCase().contains('email');
      _phoneError = message.toLowerCase().contains('phone');
    });
  }

  void _clearErrors() {
    setState(() {
      _errorMessage = '';
      _emailError = false;
      _phoneError = false;
    });
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF9FA88A).withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _saving = true;
      _clearErrors();
    });

    try {
      final newEmail = _emailCtrl.text.trim();
      final newPhone = '+966${_phoneCtrl.text}';
      final oldPhone = '+966$_originalPhone';
      final emailChanged = newEmail != _originalEmail;

      // Validate email format first
      if (!RegExp(
        r'^[\w\.\-]+@[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}$',
      ).hasMatch(newEmail)) {
        _showError('Invalid email');
        setState(() => _saving = false);
        return;
      }

      // Check if phone changed and if new phone exists
      if (newPhone != oldPhone) {
        final phoneDoc = await FirebaseFirestore.instance
            .collection('phoneNumbers')
            .doc(newPhone)
            .get();

        if (phoneDoc.exists && phoneDoc.data()?['uid'] != user.uid) {
          _showError('Phone number already in use');
          setState(() => _saving = false);
          return;
        }
      }

      // If email changed, send verification FIRST (before updating Firestore)
      if (emailChanged) {
        try {
          await user.verifyBeforeUpdateEmail(newEmail);
        } on FirebaseAuthException catch (e) {
          String msg = 'Failed to send verification email';
          if (e.code == 'email-already-in-use') {
            msg = 'Email already in use';
          } else if (e.code == 'invalid-email') {
            msg = 'Invalid email';
          } else if (e.code == 'requires-recent-login') {
            msg = 'Please sign out and sign in again to change your email';
          }
          _showError(msg);
          setState(() => _saving = false);
          return;
        }

        // Navigate to Check Email page (like sign up)
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => CheckEmailPage(email: newEmail)),
          );
        }
        return; // Don't continue to update Firestore yet
      }

      // Now update Firestore (only if email didn't change)
      final batch = FirebaseFirestore.instance.batch();

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      batch.update(userRef, {
        'firstName': _firstNameCtrl.text.trim(),
        'lastName': _lastNameCtrl.text.trim(),
        'email': newEmail,
        'phone': newPhone,
      });

      // Update phone collection if changed
      if (newPhone != oldPhone) {
        if (oldPhone.isNotEmpty) {
          final oldPhoneRef = FirebaseFirestore.instance
              .collection('phoneNumbers')
              .doc(oldPhone);
          batch.delete(oldPhoneRef);
        }

        final newPhoneRef = FirebaseFirestore.instance
            .collection('phoneNumbers')
            .doc(newPhone);
        batch.set(newPhoneRef, {
          'uid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // Update original values
      _originalFirstName = _firstNameCtrl.text.trim();
      _originalLastName = _lastNameCtrl.text.trim();
      _originalEmail = newEmail;
      _originalPhone = _phoneCtrl.text;

      if (mounted) {
        _showSuccessSnackbar('Profile updated successfully!');

        setState(() {
          _saving = false;
          _hasChanges = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Failed to update profile';
      if (e.code == 'requires-recent-login') {
        msg = 'Please sign out and sign in again to change your email';
      } else if (e.code == 'email-already-in-use') {
        msg = 'Email already in use';
      } else if (e.code == 'invalid-email') {
        msg = 'Invalid email';
      }
      _showError(msg);
      setState(() => _saving = false);
    } catch (e) {
      _showError('An error occurred. Please try again.');
      setState(() => _saving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Account',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get phone before deleting
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final phone = doc.data()?['phone'];

      // Delete user data from Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();

      // Delete phone number entry
      if (phone != null) {
        await FirebaseFirestore.instance
            .collection('phoneNumbers')
            .doc(phone)
            .delete();
      }

      // Delete Firebase Auth account
      await user.delete();

      if (mounted) {
        // Navigate to Welcome page (not Sign In)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _showError('Please sign in again to delete your account');
      } else {
        _showError('Failed to delete account');
      }
    } catch (e) {
      _showError('An error occurred');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: kGreen),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(color: kGreen, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Profile avatar
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: kGreen.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: kGreen, width: 3),
                      ),
                      child: const Icon(Icons.person, size: 50, color: kGreen),
                    ),
                    const SizedBox(height: 32),

                    // First Name and Last Name in one row
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _firstNameCtrl,
                            label: 'First Name',
                            hint: 'Enter first name',
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _lastNameCtrl,
                            label: 'Last Name',
                            hint: 'Enter last name',
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Email
                    _buildTextField(
                      controller: _emailCtrl,
                      label: 'Email',
                      hint: 'Enter email',
                      keyboardType: TextInputType.emailAddress,
                      hasError: _emailError,
                      errorText: _emailError ? _errorMessage : null,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (!RegExp(
                          r'^[\w\.\-]+@[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}$',
                        ).hasMatch(v.trim())) {
                          return 'Invalid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Phone
                    _buildTextField(
                      controller: _phoneCtrl,
                      label: 'Phone Number',
                      hint: 'Enter 9 digits',
                      keyboardType: TextInputType.phone,
                      prefixText: '+966 ',
                      hasError: _phoneError,
                      errorText: _phoneError ? _errorMessage : null,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(9),
                      ],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (!RegExp(r'^\d{9}$').hasMatch(v)) {
                          return 'Must be 9 digits';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Password (disabled)
                    _buildTextField(
                      controller: TextEditingController(text: '••••••••'),
                      label: 'Password',
                      hint: '',
                      enabled: false,
                      obscureText: true,
                    ),
                    const SizedBox(height: 40),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_saving || !_hasChanges)
                            ? null
                            : _saveChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Delete account button
                    InkWell(
                      onTap: _deleteAccount,
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        child: const Text(
                          'Delete Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool enabled = true,
    bool obscureText = false,
    String? prefixText,
    List<TextInputFormatter>? inputFormatters,
    bool hasError = false,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          onChanged: (_) {
            if (hasError) _clearErrors();
          },
          style: TextStyle(
            color: enabled ? Colors.black87 : Colors.grey,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixText: prefixText,
            filled: true,
            fillColor: enabled ? Colors.white : Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? Colors.red : Colors.black12,
                width: hasError ? 2 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? Colors.red : kGreen,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            errorStyle: const TextStyle(height: 0),
          ),
        ),
        // Show error message below field
        if (hasError && errorText != null && errorText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 6),
            child: Text(
              errorText,
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}
