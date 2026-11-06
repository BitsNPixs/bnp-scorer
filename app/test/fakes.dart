import 'package:cricket_engine/cricket_engine.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/data/match_repository.dart';
import 'package:bnp_scorer/data/team_repository.dart';

class InMemoryMatchRepository implements MatchRepository {
  final records = <String, MatchRecord>{};

  /// When true, [save] throws, simulating a storage failure.
  bool failSaves = false;

  @override
  Future<List<MatchRecord>> loadAll() async =>
      records.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<MatchRecord?> load(String id) async => records[id];

  @override
  Future<void> save(MatchRecord record) async {
    if (failSaves) throw StateError('Storage is full');
    records[record.id] = record;
  }

  @override
  Future<void> delete(String id) async {
    records.remove(id);
  }
}

class InMemoryTeamRepository implements TeamRepository {
  final teams = <String, Team>{};

  /// When true, [save] throws, simulating a storage failure.
  bool failSaves = false;

  @override
  Future<List<Team>> loadAll() async =>
      teams.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<void> save(Team team) async {
    if (failSaves) throw StateError('Storage is full');
    teams[team.id] = team;
  }

  @override
  Future<void> delete(String id) async {
    teams.remove(id);
  }
}

Team _team(String id, List<String> names) => Team(
      id: id,
      name: id == 'a' ? 'Ammapet Kings' : 'Bazaar Strikers',
      players: [
        for (var i = 0; i < names.length; i++) Player(id: '$id${i + 1}', name: names[i]),
      ],
    );

/// Team "a" (Asha, Arun, Anil, Abdul) bats first against team "b".
MatchRecord sampleRecord({
  String id = 'm1',
  int overs = 2,
  List<MatchEvent> events = const [],
  DateTime? updatedAt,
}) {
  final at = DateTime.utc(2026, 11, 5);
  return MatchRecord(
    setup: MatchSetup(
      id: id,
      teamA: _team('a', ['Asha', 'Arun', 'Anil', 'Abdul']),
      teamB: _team('b', ['Bilal', 'Bharat', 'Bose', 'Bala']),
      rules: MatchRules(oversPerInnings: overs),
      tossWinnerId: 'a',
      tossDecision: TossDecision.bat,
    ),
    events: events,
    createdAt: at,
    updatedAt: updatedAt ?? at,
  );
}
