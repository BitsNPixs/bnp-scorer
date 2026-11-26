import 'dart:convert';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/reminders.dart';
import 'ids.dart';
import 'push_messages.dart';

/// Small per-device preferences. Values are stored by name, so reordering an
/// enum never changes what a saved setting means.
class AppSettings {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static const themeModeKey = 'bnp_scorer.themeMode';
  static const remindersKey = 'bnp_scorer.reminders';
  static const reminderLeadKey = 'bnp_scorer.reminderLead';
  static const watchedRemindersKey = 'bnp_scorer.watchedReminders';
  static const pushKindsKey = 'bnp_scorer.pushKinds';
  static const deviceIdKey = 'bnp_scorer.deviceId';
  static const pushRegisteredKey = 'bnp_scorer.pushRegistered';

  /// Follows the phone until the scorer picks light or dark.
  ThemeMode get themeMode {
    final stored = _prefs.getString(themeModeKey);
    return ThemeMode.values.firstWhere((m) => m.name == stored, orElse: () => ThemeMode.system);
  }

  Future<void> setThemeMode(ThemeMode mode) => _prefs.setString(themeModeKey, mode.name);

  /// Reminders before this phone's own matches: null until the user has been
  /// offered them, so the offer shows once.
  bool? get remindersOn => switch (_prefs.getString(remindersKey)) {
        'on' => true,
        'off' => false,
        _ => null,
      };

  Future<void> setRemindersOn(bool on) => _prefs.setString(remindersKey, on ? 'on' : 'off');

  ReminderLead get reminderLead => ReminderLead.byName(_prefs.getString(reminderLeadKey));

  Future<void> setReminderLead(ReminderLead lead) => _prefs.setString(reminderLeadKey, lead.name);

  /// Other people's matches this phone asked to be reminded of. A corrupt
  /// entry is dropped rather than losing the rest.
  List<WatchedReminder> get watchedReminders {
    final stored = _prefs.getStringList(watchedRemindersKey) ?? const [];
    return [
      for (final text in stored) ?_readWatched(text),
    ];
  }

  Future<void> setWatchedReminders(List<WatchedReminder> watched) =>
      _prefs.setStringList(watchedRemindersKey, [for (final w in watched) jsonEncode(w.toJson())]);

  /// The pushes this phone asked for. Empty until the user turns one on.
  Set<PushKind> get pushKinds {
    final names = _prefs.getStringList(pushKindsKey) ?? const [];
    return {for (final k in PushKind.values) if (names.contains(k.name)) k};
  }

  Future<void> setPushKinds(Set<PushKind> kinds) =>
      _prefs.setStringList(pushKindsKey, [for (final k in kinds) k.name]);

  /// This install's id, made on first use: names its push registration, so a
  /// new token replaces the old one instead of piling up.
  String get deviceId {
    final stored = _prefs.getString(deviceIdKey);
    if (stored != null) return stored;
    final id = newId();
    _prefs.setString(deviceIdKey, id);
    return id;
  }

  /// A fresh [deviceId], for when the old registration belongs to someone
  /// else and cannot be taken over.
  Future<String> renewDeviceId() async {
    final id = newId();
    await _prefs.setString(deviceIdKey, id);
    return id;
  }

  /// Whether this phone's push registration is in Firestore, so signing out
  /// or turning every kind off knows to remove it.
  bool get pushRegistered => _prefs.getBool(pushRegisteredKey) ?? false;

  Future<void> setPushRegistered(bool registered) => _prefs.setBool(pushRegisteredKey, registered);

  static WatchedReminder? _readWatched(String text) {
    try {
      return WatchedReminder.fromJson(jsonDecode(text) as Json);
    } on Object catch (e) {
      debugPrint('Skipping an unreadable reminder: $e');
      return null;
    }
  }
}
