import 'dart:convert';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// JSON documents in shared preferences: one key per document, plus an index
/// of ids. A corrupt document is skipped so it cannot take the whole list down.
class LocalDocuments<T> {
  LocalDocuments({
    required SharedPreferences prefs,
    required String indexKey,
    required String keyPrefix,
    required T Function(Json json) fromJson,
    required Json Function(T value) toJson,
  })  : _prefs = prefs,
        _indexKey = indexKey,
        _keyPrefix = keyPrefix,
        _fromJson = fromJson,
        _toJson = toJson;

  final SharedPreferences _prefs;
  final String _indexKey;
  final String _keyPrefix;
  final T Function(Json json) _fromJson;
  final Json Function(T value) _toJson;

  List<String> get _ids => _prefs.getStringList(_indexKey) ?? const [];

  String _key(String id) => '$_keyPrefix$id';

  List<T> readAll() => [
        for (final id in _ids) ?read(id),
      ];

  Future<void> save(String id, T value) async {
    await _prefs.setString(_key(id), jsonEncode(_toJson(value)));
    final ids = _ids;
    if (!ids.contains(id)) await _prefs.setStringList(_indexKey, [...ids, id]);
  }

  Future<void> delete(String id) async {
    await _prefs.remove(_key(id));
    await _prefs.setStringList(_indexKey, [..._ids.where((i) => i != id)]);
  }

  /// One document, or null if it is missing or unreadable.
  T? read(String id) {
    final raw = _prefs.getString(_key(id));
    if (raw == null) return null;
    try {
      return _fromJson(jsonDecode(raw) as Json);
    } on Object catch (e) {
      debugPrint('Skipping unreadable document $id: $e');
      return null;
    }
  }
}
