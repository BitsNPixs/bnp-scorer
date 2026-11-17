/// Tournaments: who plays whom. Results stay in the matches themselves, so
/// tables, qualifiers and the champion are always derived, never stored.
library;

import 'models.dart';
import 'state.dart';
import 'stats.dart';

const finalFixtureId = 'final';

/// Most teams a knockout cup can have: a round of 64.
const maxKnockoutTeams = 64;

/// Time between the starts of matches on the same day.
const _matchSlot = Duration(hours: 2);

/// Marks a `_with` argument that was left out, so null can still clear a field.
const _keep = Object();

class Fixture {
  const Fixture({
    required this.id,
    required this.label,
    required this.teamAId,
    required this.teamBId,
    this.knockout = false,
    this.matchId,
    this.deciderOf,
    this.scheduledAt,
    this.venue,
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

  /// When it is due to start. Null until someone schedules it.
  final DateTime? scheduledAt;

  /// The ground, when it differs from the tournament's.
  final String? venue;

  bool get isDecider => deciderOf != null;

  Fixture _with({Object? matchId = _keep, Object? scheduledAt = _keep, Object? venue = _keep}) => Fixture(
        id: id,
        label: label,
        teamAId: teamAId,
        teamBId: teamBId,
        knockout: knockout,
        deciderOf: deciderOf,
        matchId: identical(matchId, _keep) ? this.matchId : matchId as String?,
        scheduledAt: identical(scheduledAt, _keep) ? this.scheduledAt : scheduledAt as DateTime?,
        venue: identical(venue, _keep) ? this.venue : venue as String?,
      );

  Fixture withMatch(String matchId) => _with(matchId: matchId);

  Fixture withDate(DateTime? date) => _with(scheduledAt: date);

  /// A blank ground falls back to the tournament's.
  Fixture withVenue(String? venue) => _with(venue: _blankToNull(venue));

  Json toJson() => {
        'id': id,
        'label': label,
        'teamAId': teamAId,
        'teamBId': teamBId,
        'knockout': knockout,
        'matchId': matchId,
        'deciderOf': deciderOf,
        'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
        'venue': ?venue,
      };

  factory Fixture.fromJson(Json json) => Fixture(
        id: json['id']! as String,
        label: json['label']! as String,
        teamAId: json['teamAId']! as String,
        teamBId: json['teamBId']! as String,
        knockout: json['knockout'] as bool? ?? false,
        matchId: json['matchId'] as String?,
        deciderOf: json['deciderOf'] as String?,
        scheduledAt: switch (json['scheduledAt']) {
          final String date => DateTime.parse(date),
          _ => null,
        },
        venue: json['venue'] as String?,
      );
}

/// How a tournament is played.
enum TournamentFormat {
  /// A league, or two groups, with optional knockout games after it.
  league,

  /// A straight knockout cup: losers go out each round, from the draw order.
  knockout,
}

/// A prize as the organiser writes it: "Winner", "Rs 25,000 + trophy".
class Prize {
  const Prize({required this.title, required this.reward});

  final String title;
  final String reward;

  Json toJson() => {'title': title, 'reward': reward};

  factory Prize.fromJson(Json json) =>
      Prize(title: json['title']! as String, reward: json['reward']! as String);
}

/// Where one side of a knockout game comes from.
sealed class BracketSide {
  const BracketSide();
}

/// A team drawn straight into this game, including one given a bye.
class DrawnTeam extends BracketSide {
  const DrawnTeam(this.teamId);

  final String teamId;
}

/// A place in a group's final table; both numbers count from 0.
class TablePlace extends BracketSide {
  const TablePlace(this.group, this.place);

  final int group;
  final int place;
}

/// The side that goes through from an earlier knockout game.
class WinnerOf extends BracketSide {
  const WinnerOf(this.fixtureId);

  final String fixtureId;
}

/// A knockout game, known from the start even before its teams are.
class BracketGame {
  const BracketGame({
    required this.id,
    required this.label,
    required this.round,
    required this.a,
    required this.b,
  });

  /// Becomes the fixture's id: "qf2", "sf1", "final", "r16-3".
  final String id;

  /// "Quarter-final 2", "Round of 16 Match 3", "Final".
  final String label;

  /// "Quarter-final", "Round of 16": the same for every game in its round.
  final String round;
  final BracketSide a;
  final BracketSide b;

  Fixture fixture(String teamAId, String teamBId) =>
      Fixture(id: id, label: label, teamAId: teamAId, teamBId: teamBId, knockout: true);
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
    this.format = TournamentFormat.league,
    this.hasSemiFinals = false,
    this.hasQuarterFinals = false,
    this.legs = 1,
    List<List<String>>? groups,
    List<Prize> prizes = const [],
    this.entryFee,
    Map<String, int> paid = const {},
    String? rules,
  })  : teams = List.unmodifiable(teams),
        fixtures = List.unmodifiable(fixtures),
        groups = List.unmodifiable(groups ?? [for (final t in teams) t.id].asGroup),
        prizes = List.unmodifiable(prizes),
        paid = Map.unmodifiable({
          for (final MapEntry(:key, :value) in paid.entries)
            if (value != 0) key: value,
        }),
        rules = _blankToNull(rules) {
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
    if (hasQuarterFinals) {
      final enough =
          this.groups.length == 1 ? teams.length >= 8 : this.groups.every((g) => g.length >= 4);
      if (!hasSemiFinals || !enough) {
        throw ArgumentError(
            'Quarter-finals need semi-finals and the top 8 teams, or the top 4 of each group.');
      }
    }
    if (format == TournamentFormat.knockout) {
      if (!hasFinal || hasSemiFinals || hasQuarterFinals || legs != 1 || this.groups.length != 1) {
        throw ArgumentError('A knockout cup is one draw that ends in a final.');
      }
      if (teams.length > maxKnockoutTeams) {
        throw ArgumentError('A knockout cup takes at most $maxKnockoutTeams teams.');
      }
    }
    if (this.prizes.any((p) => p.title.trim().isEmpty || p.reward.trim().isEmpty)) {
      throw ArgumentError('Every prize needs a title and what it is.');
    }
    if (entryFee case final fee? when fee < 1) {
      throw ArgumentError('An entry fee must be more than 0.');
    }
    final ids = {for (final t in teams) t.id};
    if (this.paid.entries.any((e) => e.value < 0 || !ids.contains(e.key))) {
      throw ArgumentError('Payments must be from teams in the tournament, and not below 0.');
    }
  }

