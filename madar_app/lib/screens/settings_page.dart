import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';

// ----------------------------------------------------------------------------
// Settings Page
// ----------------------------------------------------------------------------

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;
  bool _locationEnabled = true;
  bool _securityExpanded = false;

  // Password form controllers
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _updating = false;

  // Password validation states
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;
  bool _isDifferentFromOld = false;

  final _newPasswordFocus = FocusNode();
  final _oldPasswordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  bool get _allNewPasswordRequirementsMet =>
      _hasMinLength &&
      _hasUppercase &&
      _hasLowercase &&
      _hasNumber &&
      _hasSpecialChar &&
      _isDifferentFromOld;

  bool get _confirmPasswordMatches =>
      _confirmPasswordCtrl.text.isNotEmpty &&
      _confirmPasswordCtrl.text == _newPasswordCtrl.text;

  final _messageManager = TimedMessageManager();

  @override
  void initState() {
    super.initState();
    _newPasswordCtrl.addListener(_checkPasswordRequirements);
    _oldPasswordCtrl.addListener(_checkPasswordRequirements);
    _confirmPasswordCtrl.addListener(_onConfirmPasswordChange);
    _newPasswordFocus.addListener(_onNewPasswordFocusChange);
    _oldPasswordFocus.addListener(_onOldPasswordFocusChange);
    _confirmPasswordFocus.addListener(_onConfirmPasswordFocusChange);

    _messageManager.setUpdateCallback(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _newPasswordFocus.dispose();
    _oldPasswordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _messageManager.dispose();
    super.dispose();
  }

  // ---------- Focus Listeners ----------

  void _onNewPasswordFocusChange() {
    if (!_newPasswordFocus.hasFocus) {
      _formKey.currentState?.validate();
    }
  }

  void _onOldPasswordFocusChange() {
    if (!_oldPasswordFocus.hasFocus) {
      _checkPasswordRequirements();
      _formKey.currentState?.validate();
    }
  }

  void _onConfirmPasswordFocusChange() {
    if (!_confirmPasswordFocus.hasFocus) {
      _formKey.currentState?.validate();
    }
  }

  void _onConfirmPasswordChange() {
    setState(() {});
    if (_confirmPasswordCtrl.text.isNotEmpty) {
      _formKey.currentState?.validate();
    }
  }

  // ---------- Password Requirements Check ----------

  void _checkPasswordRequirements() {
    final password = _newPasswordCtrl.text;
    final oldPassword = _oldPasswordCtrl.text;

    setState(() {
      _hasMinLength = password.length >= 8;
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasNumber = password.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = password.contains(RegExp(r'[^A-Za-z0-9 ]'));

      if (password.isEmpty || oldPassword.isEmpty) {
        _isDifferentFromOld = false;
      } else {
        _isDifferentFromOld = password != oldPassword;
      }
    });
  }

  // ---------- Validation ----------

  String? _validateOldPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Old password is required';
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'New password is required';
    }
    if (value == _oldPasswordCtrl.text && _oldPasswordCtrl.text.isNotEmpty) {
      return '';
    }
    if (!_hasMinLength ||
        !_hasUppercase ||
        !_hasLowercase ||
        !_hasNumber ||
        !_hasSpecialChar) {
      return '';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _newPasswordCtrl.text) {
      return 'q';
    }
    return null;
  }

  // ---------- Update Password ----------

  Future<void> _updatePassword() async {
    _messageManager.clearMessage();

    if (!_formKey.currentState!.validate()) {
      final oldPassword = _oldPasswordCtrl.text;
      final newPassword = _newPasswordCtrl.text;
      final confirmPassword = _confirmPasswordCtrl.text;

      if (_validateOldPassword(oldPassword) != null) {
        _oldPasswordFocus.requestFocus();
      } else if (_validateNewPassword(newPassword) != null) {
        _newPasswordFocus.requestFocus();
      } else if (_validateConfirmPassword(confirmPassword) != null) {
        _confirmPasswordFocus.requestFocus();
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _updating = true);

    try {
      final email = user.email!;
      final credential = EmailAuthProvider.credential(
        email: email,
        password: _oldPasswordCtrl.text.trim(),
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(_newPasswordCtrl.text.trim());

      if (mounted) {
        SnackbarHelper.showSuccess(context, 'Password updated successfully!');

        _oldPasswordCtrl.clear();
        _newPasswordCtrl.clear();
        _confirmPasswordCtrl.clear();

        setState(() {
          _updating = false;
          _securityExpanded = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _updating = false);

      if (e.code == 'wrong-password') {
        _messageManager.showError('Old password is incorrect');
      } else if (e.code == 'weak-password') {
        _messageManager.showError('New password is too weak');
      } else if (e.code == 'requires-recent-login') {
        _messageManager.showError('Please sign in again to change password');
      } else {
        _messageManager.showError('Failed to update password');
      }
    } catch (e) {
      setState(() => _updating = false);
      _messageManager.showError('An error occurred. Please try again.');
    }
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final horizontalPadding = isSmallScreen ? 20.0 : 24.0;

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
          'Settings',
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
      body: ScrollConfiguration(
        behavior: ScrollBehavior().copyWith(
          physics: const ClampingScrollPhysics(),
        ),
        child: ListView(
          padding: EdgeInsets.all(horizontalPadding),
          children: [
            // Preferences Section
            _buildSectionTitle('Preferences'),
            const SizedBox(height: 12),

            _buildSwitchTile(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Receive push notifications',
              value: _notificationsEnabled,
              onChanged: (val) => setState(() => _notificationsEnabled = val),
            ),
            const SizedBox(height: 12),

            _buildSwitchTile(
              icon: Icons.location_on_outlined,
              title: 'Location Services',
              subtitle: 'Allow location access',
              value: _locationEnabled,
              onChanged: (val) => setState(() => _locationEnabled = val),
            ),

            const SizedBox(height: 32),

            // Privacy and Security Section
            _buildSectionTitle('Privacy and Security'),
            const SizedBox(height: 12),

            _buildSecuritySection(),
          ],
        ),
      ),
    );
  }

  // ---------- UI Builders ----------

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.kGreen, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.kGreen,
            inactiveThumbColor: Colors.grey[400],
            inactiveTrackColor: Colors.grey[300],
            trackOutlineColor: WidgetStateProperty.all(Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildSecuritySection() {
    return Column(
      children: [
        // Change Password header (collapsible)
        InkWell(
          onTap: () => setState(() => _securityExpanded = !_securityExpanded),
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              border: Border.all(color: Colors.grey[300]!, width: 1),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  color: AppColors.kGreen,
                  size: 24,
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Change Password',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Icon(
                  _securityExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey[600],
                ),
              ],
            ),
          ),
        ),

        // Expandable password change form
        if (_securityExpanded) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              border: Border.all(color: Colors.grey[300]!, width: 1),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Old Password
                  StyledTextField(
                    controller: _oldPasswordCtrl,
                    label: 'Old Password',
                    hint: 'Enter old password',
                    obscureText: _obscureOld,
                    validator: _validateOldPassword,
                    focusNode: _oldPasswordFocus,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureOld ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey.shade600,
                      ),
                      onPressed: () =>
                          setState(() => _obscureOld = !_obscureOld),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // New Password
                  StyledTextField(
                    controller: _newPasswordCtrl,
                    label: 'New Password',
                    hint: 'Enter new password',
                    obscureText: _obscureNew,
                    validator: _validateNewPassword,
                    focusNode: _newPasswordFocus,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscureNew
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () =>
                              setState(() => _obscureNew = !_obscureNew),
                        ),
                        if (_allNewPasswordRequirementsMet) ...[
                          const SizedBox(width: 8),
                          const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(
                              Icons.check_circle,
                              color: AppColors.kGreen,
                              size: 20,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Password Requirements
                  const SizedBox(height: 8),
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
                  _buildRequirementItem(
                    'New password not same as old password',
                    _isDifferentFromOld,
                  ),
                  const SizedBox(height: 16),

                  // Confirm Password
                  StyledTextField(
                    controller: _confirmPasswordCtrl,
                    label: 'Confirm Password',
                    hint: 'Re-enter new password',
                    obscureText: _obscureConfirm,
                    validator: _validateConfirmPassword,
                    focusNode: _confirmPasswordFocus,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                        if (_confirmPasswordMatches) ...[
                          const SizedBox(width: 8),
                          const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(
                              Icons.check_circle,
                              color: AppColors.kGreen,
                              size: 20,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Update Password Button
                  PrimaryButton(
                    text: 'Update Password',
                    onPressed: _updatePassword,
                    isLoading: _updating,
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
        ],
      ],
    );
  }

  Widget _buildRequirementItem(String text, bool isMet) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.circle_outlined,
            color: isMet ? AppColors.kGreen : Colors.grey,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: isMet ? AppColors.kGreen : Colors.grey,
                fontSize: 13,
                fontWeight: isMet ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
