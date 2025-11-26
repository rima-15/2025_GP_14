import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// COLORS - Define all your app colors here
// ============================================================================
class AppColors {
  static const kGreen = Color(0xFF787E65);
  static const kError = Color(0xFFC62828);
  static const kErrorLight = Color(0xFFFEF2F2);
  static const kErrorBorder = Color(0xFFF5B8B8);
  static const kSuccess = Color.fromARGB(255, 104, 114, 134);
}

// ============================================================================
// UNIFIED LOADING WIDGETS
// ============================================================================

/// Full-page loading indicator - Use when the entire page content is loading
/// Example: Profile page loading user data, Home page initial load
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

/// Inline loading indicator - Use for buttons or small inline loading states
/// Example: "Save Changes" button, "Update Password" button
class InlineLoadingIndicator extends StatelessWidget {
  final double? size; // Optional custom size

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
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        );
      },
    );
  }
}

// ============================================================================
// ERROR MESSAGE WIDGET (Bottom of page)
// ============================================================================
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

// ============================================================================
// SNACKBAR HELPERS
// ============================================================================
class SnackbarHelper {
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
        backgroundColor: const Color(0xFFF0F7E8), // Same as SuccessMessageBox
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(
            color: Color(0xFFB8C9A0), // Same border as SuccessMessageBox
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
        elevation: 0,
      ),
    );
  }

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
        backgroundColor: AppColors.kErrorLight, // Same as ErrorMessageBox
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(
            color: AppColors.kErrorBorder, // Same border as ErrorMessageBox
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
        elevation: 0,
      ),
    );
  }
}

// ============================================================================
// CONFIRMATION DIALOGS
// ============================================================================
class ConfirmationDialog {
  // Delete confirmation (Destructive action)
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

  // Positive confirmation (Non-destructive action) - like logout
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

// ============================================================================
// STYLED TEXT FIELD (with consistent error styling)
// ============================================================================
class StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final String? prefixText;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final bool obscureText; // ADD THIS
  final Widget? suffixIcon; // ADD THIS
  final String? obscuringCharacter; // ADD THIS
  final FocusNode? focusNode; // ADD THIS FOR AUTO-FOCUS

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
    this.obscureText = false, // ADD THIS
    this.suffixIcon, // ADD THIS
    this.obscuringCharacter, // ADD THIS
    this.focusNode, // ADD THIS FOR AUTO-FOCUS
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode, // ADD THIS FOR AUTO-FOCUS
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText, // ADD THIS
      obscuringCharacter: obscuringCharacter ?? '•', // ADD THIS
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
        suffixIcon: suffixIcon, // ADD THIS
        labelStyle: TextStyle(color: enabled ? null : Colors.grey[600]),
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey[200],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), // CHANGE from 12 to 10
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), // CHANGE from 12 to 10
          borderSide: const BorderSide(color: Colors.black12, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), // CHANGE from 12 to 10
          borderSide: const BorderSide(color: AppColors.kGreen, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), // CHANGE from 12 to 10
          borderSide: const BorderSide(color: AppColors.kError, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), // CHANGE from 12 to 10
          borderSide: const BorderSide(color: AppColors.kError, width: 1.8),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), // CHANGE from 12 to 10
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        errorStyle: const TextStyle(
          color: AppColors.kError,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

// ============================================================================
// TIMED ERROR STATE MANAGER (for bottom error messages)
// ============================================================================
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

// ============================================================================
// SUCCESS MESSAGE WIDGET (Bottom of page)
// ============================================================================
class SuccessMessageBox extends StatelessWidget {
  final String message;

  const SuccessMessageBox({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7E8), // Light green background
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFB8C9A0), // Light green border
          width: 1,
        ),
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

// ============================================================================
// TIMED MESSAGE STATE MANAGER (for bottom messages)
// ============================================================================
enum MessageType { error, success, none }

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