  final String id;
  final String name;
  final int oversPerInnings;
  final TournamentFormat format;

  /// The tournament ends in a final. Always true for a knockout cup.
  final bool hasFinal;

  /// Semi-finals decide who reaches the final, after a league.
  final bool hasSemiFinals;

  /// Quarter-finals come before the semi-finals, after a league.
  final bool hasQuarterFinals;

  /// How often teams in a group meet: 1, or 2 for home and away.
  final int legs;

  /// Team ids per group. One group is a plain league. In a knockout cup the
  /// one group is the draw order, and byes go to the first teams.
  final List<List<String>> groups;
  final String? venue;
  final DateTime createdAt;

  /// Squads as they were when the tournament was created. In a knockout cup,
  /// in draw order.
  final List<Team> teams;
  final List<Fixture> fixtures;

  /// In the order the organiser lists them.
  final List<Prize> prizes;

  /// What each team pays to enter, in whole rupees. Null for none.
  final int? entryFee;

  /// What each team has paid so far, by team id. The organiser's own record:
  /// it never leaves the phone ([toPublicJson] leaves it out).
  final Map<String, int> paid;

  /// House rules and notes from the organiser, shown with the tournament.
  final String? rules;

  bool get isKnockout => format == TournamentFormat.knockout;

  Iterable<Fixture> get leagueFixtures => fixtures.where((f) => !f.knockout);

  Fixture? get finalFixture => fixtures.where((f) => f.id == finalFixtureId).firstOrNull;

  /// Every knockout game, earliest round first, whether or not its teams are
  /// known yet. Empty for a league without a final.
  late final List<BracketGame> bracket = _bracketOf(this);

  Team teamById(String teamId) => teams.firstWhere((t) => t.id == teamId);

  /// "Group A", or null for a plain league.
  String? groupName(int index) => groups.length == 1 ? null : _groupName(index);

