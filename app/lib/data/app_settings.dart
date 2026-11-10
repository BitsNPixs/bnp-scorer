import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small per-device preferences. Values are stored by name, so reordering an
/// enum never changes what a saved setting means.
class AppSettings {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static const themeModeKey = 'bnp_scorer.themeMode';

  /// Follows the phone until the scorer picks light or dark.
  ThemeMode get themeMode {
    final stored = _prefs.getString(themeModeKey);
    return ThemeMode.values.firstWhere((m) => m.name == stored, orElse: () => ThemeMode.system);
  }

  Future<void> setThemeMode(ThemeMode mode) => _prefs.setString(themeModeKey, mode.name);
}
