import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'match_record.dart';
import 'match_repository.dart';

/// Offline-first storage on the device. Each match is one JSON document.
class LocalMatchRepository implements MatchRepository {
  LocalMatchRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _indexKey = 'bnp_scorer.matchIds';
  static String _key(String id) => 'bnp_scorer.match.$id';

  List<String> get _ids => _prefs.getStringList(_indexKey) ?? const [];

  @override
  Future<List<MatchRecord>> loadAll() async {
    final records = <MatchRecord>[];
    for (final id in _ids) {
      final record = _read(id);
      if (record != null) records.add(record);
    }
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return records;
  }

  @override
  Future<MatchRecord?> load(String id) async => _read(id);

  @override
  Future<void> save(MatchRecord record) async {
    await _prefs.setString(_key(record.id), jsonEncode(record.toJson()));
    final ids = _ids;
    if (!ids.contains(record.id)) {
      await _prefs.setStringList(_indexKey, [...ids, record.id]);
    }
  }

  @override
  Future<void> delete(String id) async {
    await _prefs.remove(_key(id));
    await _prefs.setStringList(_indexKey, [..._ids.where((i) => i != id)]);
  }

  MatchRecord? _read(String id) {
    final raw = _prefs.getString(_key(id));
    if (raw == null) return null;
    try {
      return MatchRecord.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object catch (e) {
      // A corrupt record must not take the whole match list down.
      debugPrint('Skipping unreadable match $id: $e');
      return null;
    }
  }
}
