/// Tournaments: who plays whom. Results stay in the matches themselves, so the
/// table and the champion are always derived, never stored.
library;

import 'models.dart';
import 'state.dart';
import 'stats.dart';

class Fixture {
  const Fixture({
    required this.id,
    required this.label,
    required this.teamAId,
    required this.teamBId,
    this.knockout = false,
    this.matchId,
  });

  final String id;

  /// "Match 3", "Final".
  final String label;
  final String teamAId;
  final String teamBId;

  /// Knockout games decide the title and stay out of the league table.
  final bool knockout;

  /// The match played for this fixture, once it has started.
  final String? matchId;

  Fixture withMatch(String matchId) => Fixture(
        id: id,
        label: label,
        teamAId: teamAId,
        teamBId: teamBId,
        knockout: knockout,
        matchId: matchId,
      );

  Json toJson() => {
        'id': id,
        'label': label,
        'teamAId': teamAId,
        'teamBId': teamBId,
        'knockout': knockout,
        'matchId': matchId,
      };

  factory Fixture.fromJson(Json json) => Fixture(
        id: json['id']! as String,
        label: json['label']! as String,
        teamAId: json['teamAId']! as String,
        teamBId: json['teamBId']! as String,
        knockout: json['knockout'] as bool? ?? false,
        matchId: json['matchId'] as String?,
      );
}

class Tournament {
  Tournament({
    required this.id,
    required this.name,
    required this.oversPerInnings,
    required this.hasFinal,
    required List<Team> teams,
    required List<Fixture> fixtures,
    required this.createdAt,
    this.venue,
  })  : teams = List.unmodifiable(teams),
        fixtures = List.unmodifiable(fixtures) {
    if (teams.length < 2) throw ArgumentError('A tournament needs at least 2 teams.');
    if (hasFinal && teams.length < 3) {
      throw ArgumentError('A final needs at least 3 teams.');
    }
    if (teams.map((t) => t.id).toSet().length != teams.length) {
      throw ArgumentError('Teams in a tournament must be different.');
    }
    if (oversPerInnings < 1) throw ArgumentError('Overs must be at least 1.');
  }

  final String id;
  final String name;
  final int oversPerInnings;

  /// The top two of the league meet in a final.
  final bool hasFinal;
  final String? venue;
  final DateTime createdAt;

  /// Squads as they were when the tournament was created.
  final List<Team> teams;
  final List<Fixture> fixtures;

  Iterable<Fixture> get leagueFixtures => fixtures.where((f) => !f.knockout);

  Fixture? get finalFixture => fixtures.where((f) => f.knockout).firstOrNull;

  Team teamById(String teamId) => teams.firstWhere((t) => t.id == teamId);

  /// What a match in this tournament is called on its card.
  String titleOf(Fixture fixture) {
    final title = '$name ${fixture.label}';
    final ground = venue;
    return ground == null ? title : '$title · $ground';
  }

  Tournament _withFixtures(List<Fixture> fixtures) => Tournament(
        id: id,
        name: name,
        oversPerInnings: oversPerInnings,
        hasFinal: hasFinal,
        teams: teams,
        fixtures: fixtures,
        createdAt: createdAt,
        venue: venue,
      );

  Tournament withMatch(String fixtureId, String matchId) => _withFixtures([
        for (final f in fixtures) f.id == fixtureId ? f.withMatch(matchId) : f,
      ]);

  Tournament withFinal(String teamAId, String teamBId) => _withFixtures([
        ...fixtures,
        Fixture(id: 'final', label: 'Final', teamAId: teamAId, teamBId: teamBId, knockout: true),
      ]);

  Json toJson() => {
        'id': id,
        'name': name,
        'oversPerInnings': oversPerInnings,
        'hasFinal': hasFinal,
        'venue': venue,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'teams': [for (final t in teams) t.toJson()],
        'fixtures': [for (final f in fixtures) f.toJson()],
      };

