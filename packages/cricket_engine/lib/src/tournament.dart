/// Tournaments: who plays whom. Results stay in the matches themselves, so
/// tables, qualifiers and the champion are always derived, never stored.
library;

import 'models.dart';
import 'state.dart';
import 'stats.dart';

const finalFixtureId = 'final';
const _semiFinalIds = ['sf1', 'sf2'];

class Fixture {
  const Fixture({
    required this.id,
    required this.label,
    required this.teamAId,
    required this.teamBId,
    this.knockout = false,
    this.matchId,
    this.deciderOf,
  });

  final String id;

  /// "Match 3", "Group A Match 2", "Semi-final 1", "Final Super Over".
  final String label;
  final String teamAId;
  final String teamBId;

  /// Knockout games decide the title and stay out of the league table.
  final bool knockout;

  /// The match played for this fixture, once it has started.
  final String? matchId;

  /// For a Super Over: the id of the tied knockout game it settles.
  final String? deciderOf;

  bool get isDecider => deciderOf != null;

  Fixture withMatch(String matchId) => Fixture(
        id: id,
        label: label,
        teamAId: teamAId,
        teamBId: teamBId,
        knockout: knockout,
        matchId: matchId,
        deciderOf: deciderOf,
      );

  Json toJson() => {
        'id': id,
        'label': label,
        'teamAId': teamAId,
        'teamBId': teamBId,
        'knockout': knockout,
        'matchId': matchId,
        'deciderOf': deciderOf,
      };