  /// Who fills a side of a knockout game, before it is known: "Team A",
  /// "Group B 2nd", "3rd in the table", "Winner of Quarter-final 1".
  String sideName(BracketSide side) => switch (side) {
        DrawnTeam(:final teamId) => teamById(teamId).name,
        TablePlace(:final group, :final place) => groups.length == 1
            ? '${_ordinal(place + 1)} in the table'
            : '${_groupName(group)} ${_ordinal(place + 1)}',
        WinnerOf(:final fixtureId) =>
          'Winner of ${bracket.firstWhere((g) => g.id == fixtureId).label}',
      };

  int paidBy(String teamId) => paid[teamId] ?? 0;

  /// What a team still owes, or null without an entry fee.
  int? dueFrom(String teamId) {
    final fee = entryFee;
    if (fee == null) return null;
    final due = fee - paidBy(teamId);
    return due < 0 ? 0 : due;
  }

  /// What a match in this tournament is called on its card.
  String titleOf(Fixture fixture) {
    final title = '$name ${fixture.label}';
    final ground = fixture.venue ?? venue;
    return ground == null ? title : '$title · $ground';
  }

  Tournament _with({
    List<Fixture>? fixtures,
    List<Prize>? prizes,
    Object? entryFee = _keep,
    Map<String, int>? paid,
    Object? rules = _keep,
  }) =>
      Tournament(
        id: id,
        name: name,
        oversPerInnings: oversPerInnings,
        format: format,
        hasFinal: hasFinal,
        hasSemiFinals: hasSemiFinals,
        hasQuarterFinals: hasQuarterFinals,
        legs: legs,
        groups: groups,
        teams: teams,
        fixtures: fixtures ?? this.fixtures,
        createdAt: createdAt,
        venue: venue,
        prizes: prizes ?? this.prizes,
        entryFee: identical(entryFee, _keep) ? this.entryFee : entryFee as int?,
        paid: paid ?? this.paid,
        rules: identical(rules, _keep) ? this.rules : rules as String?,
      );

  Tournament withMatch(String fixtureId, String matchId) => _with(fixtures: [
        for (final f in fixtures) f.id == fixtureId ? f.withMatch(matchId) : f,
      ]);

  /// Adds the next round, as offered by [TournamentProgress.nextRound]. In a
  /// scheduled tournament, it is dated the day after the latest game.
  Tournament withFixtures(List<Fixture> added) {
    final dates = fixtures.map((f) => f.scheduledAt).nonNulls;
    if (dates.isEmpty) return _with(fixtures: [...fixtures, ...added]);
    final last = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final start = last.add(const Duration(days: 1));
    return _with(fixtures: [
      ...fixtures,
      for (var i = 0; i < added.length; i++) added[i].withDate(start.add(_matchSlot * i)),
    ]);
  }

  Tournament withFixtureDate(String fixtureId, DateTime? date) => _with(fixtures: [
        for (final f in fixtures) f.id == fixtureId ? f.withDate(date) : f,
      ]);

  /// A blank ground falls back to the tournament's.
  Tournament withFixtureVenue(String fixtureId, String? venue) => _with(fixtures: [
        for (final f in fixtures) f.id == fixtureId ? f.withVenue(venue) : f,
      ]);

  /// Replaces fixtures with the same id, as offered by
  /// [TournamentProgress.outdated].
  Tournament withCorrected(List<Fixture> corrected) => _with(fixtures: [
        for (final f in fixtures)
          corrected.where((c) => c.id == f.id).firstOrNull ?? f,
      ]);

  /// The organiser's prizes, entry fee and notes, replaced together.
  Tournament withDetails({required List<Prize> prizes, required int? entryFee, required String? rules}) =>
      _with(prizes: prizes, entryFee: entryFee, rules: rules);

  /// Records what [teamId] has paid in total so far; 0 clears it.
  Tournament withPaid(String teamId, int amount) => _with(paid: {...paid, teamId: amount});

  /// Everything, for this phone's storage and backups.
  Json toJson() => {
        ...toPublicJson(),
        if (paid.isNotEmpty) 'paid': paid,
      };

