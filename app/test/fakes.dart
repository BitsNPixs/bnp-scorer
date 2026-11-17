import 'dart:async';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/cloud_matches.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/data/match_repository.dart';
import 'package:bnp_scorer/data/team_repository.dart';
import 'package:bnp_scorer/data/tournament_repository.dart';

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

class InMemoryTournamentRepository implements TournamentRepository {
  final tournaments = <String, Tournament>{};

  /// When true, [save] throws, simulating a storage failure.
  bool failSaves = false;

  @override
  Future<List<Tournament>> loadAll() async =>
      tournaments.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<void> save(Tournament tournament) async {
    if (failSaves) throw StateError('Storage is full');
    tournaments[tournament.id] = tournament;
  }

  @override
  Future<void> delete(String id) async {
    tournaments.remove(id);
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

/// Sign-in without Google. [nextSignIn] is who the next sign-in returns; null
/// acts as the scorer cancelling.
class FakeAccounts implements Accounts {
  FakeAccounts({Scorer? signedIn}) : _current = signedIn;

  Scorer? _current;
  Scorer? nextSignIn = const Scorer(uid: 'u1', name: 'Asha Scorer');

  /// When set, sign-in fails with this message.
  String? failWith;
  int signInCalls = 0;
  final _changes = StreamController<Scorer?>.broadcast();

  @override
  bool get available => true;

  @override
  Scorer? get current => _current;

  @override
  Stream<Scorer?> get changes async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<Scorer?> signIn() async {
    signInCalls++;
    final failure = failWith;
    if (failure != null) throw AccountsException(failure);
    if (nextSignIn != null) {
      _current = nextSignIn;
      _changes.add(_current);
    }
    return nextSignIn;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _changes.add(null);
  }
}

/// The cloud as two maps: what is published, and by whom.
class FakeCloudMatches implements CloudMatches {
  final published = <String, MatchRecord>{};
  final owners = <String, Scorer>{};
  final unpublished = <String>[];

  /// When true, every write fails, as with no connection and no queue.
  bool failWrites = false;

  @override
  Future<void> publish(MatchRecord record, Scorer owner) async {
    if (failWrites) throw StateError('No connection');
    published[record.id] = record;
    owners[record.id] = owner;
  }

  @override
  Future<void> unpublish(String matchId) async {
    if (failWrites) throw StateError('No connection');
    published.remove(matchId);
    unpublished.add(matchId);
  }
}