  factory Fixture.fromJson(Json json) => Fixture(
        id: json['id']! as String,
        label: json['label']! as String,
        teamAId: json['teamAId']! as String,
        teamBId: json['teamBId']! as String,
        knockout: json['knockout'] as bool? ?? false,
        matchId: json['matchId'] as String?,
        deciderOf: json['deciderOf'] as String?,
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
    this.hasSemiFinals = false,
    this.legs = 1,
    List<List<String>>? groups,
  })  : teams = List.unmodifiable(teams),
        fixtures = List.unmodifiable(fixtures),
        groups = List.unmodifiable(groups ?? [for (final t in teams) t.id].asGroup) {
    if (teams.length < 2) throw ArgumentError('A tournament needs at least 2 teams.');
    if (hasFinal && teams.length < 3) {
      throw ArgumentError('A final needs at least 3 teams.');
    }
    if (hasSemiFinals && (!hasFinal || teams.length < 4)) {
      throw ArgumentError('Semi-finals need a final and at least 4 teams.');
    }
    if (teams.map((t) => t.id).toSet().length != teams.length) {
      throw ArgumentError('Teams in a tournament must be different.');
    }
    if (oversPerInnings < 1) throw ArgumentError('Overs must be at least 1.');
    if (legs < 1 || legs > 2) throw ArgumentError('Teams meet once or twice.');
    if (this.groups.length > 2 || this.groups.any((g) => g.length < 2)) {
      throw ArgumentError('Use one or two groups of at least 2 teams.');
    }
    if (this.groups.length == 2 && !hasFinal) {
      throw ArgumentError('Two groups need a final to meet in.');
    }
    final grouped = this.groups.expand((g) => g).toSet();
    if (grouped.length != teams.length || !teams.every((t) => grouped.contains(t.id))) {
      throw ArgumentError('Every team must be in exactly one group.');
    }
  }

  final String id;
  final String name;
  final int oversPerInnings;

  /// The league ends in a final.
  final bool hasFinal;

  /// Semi-finals decide who reaches the final.
  final bool hasSemiFinals;

  /// How often teams in a group meet: 1, or 2 for home and away.
  final int legs;

  /// Team ids per group. One group is a plain league.
  final List<List<String>> groups;
  final String? venue;
  final DateTime createdAt;

  /// Squads as they were when the tournament was created.
  final List<Team> teams;
  final List<Fixture> fixtures;

  Iterable<Fixture> get leagueFixtures => fixtures.where((f) => !f.knockout);

  Fixture? get finalFixture => fixtures.where((f) => f.id == finalFixtureId).firstOrNull;

  Team teamById(String teamId) => teams.firstWhere((t) => t.id == teamId);

  /// "Group A", or null for a plain league.
  String? groupName(int index) => groups.length == 1 ? null : _groupName(index);

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
        hasSemiFinals: hasSemiFinals,
        legs: legs,
        groups: groups,
        teams: teams,
        fixtures: fixtures,
        createdAt: createdAt,
        venue: venue,
      );

  Tournament withMatch(String fixtureId, String matchId) => _withFixtures([
        for (final f in fixtures) f.id == fixtureId ? f.withMatch(matchId) : f,
      ]);

  /// Adds the next round, as offered by [TournamentProgress.nextRound].
  Tournament withFixtures(List<Fixture> added) => _withFixtures([...fixtures, ...added]);

  /// Replaces fixtures with the same id, as offered by
  /// [TournamentProgress.outdated].
  Tournament withCorrected(List<Fixture> corrected) => _withFixtures([
        for (final f in fixtures)
          corrected.where((c) => c.id == f.id).firstOrNull ?? f,
      ]);

  Json toJson() => {
        'id': id,
        'name': name,
        'oversPerInnings': oversPerInnings,
        'hasFinal': hasFinal,
        'hasSemiFinals': hasSemiFinals,
        'legs': legs,
        'groups': groups,
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
        hasSemiFinals: json['hasSemiFinals'] as bool? ?? false,
        legs: json['legs'] as int? ?? 1,
        groups: switch (json['groups']) {
          final List<Object?> list => [
              for (final group in list) [for (final id in group! as List<Object?>) id! as String],
            ],
          _ => null,
        },
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

extension on List<String> {
  List<List<String>> get asGroup => [this];
}

String _groupName(int index) => 'Group ${String.fromCharCode(65 + index)}';

/// Splits [teams] into two groups, alternating, so the list order is balanced.
List<List<String>> splitIntoTwoGroups(List<Team> teams) => [
      for (var group = 0; group < 2; group++)
        [
          for (var i = group; i < teams.length; i += 2) teams[i].id,
        ],
    ];

/// One league game for every pairing in each of [groups], [legs] times. Numbers
/// run through all groups, and the second leg swaps home and away.
List<Fixture> leagueFixtures(List<List<String>> groups, {int legs = 1}) {
  final fixtures = <Fixture>[];
  for (var g = 0; g < groups.length; g++) {
    final prefix = groups.length == 1 ? '' : '${_groupName(g)} ';
    final pairings = _rounds(groups[g]);
    for (var leg = 0; leg < legs; leg++) {
      for (final (home, away) in pairings) {
        final number = fixtures.length + 1;
        fixtures.add(Fixture(
          id: 'f$number',
          label: '${prefix}Match $number',
          teamAId: leg.isEven ? home : away,
          teamBId: leg.isEven ? away : home,
        ));
      }
    }
  }
  return fixtures;
}

/// Every team plays every other once, spread into rounds by the circle method
/// so nobody waits long between games.
List<Fixture> roundRobinFixtures(List<Team> teams, {int legs = 1}) =>
    leagueFixtures([
      [for (final t in teams) t.id],
    ], legs: legs);

List<(String, String)> _rounds(List<String> teamIds) {
  final slots = <String?>[...teamIds];
  if (slots.length.isOdd) slots.add(null); // the team drawn against this rests
  final pairings = <(String, String)>[];
  for (var round = 0; round < slots.length - 1; round++) {
    for (var i = 0; i < slots.length ~/ 2; i++) {
      final home = slots[i];
      final away = slots[slots.length - 1 - i];
      if (home != null && away != null) pairings.add((home, away));
    }
    slots.insert(1, slots.removeLast());
  }
  return pairings;
}

/// A fixture with the match played for it. [match] is null before it starts,
/// and again if the match was deleted, which reopens the fixture.
class FixtureProgress {
  const FixtureProgress({required this.fixture, this.match});

  final Fixture fixture;
  final MatchState? match;

  bool get isFinished => match?.isCompleted ?? false;
}

/// A group's league table, best first. [name] is null for a plain league.
class GroupTable {
  const GroupTable({required this.name, required this.teams});

  final String? name;
  final List<TeamStats> teams;
}

class TournamentProgress {
  const TournamentProgress({
    required this.tournament,
    required this.fixtures,
    required this.tables,
    required this.book,
    required this.nextRound,
    required this.outdated,
    required this.championId,
  });

  final Tournament tournament;
  final List<FixtureProgress> fixtures;

  /// League games only. Teams yet to play are included.
  final List<GroupTable> tables;

  /// Every finished game, finals included and Super Overs left out.
  final StatsBook book;

  /// Fixtures that can be scheduled now: the first knockout round, the final,
  /// or a Super Over for a tied knockout game.
  final List<Fixture> nextRound;

  /// Scheduled knockout games, with the teams the results now call for, whose
  /// stored teams no longer match. A corrected result upstream causes this.
  final List<Fixture> outdated;

  /// Null until decided, including while a tied final awaits its Super Over.
  final String? championId;

  int get finishedCount => fixtures.where((f) => f.isFinished).length;

  /// Includes knockout games that have not been scheduled yet.
  int get totalCount {
    final t = tournament;
    final planned = t.hasSemiFinals ? 3 : (t.hasFinal ? 1 : 0);
    final scheduled = t.fixtures.where((f) => f.knockout && !f.isDecider).length;
    return t.fixtures.length + planned - scheduled;
  }

  bool get isFinished => championId != null;
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
  final tables = [
    for (var g = 0; g < tournament.groups.length; g++)
      GroupTable(
        name: tournament.groupName(g),
        teams: computeStats(
          played(league.where((f) => tournament.groups[g].contains(f.fixture.teamAId))),
          entrants: [
            for (final id in tournament.groups[g]) tournament.teamById(id),
          ],
        ).teams,
      ),
  ];
  final book = computeStats(played(fixtures), entrants: tournament.teams);

  List<FixtureProgress> decidersOf(String id) =>
      fixtures.where((f) => f.fixture.deciderOf == id).toList();

  /// The side going through, once a knockout game and any Super Over are done.
  /// A knockout game with no winner, tied or abandoned, needs a Super Over.
  String? winnerOf(String fixtureId) {
    final game = fixtures.where((f) => f.fixture.id == fixtureId).firstOrNull;
    if (game == null || !game.isFinished) return null;
    final winner = game.match!.result?.winnerTeamId;
    if (winner != null) return winner;
    final deciders = decidersOf(fixtureId);
    if (deciders.isEmpty || !deciders.last.isFinished) return null;
    return deciders.last.match!.result?.winnerTeamId;
  }

  final nextRound = <Fixture>[];
  final hasKnockouts = tournament.fixtures.any((f) => f.knockout);
  if (tournament.hasFinal && leagueDone && !hasKnockouts) {
    nextRound.addAll(_firstKnockoutRound(tournament, tables));
  }
  if (tournament.hasSemiFinals && tournament.finalFixture == null) {
    final winners = [for (final id in _semiFinalIds) winnerOf(id)];
    if (winners.every((w) => w != null)) {
      nextRound.add(_finalBetween(winners[0]!, winners[1]!));
    }
  }
  for (final game in fixtures) {
    final fixture = game.fixture;
    if (!fixture.knockout || fixture.isDecider || !game.isFinished) continue;
    if (winnerOf(fixture.id) != null) continue;
    final deciders = decidersOf(fixture.id);
    if (deciders.isNotEmpty && !deciders.last.isFinished) continue;
    final tied = deciders.isEmpty ? game : deciders.last;
    nextRound.add(_superOver(fixture, tied.match!, deciders.length + 1));
  }

  final expected = [
    if (tournament.hasFinal && leagueDone) ..._firstKnockoutRound(tournament, tables),
    if (tournament.hasSemiFinals)
      if ([for (final id in _semiFinalIds) winnerOf(id)] case [final String a, final String b])
        _finalBetween(a, b),
  ];
  final outdated = <Fixture>[];
  for (final wanted in expected) {
    final stored = tournament.fixtures.where((f) => f.id == wanted.id).firstOrNull;
    if (stored == null) continue;
    final same = {stored.teamAId, stored.teamBId}.containsAll([wanted.teamAId, wanted.teamBId]);
    if (!same) outdated.add(wanted);
  }

  final String? championId;
  if (tournament.hasFinal) {
    championId = winnerOf(finalFixtureId);
  } else {
    championId = leagueDone ? tables.single.teams.first.teamId : null;
  }
  return TournamentProgress(
    tournament: tournament,
    fixtures: fixtures,
    tables: tables,
    book: book,
    nextRound: nextRound,
    outdated: outdated,
    championId: championId,
  );
}

Fixture _finalBetween(String teamAId, String teamBId) => Fixture(
      id: finalFixtureId,
      label: 'Final',
      teamAId: teamAId,
      teamBId: teamBId,
      knockout: true,
    );

Fixture _semiFinal(int index, String teamAId, String teamBId) => Fixture(
      id: _semiFinalIds[index],
      label: 'Semi-final ${index + 1}',
      teamAId: teamAId,
      teamBId: teamBId,
      knockout: true,
    );

/// One group: 1 v 4 and 2 v 3, or 1 v 2 for a final. Two groups: group winners
/// meet runners-up from the other group, or each other in a final.
List<Fixture> _firstKnockoutRound(Tournament tournament, List<GroupTable> tables) {
  String seed(int group, int place) => tables[group].teams[place].teamId;
  final twoGroups = tables.length == 2;
  if (!tournament.hasSemiFinals) {
    return [
      twoGroups
          ? _finalBetween(seed(0, 0), seed(1, 0))
          : _finalBetween(seed(0, 0), seed(0, 1)),
    ];
  }
  return twoGroups
      ? [
          _semiFinal(0, seed(0, 0), seed(1, 1)),
          _semiFinal(1, seed(1, 0), seed(0, 1)),
        ]
      : [
          _semiFinal(0, seed(0, 0), seed(0, 3)),
          _semiFinal(1, seed(0, 1), seed(0, 2)),
        ];
}

/// The side that batted second in the tied game bats first in the Super Over.
Fixture _superOver(Fixture tied, MatchState match, int number) {
  final battedSecond = match.innings.last.battingTeamId;
  final other = battedSecond == tied.teamAId ? tied.teamBId : tied.teamAId;
  return Fixture(
    id: '${tied.id}-so$number',
    label: number == 1 ? '${tied.label} Super Over' : '${tied.label} Super Over $number',
    teamAId: battedSecond,
    teamBId: other,
    knockout: true,
    deciderOf: tied.id,
  );
}
