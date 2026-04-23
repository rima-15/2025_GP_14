import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:madar_app/services/fcm_token_service.dart';
import 'package:madar_app/services/notification_preferences_service.dart';
import 'package:madar_app/services/notification_service.dart';
import 'package:madar_app/widgets/app_widgets.dart';
import 'package:madar_app/theme/theme.dart';
import 'package:permission_handler/permission_handler.dart';

// ----------------------------------------------------------------------------
// Settings Page
// ----------------------------------------------------------------------------

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  bool _securityExpanded = false;
  bool _notificationPrefsLoading = true;
  bool _notificationPrefsSaving = false;
  bool _systemNotificationStatusLoading = true;
  AuthorizationStatus? _systemNotificationStatus;
  NotificationPreferences _notificationPreferences =
      NotificationPreferences.defaults();

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
  late final TapGestureRecognizer _openSettingsRecognizer;

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
    WidgetsBinding.instance.addObserver(this);
    _openSettingsRecognizer =
        TapGestureRecognizer()
          ..onTap = () async {
            await openAppSettings();
          };
    _initializeNotificationSettings();
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

  bool get _allowNotifications => _notificationPreferences.allowNotifications;
  bool get _systemNotificationsBlocked =>
      _systemNotificationStatus != null &&
      NotificationService.isPermissionBlocked(_systemNotificationStatus!);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _openSettingsRecognizer.dispose();
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _newPasswordFocus.dispose();
    _oldPasswordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _messageManager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _refreshSystemNotificationStatus(syncAppPreferenceIfBlocked: true);
    }
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
      return 'New and confirm passwords do not match';
    }
    return null;
  }

  // ---------- Update Password ----------

  Future<void> _initializeNotificationSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _notificationPrefsLoading = false;
        _systemNotificationStatusLoading = false;
      });
      return;
    }

    try {
      var prefs = await NotificationPreferencesService.load(user.uid);
      final status = await NotificationService.getAuthorizationStatus();

      if (NotificationService.isPermissionBlocked(status)) {
        prefs = await NotificationPreferencesService.disableInAppNotifications(
          user.uid,
        );
      }

      if (!mounted) return;
      setState(() {
        _notificationPreferences = prefs;
        _notificationPrefsLoading = false;
        _systemNotificationStatus = status;
        _systemNotificationStatusLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notificationPrefsLoading = false;
        _systemNotificationStatusLoading = false;
      });
      SnackbarHelper.showError(
        context,
        'Failed to load notification settings. Please try again.',
      );
    }
  }

  Future<void> _refreshSystemNotificationStatus({
    bool syncAppPreferenceIfBlocked = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    try {
      final status = await NotificationService.getAuthorizationStatus();
      NotificationPreferences? syncedPrefs;

      if (syncAppPreferenceIfBlocked &&
          user != null &&
          NotificationService.isPermissionBlocked(status)) {
        syncedPrefs =
            await NotificationPreferencesService.disableInAppNotifications(
              user.uid,
            );
      }

      if (!mounted) return;
      setState(() {
        _systemNotificationStatus = status;
        _systemNotificationStatusLoading = false;
        if (syncedPrefs != null) {
          _notificationPreferences = syncedPrefs;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _systemNotificationStatusLoading = false);
    }
  }

  Future<void> _saveNotificationPreferences(
    NotificationPreferences next, {
    bool requestSystemPermission = false,
  }) async {
    if (_notificationPrefsSaving) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      SnackbarHelper.showError(
        context,
        'Please sign in again to update notification settings.',
      );
      return;
    }

    final previous = _notificationPreferences;
    setState(() {
      _notificationPreferences = next;
      _notificationPrefsSaving = true;
    });

    try {
      await NotificationPreferencesService.save(user.uid, next);

      if (requestSystemPermission && next.allowNotifications) {
        final status = await NotificationService.ensurePermission();

        final permissionGranted =
            NotificationService.isPermissionGranted(status);

        if (permissionGranted) {
          await FcmTokenService.saveToken(user.uid);
        }

        if (!permissionGranted && mounted) {
          final disabledPrefs = next.disableInApp();
          await NotificationPreferencesService.save(user.uid, disabledPrefs);
          setState(() {
            _notificationPreferences = disabledPrefs;
            _systemNotificationStatus = status;
          });
          SnackbarHelper.showError(
            context,
            'Turn on notifications from your device settings to enable them in Madar.',
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notificationPreferences = previous;
      });
      SnackbarHelper.showError(
        context,
        'Failed to update notification settings. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _notificationPrefsSaving = false);
      }
    }
  }

  Future<void> _toggleAllowNotifications(bool value) async {
    if (_systemNotificationsBlocked) return;

    await _saveNotificationPreferences(
      value
          ? _notificationPreferences.enableInApp()
          : _notificationPreferences.disableInApp(),
      requestSystemPermission: value,
    );
  }

  Future<void> _toggleTrackingRequests(bool value) async {
    await _saveNotificationPreferences(
      _notificationPreferences
          .copyWith(trackingRequests: value)
          .syncMasterSwitches(),
    );
  }

  Future<void> _toggleTrackingUpdates(bool value) async {
    await _saveNotificationPreferences(
      _notificationPreferences
          .copyWith(trackingUpdates: value)
          .syncMasterSwitches(),
    );
  }

  Future<void> _toggleMeetingPointInvitations(bool value) async {
    await _saveNotificationPreferences(
      _notificationPreferences
          .copyWith(meetingPointInvitations: value)
          .syncMasterSwitches(),
    );
  }

  Future<void> _toggleMeetingPointUpdates(bool value) async {
    await _saveNotificationPreferences(
      _notificationPreferences
          .copyWith(meetingPointUpdates: value)
          .syncMasterSwitches(),
    );
  }

  Future<void> _toggleRefreshLocationRequests(bool value) async {
    await _saveNotificationPreferences(
      _notificationPreferences
          .copyWith(refreshLocationRequests: value)
          .syncMasterSwitches(),
    );
  }

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

            if (_systemNotificationsBlocked) ...[
              _buildSystemNotificationNotice(),
              const SizedBox(height: 12),
            ],
            _buildNotificationsSection(),

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

  Widget _buildNotificationsSection() {
    if (_notificationPrefsLoading || _systemNotificationStatusLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          border: Border.all(color: Colors.grey[300]!, width: 1),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Loading notification settings...',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AbsorbPointer(
      absorbing: _notificationPrefsSaving,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          border: Border.all(color: Colors.grey[300]!, width: 1),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_outlined,
                    color: AppColors.kGreen,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Allow notifications',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _notificationPrefsSaving
                              ? 'Updating your push notification settings...'
                              : _systemNotificationsBlocked
                              ? 'Turn on notifications in your device settings first.'
                              : 'Receive push notifications',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value:
                        _systemNotificationsBlocked ? false : _allowNotifications,
                    onChanged:
                        _systemNotificationsBlocked
                            ? null
                            : _toggleAllowNotifications,
                    activeColor: AppColors.kGreen,
                    inactiveThumbColor: Colors.grey[400],
                    inactiveTrackColor: Colors.grey[300],
                    trackOutlineColor: WidgetStateProperty.all(
                      Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: _allowNotifications
                  ? Column(
                      children: [
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.grey[300],
                        ),
                        _buildPreferenceOption(
                          title: 'Tracking Requests',
                          subtitle:
                              'New track requests that need your response.',
                          value: _notificationPreferences.trackingRequests,
                          onChanged: _toggleTrackingRequests,
                        ),
                        _buildPreferenceOption(
                          title: 'Tracking Updates',
                          subtitle:
                              'Accepted, declined, started, completed, and cancelled tracking updates.',
                          value: _notificationPreferences.trackingUpdates,
                          onChanged: _toggleTrackingUpdates,
                        ),
                        _buildPreferenceOption(
                          title: 'Meeting Point Invitations',
                          subtitle:
                              'Invitations to join a shared meeting point.',
                          value:
                              _notificationPreferences.meetingPointInvitations,
                          onChanged: _toggleMeetingPointInvitations,
                        ),
                        _buildPreferenceOption(
                          title: 'Meeting Point Updates',
                          subtitle:
                              'Meeting point started, completed, cancelled, and arrival reminders.',
                          value: _notificationPreferences.meetingPointUpdates,
                          onChanged: _toggleMeetingPointUpdates,
                        ),
                        _buildPreferenceOption(
                          title: 'Refresh Location Requests',
                          subtitle:
                              'Manual and system reminders to refresh your location.',
                          value:
                              _notificationPreferences.refreshLocationRequests,
                          onChanged: _toggleRefreshLocationRequests,
                          isLast: true,
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemNotificationNotice() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[700],
            height: 1.4,
          ),
          children: [
            const TextSpan(
              text:
                  'Notifications are turned off in your device settings. Turn them on there to manage them in Madar. ',
            ),
            TextSpan(
              text: 'Open Settings',
              recognizer: _openSettingsRecognizer,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.kGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferenceOption({
    required String title,
    String? subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
        ),
        if (!isLast)
          Divider(height: 1, thickness: 1, color: Colors.grey[200]),
      ],
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
