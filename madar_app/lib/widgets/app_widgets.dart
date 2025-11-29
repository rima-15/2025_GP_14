import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:madar_app/theme/theme.dart';

// ----------------------------------------------------------------------------
// App Colors
// ----------------------------------------------------------------------------
class AppColors {
  static const kGreen = Color(0xFF787E65);
  static const kError = Color(0xFFC62828);
  static const kErrorLight = Color(0xFFFEF2F2);
  static const kErrorBorder = Color(0xFFF5B8B8);
  static const kSuccess = Color(0xFF687286);
  static const kSuccessLight = Color(0xFFF0F7E8);
  static const kSuccessBorder = Color(0xFFB8C9A0);
}

// ----------------------------------------------------------------------------
// Loading Indicators
// ----------------------------------------------------------------------------

/// Full-page loading indicator for initial page loads
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircularProgressIndicator(
        color: AppColors.kGreen,
        backgroundColor: AppColors.kGreen.withOpacity(0.2),
      ),
    );
  }
}

/// Inline loading indicator for buttons and small spaces
class InlineLoadingIndicator extends StatelessWidget {
  final double? size;

  const InlineLoadingIndicator({super.key, this.size});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final indicatorSize =
            size ?? (constraints.maxHeight * 0.6).clamp(16.0, 24.0);
        return SizedBox(
          width: indicatorSize,
          height: indicatorSize,
          child: const CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------
// Message Boxes
// ----------------------------------------------------------------------------

/// Error message box displayed at bottom of forms
class ErrorMessageBox extends StatelessWidget {
  final String message;

  const ErrorMessageBox({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.kErrorLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.kErrorBorder, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.kError),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.kError,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Success message box displayed at bottom of forms
class SuccessMessageBox extends StatelessWidget {
  final String message;

  const SuccessMessageBox({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.kSuccessLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.kSuccessBorder, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.kGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.kGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Snackbar Helpers
// ----------------------------------------------------------------------------
class SnackbarHelper {
  /// Shows a success snackbar with green styling
  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.kGreen),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.kGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.kSuccessLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.kSuccessBorder, width: 1),
        ),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
        elevation: 0,
      ),
    );
  }

  /// Shows an error snackbar with red styling
  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.kError),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.kError,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.kErrorLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.kErrorBorder, width: 1),
        ),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
        elevation: 0,
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Confirmation Dialogs
// ----------------------------------------------------------------------------
class ConfirmationDialog {
  /// Shows a delete/destructive action confirmation dialog
  static Future<bool> showDeleteConfirmation(
    BuildContext context, {
    required String title,
    required String message,
    String cancelText = 'Cancel',
    String confirmText = 'Delete',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        content: Text(message, style: const TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey[200],
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              cancelText,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.kError,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              confirmText,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );

    return result ?? false;
  }

  /// Shows a positive/non-destructive confirmation dialog (e.g., logout)
  static Future<bool> showPositiveConfirmation(
    BuildContext context, {
    required String title,
    required String message,
    String cancelText = 'Cancel',
    String confirmText = 'Confirm',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        content: Text(message, style: const TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey[200],
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              cancelText,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.kGreen,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              confirmText,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );

    return result ?? false;
  }
}

// ----------------------------------------------------------------------------
// Styled Text Field
// ----------------------------------------------------------------------------

/// Consistent styled text field used across the app
class StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final String? prefixText;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? obscuringCharacter;
  final FocusNode? focusNode;

  const StyledTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.validator,
    this.keyboardType,
    this.prefixText,
    this.inputFormatters,
    this.enabled = true,
    this.obscureText = false,
    this.suffixIcon,
    this.obscuringCharacter,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      obscuringCharacter: obscuringCharacter ?? '•',
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validator,
      style: TextStyle(
        color: enabled ? Colors.black87 : Colors.grey[700],
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefixText,
        suffixIcon: suffixIcon,
        labelStyle: TextStyle(color: enabled ? null : Colors.grey[600]),
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey[200],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: const BorderSide(color: Colors.black12, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.kGreen, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.kError, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.kError, width: 1.8),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        errorStyle: AppTextStyles.error,
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Primary Button
// ----------------------------------------------------------------------------

// Fixed button height to prevent jumping during loading state
const double _kButtonHeight = 50.0;
const double _kLoadingIndicatorSize = 22.0;

/// Consistent primary button used across the app
/// Has fixed height to prevent size changes during loading
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool enabled;

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: _kButtonHeight,
      child: ElevatedButton(
        onPressed: (isLoading || !enabled) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.kGreen,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          elevation: 0,
          // Gray when loading or disabled (original behavior)
          disabledBackgroundColor: Colors.grey[300],
          disabledForegroundColor: Colors.grey[600],
        ),
        child: isLoading
            ? const SizedBox(
                width: _kLoadingIndicatorSize,
                height: _kLoadingIndicatorSize,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(text, style: AppTextStyles.button),
      ),
    );
  }
}

/// Consistent outlined button used across the app
/// Has fixed height to prevent size changes during loading
class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const SecondaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: _kButtonHeight,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.kGreen, width: 2),
          foregroundColor: AppColors.kGreen,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: _kLoadingIndicatorSize,
                height: _kLoadingIndicatorSize,
                child: CircularProgressIndicator(
                  color: AppColors.kGreen,
                  strokeWidth: 2.5,
                ),
              )
            : Text(text, style: AppTextStyles.button),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Message State Managers
// ----------------------------------------------------------------------------

enum MessageType { error, success, none }

/// Manages timed messages (errors/success) that auto-clear
class TimedMessageManager {
  String _message = '';
  MessageType _type = MessageType.none;
  VoidCallback? _onUpdate;

  String get message => _message;
  MessageType get type => _type;
  bool get hasMessage => _message.isNotEmpty;

  void setUpdateCallback(VoidCallback callback) {
    _onUpdate = callback;
  }

  void showError(
    String message, {
    Duration duration = const Duration(seconds: 5),
  }) {
    _message = message;
    _type = MessageType.error;
    _onUpdate?.call();

    Future.delayed(duration, () {
      clearMessage();
    });
  }

  void showSuccess(
    String message, {
    Duration duration = const Duration(seconds: 5),
  }) {
    _message = message;
    _type = MessageType.success;
    _onUpdate?.call();

    Future.delayed(duration, () {
      clearMessage();
    });
  }

  void clearMessage() {
    _message = '';
    _type = MessageType.none;
    _onUpdate?.call();
  }

  void dispose() {
    _onUpdate = null;
  }
}

/// Legacy error-only manager for backwards compatibility
class TimedErrorManager {
  String _errorMessage = '';
  VoidCallback? _onUpdate;

  String get errorMessage => _errorMessage;

  void setUpdateCallback(VoidCallback callback) {
    _onUpdate = callback;
  }

  void showError(
    String message, {
    Duration duration = const Duration(seconds: 5),
  }) {
    _errorMessage = message;
    _onUpdate?.call();

    Future.delayed(duration, () {
      clearError();
    });
  }

  void clearError() {
    _errorMessage = '';
    _onUpdate?.call();
  }

  void dispose() {
    _onUpdate = null;
  }
}