  /// Everything except who has paid what, which stays with the organiser.
  Json toPublicJson() => {
        'id': id,
        'name': name,
        'oversPerInnings': oversPerInnings,
        if (isKnockout) 'format': format.name,
        'hasFinal': hasFinal,
        'hasSemiFinals': hasSemiFinals,
        if (hasQuarterFinals) 'hasQuarterFinals': true,
        'legs': legs,
        'groups': groups,
        'venue': venue,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'teams': [for (final t in teams) t.toJson()],
        'fixtures': [for (final f in fixtures) f.toJson()],
        if (prizes.isNotEmpty) 'prizes': [for (final p in prizes) p.toJson()],
        'entryFee': ?entryFee,
        'rules': ?rules,
      };

  factory Tournament.fromJson(Json json) => Tournament(
        id: json['id']! as String,
        name: json['name']! as String,
        oversPerInnings: json['oversPerInnings']! as int,
        format: TournamentFormat.values.byName(json['format'] as String? ?? TournamentFormat.league.name),
        hasFinal: json['hasFinal']! as bool,
        hasSemiFinals: json['hasSemiFinals'] as bool? ?? false,
        hasQuarterFinals: json['hasQuarterFinals'] as bool? ?? false,
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
        prizes: [
          for (final p in json['prizes'] as List<Object?>? ?? const []) Prize.fromJson(p! as Json),
        ],
        entryFee: json['entryFee'] as int?,
        paid: {
          for (final MapEntry(:key, :value) in (json['paid'] as Json? ?? const {}).entries)
            key: value! as int,
        },
        rules: json['rules'] as String?,
      );
}

