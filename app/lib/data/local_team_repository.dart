import 'dart:convert';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'team_repository.dart';

/// Saved squads on the device. Each team is one JSON document.
class LocalTeamRepository implements TeamRepository {
  LocalTeamRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _indexKey = 'bnp_scorer.teamIds';
  static String _key(String id) => 'bnp_scorer.team.$id';

  List<String> get _ids => _prefs.getStringList(_indexKey) ?? const [];

  @override
  Future<List<Team>> loadAll() async {
    final teams = <Team>[];
    for (final id in _ids) {
      final team = _read(id);
      if (team != null) teams.add(team);
    }
    teams.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return teams;
  }

  @override
  Future<void> save(Team team) async {
    await _prefs.setString(_key(team.id), jsonEncode(team.toJson()));
    final ids = _ids;
    if (!ids.contains(team.id)) {
      await _prefs.setStringList(_indexKey, [...ids, team.id]);
    }
  }

  @override
  Future<void> delete(String id) async {
    await _prefs.remove(_key(id));
    await _prefs.setStringList(_indexKey, [..._ids.where((i) => i != id)]);
  }

  Team? _read(String id) {
    final raw = _prefs.getString(_key(id));
    if (raw == null) return null;
    try {
      return Team.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object catch (e) {
      // A corrupt record must not take the whole team list down.
      debugPrint('Skipping unreadable team $id: $e');
      return null;
    }
  }
}
