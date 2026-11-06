import 'package:cricket_engine/cricket_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_documents.dart';

/// Storage boundary for tournaments. A tournament holds its fixtures and which
/// match was played for each; the results live in the matches.
abstract interface class TournamentRepository {
  /// Newest first. Unreadable records are skipped.
  Future<List<Tournament>> loadAll();

  Future<void> save(Tournament tournament);

  Future<void> delete(String id);
}

class LocalTournamentRepository implements TournamentRepository {
  LocalTournamentRepository(SharedPreferences prefs)
      : _documents = LocalDocuments(
          prefs: prefs,
          indexKey: 'bnp_scorer.tournamentIds',
          keyPrefix: 'bnp_scorer.tournament.',
          fromJson: Tournament.fromJson,
          toJson: (tournament) => tournament.toJson(),
        );

  final LocalDocuments<Tournament> _documents;

  @override
  Future<List<Tournament>> loadAll() async =>
      _documents.readAll()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> save(Tournament tournament) => _documents.save(tournament.id, tournament);

  @override
  Future<void> delete(String id) => _documents.delete(id);
}