String? _blankToNull(String? text) {
  final trimmed = text?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _ordinal(int n) => switch (n % 100) {
      11 || 12 || 13 => '${n}th',
      _ => switch (n % 10) {
          1 => '${n}st',
          2 => '${n}nd',
          3 => '${n}rd',
          _ => '${n}th',
        },
    };

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

/// Dates [fixtures] in order from [start], [perDay] games a day on consecutive
/// days, two hours apart.
List<Fixture> scheduleFixtures(List<Fixture> fixtures, DateTime start, {int perDay = 2}) {
  if (perDay < 1) throw ArgumentError('Play at least one match a day.');
  return [
    for (var i = 0; i < fixtures.length; i++)
      fixtures[i].withDate(
        DateTime(start.year, start.month, start.day + i ~/ perDay, start.hour, start.minute)
            .add(_matchSlot * (i % perDay)),
      ),
  ];
}

/// A knockout cup's games, earliest round first, from [teamIds] in draw order.
/// Teams are paired in order. When the number is not a power of two, the
/// first teams get byes into the second round, where each meets the winner of
/// a first-round game.
List<BracketGame> knockoutBracket(List<String> teamIds) {
  var size = 2;
  while (size < teamIds.length) {
    size *= 2;
  }
  final byes = size - teamIds.length;
  if (byes == 0) return _playOff([for (final id in teamIds) DrawnTeam(id)]);
  final playing = teamIds.sublist(byes);
  final opening = [
    for (var i = 0; i < playing.length; i += 2)
      _bracketGame(size, i ~/ 2, playing.length ~/ 2, DrawnTeam(playing[i]), DrawnTeam(playing[i + 1])),
  ];
  final next = <BracketSide>[];
  for (var i = 0; i < byes || i < opening.length; i++) {
    if (i < byes) next.add(DrawnTeam(teamIds[i]));
    if (i < opening.length) next.add(WinnerOf(opening[i].id));
  }
  return [...opening, ..._playOff(next)];
}

/// The first round's fixtures of a knockout cup, for creating it.
List<Fixture> knockoutFixtures(List<String> teamIds) => [
      for (final game in knockoutBracket(teamIds))
        if ((game.a, game.b) case (DrawnTeam(teamId: final a), DrawnTeam(teamId: final b)))
          game.fixture(a, b),
    ];

/// Pairs [entrants] in order, then the winners, round by round to a final.
List<BracketGame> _playOff(List<BracketSide> entrants) {
  final games = <BracketGame>[];
  var round = entrants;
  while (round.length > 1) {
    final count = round.length ~/ 2;
    final played = [
      for (var i = 0; i < count; i++) _bracketGame(round.length, i, count, round[2 * i], round[2 * i + 1]),
    ];
    games.addAll(played);
    round = [for (final g in played) WinnerOf(g.id)];
  }
  return games;
}

/// Game [index] of [count] in the round with [teams] teams left.
BracketGame _bracketGame(int teams, int index, int count, BracketSide a, BracketSide b) {
  final n = index + 1;
  final (id, round) = switch (teams) {
    2 => (finalFixtureId, 'Final'),
    4 => ('sf$n', 'Semi-final'),
    8 => ('qf$n', 'Quarter-final'),
    _ => ('r$teams-$n', 'Round of $teams'),
  };
  final label = count == 1 ? round : (teams > 8 ? '$round Match $n' : '$round $n');
  return BracketGame(id: id, label: label, round: round, a: a, b: b);
}

/// After a league, the top teams play off in an order that keeps the best
/// apart: one group 1 v 8, 4 v 5, 2 v 7, 3 v 6; two groups cross over, so a
/// group's top two can only meet in the final.
List<BracketGame> _bracketOf(Tournament t) {
  if (t.isKnockout) return knockoutBracket([for (final team in t.teams) team.id]);
  if (!t.hasFinal) return const [];
  // Places in group A, which is the whole table in a one-group league, and B.
  BracketSide a(int place) => TablePlace(0, place - 1);
  BracketSide b(int place) => TablePlace(1, place - 1);
  final twoGroups = t.groups.length == 2;
  final List<BracketSide> entrants;
  if (t.hasQuarterFinals) {
    entrants = twoGroups
        ? [a(1), b(4), b(2), a(3), b(1), a(4), a(2), b(3)]
        : [a(1), a(8), a(4), a(5), a(2), a(7), a(3), a(6)];
  } else if (t.hasSemiFinals) {
    entrants = twoGroups ? [a(1), b(2), b(1), a(2)] : [a(1), a(4), a(2), a(3)];
  } else {
    entrants = twoGroups ? [a(1), b(1)] : [a(1), a(2)];
  }
  return _playOff(entrants);
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
    required this.bracketTeams,
    required this.outdated,
    required this.championId,
  });

  final Tournament tournament;
  final List<FixtureProgress> fixtures;

  /// League games only. Teams yet to play are included.
  final List<GroupTable> tables;

  /// Every finished game, finals included and Super Overs left out.
  final StatsBook book;

  /// Fixtures that can be scheduled now: knockout games whose teams are both
  /// known, or a Super Over for a tied knockout game.
  final List<Fixture> nextRound;

  /// The teams known so far for each game in [Tournament.bracket], by game id.
  /// Null for a side still to be decided.
  final Map<String, (String?, String?)> bracketTeams;

  /// Scheduled knockout games, with the teams the results now call for, whose
  /// stored teams no longer match. A corrected result upstream causes this.
  final List<Fixture> outdated;

  /// Null until decided, including while a tied final awaits its Super Over.
  final String? championId;

  int get finishedCount => fixtures.where((f) => f.isFinished).length;

  /// Includes knockout games that have not been scheduled yet.
  int get totalCount {
    final t = tournament;
    final ids = {for (final f in t.fixtures) f.id};
    return t.fixtures.length + t.bracket.where((g) => !ids.contains(g.id)).length;
  }

  bool get isFinished => championId != null;

  /// The top MVP once the title is decided.
  PlayerStats? get playerOfTheTournament => isFinished ? book.mvp.firstOrNull : null;
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

  String? teamFor(BracketSide side) => switch (side) {
        DrawnTeam(:final teamId) => teamId,
        TablePlace(:final group, :final place) => leagueDone ? tables[group].teams[place].teamId : null,
        WinnerOf(:final fixtureId) => winnerOf(fixtureId),
      };

  final nextRound = <Fixture>[];
  final outdated = <Fixture>[];
  final bracketTeams = <String, (String?, String?)>{};
  for (final game in tournament.bracket) {
    final (a, b) = (teamFor(game.a), teamFor(game.b));
    bracketTeams[game.id] = (a, b);
    if (a == null || b == null) continue;
    final stored = tournament.fixtures.where((f) => f.id == game.id).firstOrNull;
    if (stored == null) {
      nextRound.add(game.fixture(a, b));
    } else if (!{stored.teamAId, stored.teamBId}.containsAll([a, b])) {
      outdated.add(game.fixture(a, b));
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

  final String? championId;
  if (tournament.bracket.isNotEmpty) {
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
    bracketTeams: bracketTeams,
    outdated: outdated,
    championId: championId,
  );
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
