import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:madar_app/screens/welcome_page.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';

// ----------------------------------------------------------------------------
// Profile Page
// ----------------------------------------------------------------------------

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

  final _firstNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _phoneFocus = FocusNode();

  bool _loading = true;
  bool _saving = false;
  bool _hasChanges = false;

  String _originalFirstName = '';
  String _originalLastName = '';
  String _originalEmail = '';
  String _originalPhone = '';

  final _messageManager = TimedMessageManager();

  @override
  void initState() {
    super.initState();
    _loadUserData();

    _firstNameCtrl.addListener(_checkChanges);
    _lastNameCtrl.addListener(_checkChanges);
    _phoneCtrl.addListener(_checkChanges);

    _messageManager.setUpdateCallback(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _phoneFocus.dispose();
    _messageManager.dispose();
    super.dispose();
  }

  // ---------- Change Detection ----------

  void _checkChanges() {
    final hasChanges =
        _firstNameCtrl.text != _originalFirstName ||
        _lastNameCtrl.text != _originalLastName ||
        _phoneCtrl.text != _originalPhone;

    if (hasChanges != _hasChanges) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  // ---------- Validation ----------

  String? _validateFirstName(String value) {
    if (value.isEmpty) {
      return 'First name is required';
    } else if (value.length < 2) {
      return 'Must be at least 2 characters';
    } else if (!RegExp(r'^[A-Za-z]').hasMatch(value)) {
      return 'Must start with a letter';
    } else if (!RegExp(r'^[A-Za-z][A-Za-z0-9-]{1,19}$').hasMatch(value)) {
      return 'Only letters, numbers, and "-" allowed';
    }
    return null;
  }

  String? _validateLastName(String value) {
    if (value.isEmpty) {
      return 'Last name is required';
    } else if (value.length < 2) {
      return 'Must be at least 2 characters';
    } else if (!RegExp(r'^[A-Za-z]').hasMatch(value)) {
      return 'Must start with a letter';
    } else if (!RegExp(r'^[A-Za-z][A-Za-z0-9-]{1,19}$').hasMatch(value)) {
      return 'Only letters, numbers, and "-" allowed';
    }
    return null;
  }

  String? _validatePhone(String value) {
    if (value.isEmpty) {
      return 'Phone number is required';
    } else if (!RegExp(r'^\d{9}$').hasMatch(value)) {
      return 'Must be 9 digits';
    }
    return null;
  }

  // ---------- Data Loading ----------

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
        _messageManager.showError('Failed to load profile data');
        setState(() => _loading = false);
      }
    }
  }

  // ---------- Save Changes ----------

  Future<void> _saveChanges() async {
    _messageManager.clearMessage();

    if (!_formKey.currentState!.validate()) {
      final firstName = _firstNameCtrl.text;
      final lastName = _lastNameCtrl.text;
      final phone = _phoneCtrl.text;

      if (_validateFirstName(firstName) != null) {
        _firstNameFocus.requestFocus();
      } else if (_validateLastName(lastName) != null) {
        _lastNameFocus.requestFocus();
      } else if (_validatePhone(phone) != null) {
        _phoneFocus.requestFocus();
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    try {
      final newPhone = '+966${_phoneCtrl.text.trim()}';
      final oldPhone = '+966$_originalPhone';

      // Check if phone changed and if new phone exists
      if (newPhone != oldPhone) {
        final phoneQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: newPhone)
            .get();

        if (phoneQuery.docs.isNotEmpty &&
            phoneQuery.docs.first.id != user.uid) {
          setState(() => _saving = false);
          _messageManager.showError('Phone number already in use');
          return;
        }
      }

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
            'firstName': _firstNameCtrl.text.trim(),
            'lastName': _lastNameCtrl.text.trim(),
            'phone': newPhone,
          });

      _originalFirstName = _firstNameCtrl.text.trim();
      _originalLastName = _lastNameCtrl.text.trim();
      _originalPhone = _phoneCtrl.text.trim();

      if (mounted) {
        SnackbarHelper.showSuccess(context, 'Profile updated successfully!');
        setState(() {
          _saving = false;
          _hasChanges = false;
        });
      }
    } catch (e) {
      setState(() => _saving = false);
      _messageManager.showError('An error occurred. Please try again.');
    }
  }

  // ---------- Delete Account ----------

  Future<void> _deleteAccount() async {
    final confirmed = await ConfirmationDialog.showDeleteConfirmation(
      context,
      title: 'Delete Account',
      message:
          'Are you sure you want to delete your account? This action cannot be undone.',
    );

    if (!confirmed) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();
      await user.delete();

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _messageManager.showError(
          'Please sign in again to delete your account',
        );
      } else {
        _messageManager.showError('Failed to delete account');
      }
    } catch (e) {
      _messageManager.showError('An error occurred');
    }
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final horizontalPadding = isSmallScreen ? 20.0 : 24.0;
    final avatarSize = isSmallScreen ? 80.0 : 100.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.kGreen),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: AppColors.kGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey[300], height: 1),
        ),
      ),
      body: _loading
          ? const AppLoadingIndicator()
          : SingleChildScrollView(
              padding: EdgeInsets.all(horizontalPadding),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Profile Avatar
                    Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        color: AppColors.kGreen.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person,
                        size: avatarSize * 0.5,
                        color: AppColors.kGreen,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // First Name
                    StyledTextField(
                      controller: _firstNameCtrl,
                      focusNode: _firstNameFocus,
                      label: 'First Name',
                      hint: 'Enter first name',
                      validator: (v) => _validateFirstName(v ?? ''),
                    ),
                    const SizedBox(height: 20),

                    // Last Name
                    StyledTextField(
                      controller: _lastNameCtrl,
                      focusNode: _lastNameFocus,
                      label: 'Last Name',
                      hint: 'Enter last name',
                      validator: (v) => _validateLastName(v ?? ''),
                    ),
                    const SizedBox(height: 20),

                    // Email (Read-only)
                    StyledTextField(
                      controller: _emailCtrl,
                      label: 'Email',
                      hint: '',
                      enabled: false,
                    ),
                    const SizedBox(height: 20),

                    // Phone
                    StyledTextField(
                      controller: _phoneCtrl,
                      focusNode: _phoneFocus,
                      label: 'Phone Number',
                      hint: 'Enter 9 digits',
                      keyboardType: TextInputType.number,
                      prefixText: '+966 ',
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(9),
                      ],
                      validator: (v) => _validatePhone(v ?? ''),
                    ),
                    const SizedBox(height: 40),

                    // Save Button
                    PrimaryButton(
                      text: 'Save Changes',
                      onPressed: _saveChanges,
                      isLoading: _saving,
                      enabled: _hasChanges,
                    ),
                    const SizedBox(height: 16),

                    // Delete Account Button
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
                            color: AppColors.kError,
                          ),
                        ),
                      ),
                    ),

                    // Message box
                    if (_messageManager.hasMessage) ...[
                      const SizedBox(height: 16),
                      _messageManager.type == MessageType.error
                          ? ErrorMessageBox(message: _messageManager.message)
                          : SuccessMessageBox(message: _messageManager.message),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
