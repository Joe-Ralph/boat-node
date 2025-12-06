import 'package:flutter/material.dart';

class UiUtils {
  static const Color _zinc900 = Color(0xFF18181B);
  static final Color _errorRed = Colors.red[800]!;
  static const Color _successGreen = Color(0xFF22C55E);

  static void showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isSuccess = false,
    Color? backgroundColor,
    Duration? duration,
  }) {
    // Hide any current snackbar before showing the new one
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    Color finalBackgroundColor =
        backgroundColor ??
        (isError ? _errorRed : (isSuccess ? _successGreen : _zinc900));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: finalBackgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }
}
