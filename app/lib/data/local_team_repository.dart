import 'package:cricket_engine/cricket_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_documents.dart';
import 'team_repository.dart';

/// Saved squads on the device.
class LocalTeamRepository implements TeamRepository {
  LocalTeamRepository(SharedPreferences prefs)
      : _documents = LocalDocuments(
          prefs: prefs,
          indexKey: 'bnp_scorer.teamIds',
          keyPrefix: 'bnp_scorer.team.',
          fromJson: Team.fromJson,
          toJson: (team) => team.toJson(),
        );

  final LocalDocuments<Team> _documents;

  @override
  Future<List<Team>> loadAll() async => _documents.readAll()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Future<void> save(Team team) => _documents.save(team.id, team);

  @override
  Future<void> delete(String id) => _documents.delete(id);
}
