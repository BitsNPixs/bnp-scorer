import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

void showMessage(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? AppColors.wicket : null,
      duration: const Duration(seconds: 2),
    ));
}

/// Shows the error from a scoring action, if any. Returns true on success.
bool reportResult(BuildContext context, String? error) {
  if (error == null) return true;
  HapticFeedback.vibrate();
  showMessage(context, error, isError: true);
  return false;
}
