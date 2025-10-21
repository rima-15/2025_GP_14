import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  String _originalEmail = '';
  String _originalPhone = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
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
          _firstNameCtrl.text = data['firstName'] ?? '';
          _lastNameCtrl.text = data['lastName'] ?? '';
          _emailCtrl.text = data['email'] ?? '';
          _originalEmail = data['email'] ?? '';

          // Extract phone without +966
          final fullPhone = data['phone'] ?? '';
          _phoneCtrl.text = fullPhone.startsWith('+966')
              ? fullPhone.substring(4)
              : fullPhone;
          _originalPhone = fullPhone;

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.redAccent.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccess(String message) {
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
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    try {
      final newEmail = _emailCtrl.text.trim();
      final newPhone = '+966${_phoneCtrl.text}';
      final batch = FirebaseFirestore.instance.batch();

      // Check if phone changed and if new phone exists
      if (newPhone != _originalPhone) {
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

      // Update user document
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
      if (newPhone != _originalPhone) {
        // Delete old phone entry
        if (_originalPhone.isNotEmpty) {
          final oldPhoneRef = FirebaseFirestore.instance
              .collection('phoneNumbers')
              .doc(_originalPhone);
          batch.delete(oldPhoneRef);
        }

        // Add new phone entry
        final newPhoneRef = FirebaseFirestore.instance
            .collection('phoneNumbers')
            .doc(newPhone);
        batch.set(newPhoneRef, {
          'uid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // If email changed, update Firebase Auth and send verification
      if (newEmail != _originalEmail) {
        await user.verifyBeforeUpdateEmail(newEmail);

        if (mounted) {
          _showSuccess(
            'Profile updated! Please verify your new email address before it takes effect.',
          );
        }
      } else {
        if (mounted) {
          _showSuccess('Profile updated successfully!');
        }
      }

      // Reload data
      _originalEmail = newEmail;
      _originalPhone = newPhone;

      setState(() => _saving = false);
    } on FirebaseAuthException catch (e) {
      String msg = 'Failed to update profile';
      if (e.code == 'requires-recent-login') {
        msg = 'Please sign in again to change your email';
      } else if (e.code == 'email-already-in-use') {
        msg = 'Email already in use';
      } else if (e.code == 'invalid-email') {
        msg = 'Invalid email address';
      }
      _showError(msg);
      setState(() => _saving = false);
    } catch (e) {
      _showError('An error occurred. Please try again.');
      setState(() => _saving = false);
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

                    // First Name
                    _buildTextField(
                      controller: _firstNameCtrl,
                      label: 'First Name',
                      hint: 'Enter first name',
                      icon: Icons.person_outline,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 20),

                    // Last Name
                    _buildTextField(
                      controller: _lastNameCtrl,
                      label: 'Last Name',
                      hint: 'Enter last name',
                      icon: Icons.person_outline,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 20),

                    // Email
                    _buildTextField(
                      controller: _emailCtrl,
                      label: 'Email',
                      hint: 'Enter email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
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
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      prefixText: '+966 ',
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
                      icon: Icons.lock_outline,
                      enabled: false,
                      obscureText: true,
                    ),
                    const SizedBox(height: 40),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _saveChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
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
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool enabled = true,
    bool obscureText = false,
    String? prefixText,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: TextStyle(
        color: enabled ? Colors.black87 : Colors.grey,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
        prefixIcon: Icon(icon, color: enabled ? kGreen : Colors.grey),
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}