  factory Tournament.fromJson(Json json) => Tournament(
        id: json['id']! as String,
        name: json['name']! as String,
        oversPerInnings: json['oversPerInnings']! as int,
        hasFinal: json['hasFinal']! as bool,
        venue: json['venue'] as String?,
        createdAt: DateTime.parse(json['createdAt']! as String),
        teams: [
          for (final t in json['teams']! as List<Object?>) Team.fromJson(t! as Json),
        ],
        fixtures: [
          for (final f in json['fixtures']! as List<Object?>) Fixture.fromJson(f! as Json),
        ],
      );
}

/// Every team plays every other once, spread into rounds by the circle method
/// so nobody waits long between games.
List<Fixture> roundRobinFixtures(List<Team> teams) {
  final slots = <String?>[for (final t in teams) t.id];
  if (slots.length.isOdd) slots.add(null); // the team drawn against this rests
  final fixtures = <Fixture>[];
  for (var round = 0; round < slots.length - 1; round++) {
    for (var i = 0; i < slots.length ~/ 2; i++) {
      final home = slots[i];
      final away = slots[slots.length - 1 - i];
      if (home == null || away == null) continue;
      final number = fixtures.length + 1;
      fixtures.add(Fixture(id: 'f$number', label: 'Match $number', teamAId: home, teamBId: away));
    }
    slots.insert(1, slots.removeLast());
  }
  return fixtures;
}

/// A fixture with the match played for it. [match] is null before it starts,
/// and again if the match was deleted, which reopens the fixture.
class FixtureProgress {
  const FixtureProgress({required this.fixture, this.match});

  final Fixture fixture;
  final MatchState? match;

  bool get isFinished => match?.isCompleted ?? false;
}

class TournamentProgress {
  const TournamentProgress({
    required this.tournament,
    required this.fixtures,
    required this.table,
    required this.book,
    required this.finalists,
    required this.championId,
  });

  final Tournament tournament;
  final List<FixtureProgress> fixtures;

  /// League games only, best first. Teams yet to play are included.
  final List<TeamStats> table;

  /// Every finished game, final included.
  final StatsBook book;

  /// The top two, once the league is done and the final needs scheduling.
  final (TeamStats, TeamStats)? finalists;

  /// Null until decided, and for a tied final.
  final String? championId;

  int get finishedCount => fixtures.where((f) => f.isFinished).length;

  /// Includes a final that has not been scheduled yet.
  int get totalCount {
    final t = tournament;
    return fixtures.length + (t.hasFinal && t.finalFixture == null ? 1 : 0);
  }

  bool get isFinished => finishedCount == totalCount;
}

/// Combines [tournament] with its matches. [matches] is keyed by match id and
/// may hold matches from outside the tournament.
TournamentProgress progressOf(Tournament tournament, Map<String, MatchState> matches) {
  final fixtures = [
    for (final f in tournament.fixtures)
      FixtureProgress(fixture: f, match: matches[f.matchId]),
  ];
  Iterable<MatchState> played(Iterable<FixtureProgress> list) =>
      list.where((f) => f.isFinished).map((f) => f.match!);

  final league = fixtures.where((f) => !f.fixture.knockout);
  final leagueDone = league.every((f) => f.isFinished);
  final table = computeStats(played(league), entrants: tournament.teams).teams;
  final book = computeStats(played(fixtures), entrants: tournament.teams);

  (TeamStats, TeamStats)? finalists;
  String? championId;
  if (tournament.hasFinal) {
    final finalGame = fixtures.where((f) => f.fixture.knockout).firstOrNull;
    if (finalGame == null) {
      if (leagueDone) finalists = (table[0], table[1]);
    } else if (finalGame.isFinished) {
      championId = finalGame.match!.result?.winnerTeamId;
    }
  } else if (leagueDone) {
    championId = table.first.teamId;
  }
  return TournamentProgress(
    tournament: tournament,
    fixtures: fixtures,
    table: table,
    book: book,
    finalists: finalists,
    championId: championId,
  );
}
