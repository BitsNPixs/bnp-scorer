import 'package:flutter/material.dart';

/// Soft filled field used across forms.
InputDecoration fieldDecoration(BuildContext context, String hint, {IconData? icon, Widget? suffix}) {
  final radius = BorderRadius.circular(14);
  return InputDecoration(
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon),
    suffixIcon: suffix,
    filled: true,
    fillColor: Theme.of(context).colorScheme.surfaceContainer,
    border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}
