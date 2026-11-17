import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

Team _team(String id) => Team(
      id: id,
      name: 'Team ${id.toUpperCase()}',
      players: [
        for (var i = 1; i <= 3; i++) Player(id: '$id$i', name: 'Player $id$i'),
      ],
    );

Tournament _tournament(
  List<String> ids, {
  bool hasFinal = false,
  bool hasSemiFinals = false,
  bool hasQuarterFinals = false,
  bool twoGroups = false,
  int legs = 1,
  String? venue,
}) {
  final teams = [for (final id in ids) _team(id)];
  final groups = twoGroups ? splitIntoTwoGroups(teams) : null;
  return Tournament(
    id: 't',
    name: 'Cup',
    oversPerInnings: 1,
    hasFinal: hasFinal,
    hasSemiFinals: hasSemiFinals,
    hasQuarterFinals: hasQuarterFinals,
    groups: groups,
    legs: legs,
    teams: teams,
    fixtures: groups == null
        ? roundRobinFixtures(teams, legs: legs)
        : leagueFixtures(groups, legs: legs),
    createdAt: DateTime.utc(2026),
    venue: venue,
  );
}

/// A one-over match between [first] and [second], which bats second, with 3
/// runs scored each. Decided by neither side, so it is a tie.
MatchState _tied(Team first, Team second, {bool superOver = false}) {
  final at = DateTime.utc(2026);
  final setup = MatchSetup(
    id: 'tie',
    teamA: first,
    teamB: second,
    rules: MatchRules(oversPerInnings: 1, superOver: superOver),
    tossWinnerId: first.id,
    tossDecision: TossDecision.bat,
  );
  var n = 0;
  String id() => 'e${n++}';
  List<MatchEvent> innings(Team bat, Team bowl) => [
        OpenersSelected(id: id(), at: at, strikerId: bat.players[0].id, nonStrikerId: bat.players[1].id),
        BowlerChanged(id: id(), at: at, bowlerId: bowl.players[0].id),
        for (final r in [1, 1, 1, 0, 0, 0]) BallBowled(id: id(), at: at, runsOffBat: r),
      ];
  return ScoringEngine.replay(setup, [...innings(first, second), ...innings(second, first)]);
}

/// Plays a knockout fixture by id, with [state] as its match.
(Tournament, Map<String, MatchState>) _record(
  Tournament t,
  Map<String, MatchState> matches,
  String fixtureId,
  MatchState state,
) =>
    (t.withMatch(fixtureId, 'ko-$fixtureId'), {...matches, 'ko-$fixtureId': state});

(String, String) _pair(Fixture f) => (f.teamAId, f.teamBId);

/// A one-over match that [firstBatting] wins by scoring 6 to nothing.
MatchState _won(Team firstBatting, Team other) {
  final at = DateTime.utc(2026);
  final setup = MatchSetup(
    id: 'm',
    teamA: firstBatting,
    teamB: other,
    rules: MatchRules(oversPerInnings: 1),
    tossWinnerId: firstBatting.id,
    tossDecision: TossDecision.bat,
  );
  var n = 0;
  String id() => 'e${n++}';
  List<MatchEvent> innings(Team bat, Team bowl, int runs) => [
        OpenersSelected(id: id(), at: at, strikerId: bat.players[0].id, nonStrikerId: bat.players[1].id),
        BowlerChanged(id: id(), at: at, bowlerId: bowl.players[0].id),
        for (var i = 0; i < 6; i++) BallBowled(id: id(), at: at, runsOffBat: i < runs ? 1 : 0),
      ];
  return ScoringEngine.replay(setup, [
    ...innings(firstBatting, other, 6),
    ...innings(other, firstBatting, 0),
  ]);
}

/// A straight knockout cup of [ids], in that draw order.
Tournament _cup(List<String> ids) => Tournament(
      id: 'cup',
      name: 'Cup',
      oversPerInnings: 1,
      hasFinal: true,
      format: TournamentFormat.knockout,
      teams: [for (final id in ids) _team(id)],
      fixtures: knockoutFixtures(ids),
      createdAt: DateTime.utc(2026),
    );

/// Plays the stored knockout fixture [fixtureId], won by [winnerId].
(Tournament, Map<String, MatchState>) _win(
  Tournament t,
  Map<String, MatchState> matches,
  String fixtureId,
  String winnerId,
) {
  final f = t.fixtures.firstWhere((f) => f.id == fixtureId);
  final loserId = winnerId == f.teamAId ? f.teamBId : f.teamAId;
  return _record(t, matches, fixtureId, _won(t.teamById(winnerId), t.teamById(loserId)));
}

/// The alphabetically first team of a fixture, so league tables run a, b, c.
String _better(Fixture f) => f.teamAId.compareTo(f.teamBId) < 0 ? f.teamAId : f.teamBId;

/// Plays [winners] in fixture order, linking each match to its fixture.
(Tournament, Map<String, MatchState>) _play(Tournament start, List<String> winners) {
  var t = start;
  final matches = <String, MatchState>{};
  for (var i = 0; i < winners.length; i++) {
    final f = t.fixtures[i];
    final winner = t.teamById(winners[i]);
    final loser = t.teamById(winners[i] == f.teamAId ? f.teamBId : f.teamAId);
    matches['m$i'] = _won(winner, loser);
    t = t.withMatch(f.id, 'm$i');
  }
  return (t, matches);
}

void main() {
  group('round robin', () {
    Set<String> pairs(List<Fixture> fixtures) =>
        {for (final f in fixtures) ([f.teamAId, f.teamBId]..sort()).join()};

    test('every pair meets exactly once', () {
      for (final ids in [
        ['a', 'b'],
        ['a', 'b', 'c'],
        ['a', 'b', 'c', 'd'],
        ['a', 'b', 'c', 'd', 'e'],
        ['a', 'b', 'c', 'd', 'e', 'f'],
      ]) {
        final fixtures = roundRobinFixtures([for (final id in ids) _team(id)]);
        final expected = ids.length * (ids.length - 1) ~/ 2;
        expect(fixtures, hasLength(expected));
        expect(pairs(fixtures), hasLength(expected));
      }
    });

    test('nobody plays twice in a round of four teams', () {
      final fixtures = roundRobinFixtures([for (final id in 'abcd'.split('')) _team(id)]);
      for (var round = 0; round < 3; round++) {
        final inRound = fixtures.skip(round * 2).take(2);
        final teams = inRound.expand((f) => [f.teamAId, f.teamBId]).toSet();
        expect(teams, hasLength(4));
      }
    });

    test('fixtures have unique ids and are numbered', () {
      final fixtures = roundRobinFixtures([for (final id in 'abcd'.split('')) _team(id)]);
      expect(fixtures.map((f) => f.id).toSet(), hasLength(6));
      expect(fixtures.first.label, 'Match 1');
      expect(fixtures.last.label, 'Match 6');
    });
  });

  group('rules for a tournament', () {
    test('needs two different teams', () {
      expect(() => _tournament(['a']), throwsArgumentError);
      expect(() => _tournament(['a', 'a']), throwsArgumentError);
    });

    test('a final needs three teams', () {
      expect(() => _tournament(['a', 'b'], hasFinal: true), throwsArgumentError);
      expect(() => _tournament(['a', 'b', 'c'], hasFinal: true), returnsNormally);
    });
  });

  group('progress', () {
    test('a new tournament lists every team on zero', () {
      final p = progressOf(_tournament(['a', 'b', 'c']), const {});
      expect(p.tables.single.name, isNull);
      expect(p.tables.single.teams, hasLength(3));
      expect(p.tables.single.teams.every((t) => t.played == 0 && t.netRunRate == null), isTrue);
      expect(p.finishedCount, 0);
      expect(p.totalCount, 3);
      expect(p.championId, isNull);
      expect(p.book.isEmpty, isTrue);
    });

    test('a league without a final is won by the top of the table', () {
      final start = _tournament(['a', 'b', 'c']);
      final winners = [
        for (final f in start.fixtures) f.teamAId == 'a' || f.teamBId == 'a' ? 'a' : 'b',
      ];
      final (t, matches) = _play(start, winners);
      final p = progressOf(t, matches);
      expect(p.tables.single.teams.first.teamId, 'a');
      expect(p.tables.single.teams.first.points, 4);
      expect(p.championId, 'a');
      expect(p.isFinished, isTrue);
    });

    test('with a final, the league finishing names the top two and no champion', () {
      final start = _tournament(['a', 'b', 'c'], hasFinal: true);
      final winners = [
        for (final f in start.fixtures) f.teamAId == 'a' || f.teamBId == 'a' ? 'a' : 'b',
      ];
      final (t, matches) = _play(start, winners);
      final p = progressOf(t, matches);
      expect(_pair(p.nextRound.single), ('a', 'b'));
      expect(p.nextRound.single.id, finalFixtureId);
      expect(p.championId, isNull);
      expect(p.isFinished, isFalse);
      expect(p.totalCount, 4);
    });

    test('no finalists while a league game is unplayed', () {
      final start = _tournament(['a', 'b', 'c'], hasFinal: true);
      final (t, matches) = _play(start, [start.fixtures[0].teamAId]);
      expect(progressOf(t, matches).nextRound, isEmpty);
    });

    test('the final decides the champion and stays out of the table', () {
      final start = _tournament(['a', 'b', 'c'], hasFinal: true);
      final winners = [
        for (final f in start.fixtures) f.teamAId == 'a' || f.teamBId == 'a' ? 'a' : 'b',
      ];
      final (league, matches) = _play(start, winners);
      final withFinal = league.withFixtures(progressOf(league, matches).nextRound);
      expect(progressOf(withFinal, matches).nextRound, isEmpty);

      final done = withFinal.withMatch('final', 'final-match');
      final p = progressOf(done, {...matches, 'final-match': _won(_team('b'), _team('a'))});

      expect(p.championId, 'b');
      expect(p.isFinished, isTrue);
      final top = p.tables.single.teams.first;
      expect(top.teamId, 'a', reason: 'the final does not change the table');
      expect(top.played, 2);
      expect(p.book.matches, 4, reason: 'leaderboards count the final');
    });

    test('an unfinished match does not count, and a deleted one reopens the fixture', () {
      final start = _tournament(['a', 'b']);
      final linked = start.withMatch('f1', 'gone');
      final p = progressOf(linked, const {});
      expect(p.fixtures.single.match, isNull);
      expect(p.fixtures.single.isFinished, isFalse);
      expect(p.championId, isNull);
    });

    test('matches outside the tournament are ignored', () {
      final p = progressOf(_tournament(['a', 'b']), {'other': _won(_team('a'), _team('b'))});
      expect(p.book.isEmpty, isTrue);
      expect(p.tables.single.teams.every((t) => t.played == 0), isTrue);
    });
  });

  group('formats', () {
    test('home and away plays every pairing twice, swapped', () {
      final teams = [_team('a'), _team('b'), _team('c')];
      final fixtures = roundRobinFixtures(teams, legs: 2);
      expect(fixtures, hasLength(6));
      expect(fixtures.map((f) => f.id).toSet(), hasLength(6));
      expect(_pair(fixtures[3]), (fixtures[0].teamBId, fixtures[0].teamAId));
    });

    test('groups split evenly and play only inside the group', () {
      final teams = [for (final id in 'abcde'.split('')) _team(id)];
      final groups = splitIntoTwoGroups(teams);
      expect(groups, [
        ['a', 'c', 'e'],
        ['b', 'd'],
      ]);
      final fixtures = leagueFixtures(groups);
      expect(fixtures, hasLength(4));
      expect(fixtures.first.label, 'Group A Match 1');
      expect(fixtures.last.label, 'Group B Match 4');
      for (final f in fixtures) {
        final group = groups.firstWhere((g) => g.contains(f.teamAId));
        expect(group, contains(f.teamBId));
      }
    });

    test('rejects shapes that cannot finish', () {
      expect(() => _tournament(['a', 'b', 'c'], hasFinal: true, hasSemiFinals: true), throwsArgumentError);
      expect(() => _tournament(['a', 'b', 'c', 'd'], hasSemiFinals: true), throwsArgumentError);
      expect(() => _tournament(['a', 'b', 'c', 'd'], twoGroups: true), throwsArgumentError);
      expect(() => _tournament(['a', 'b', 'c'], hasFinal: true, twoGroups: true), throwsArgumentError);
      expect(() => _tournament(['a', 'b'], legs: 3), throwsArgumentError);
    });

    test('rejects a team left out of the groups', () {
      expect(
        () => Tournament(
          id: 't',
          name: 'Cup',
          oversPerInnings: 1,
          hasFinal: true,
          groups: const [
            ['a', 'b'],
            ['c', 'x'],
          ],
          teams: [_team('a'), _team('b'), _team('c'), _team('d')],
          fixtures: const [],
          createdAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });

    test('one league with semi-finals pairs 1 v 4 and 2 v 3', () {
      final start = _tournament(['a', 'b', 'c', 'd'], hasFinal: true, hasSemiFinals: true);
      // a beats everyone, b beats c and d, c beats d.
      String better(Fixture f) => [f.teamAId, f.teamBId].reduce((x, y) => x.compareTo(y) < 0 ? x : y);
      final (t, matches) = _play(start, [for (final f in start.fixtures) better(f)]);
      final p = progressOf(t, matches);
      expect(p.nextRound.map(_pair), [('a', 'd'), ('b', 'c')]);
      expect(p.nextRound.map((f) => f.label), ['Semi-final 1', 'Semi-final 2']);
      expect(p.totalCount, 9);
    });

    test('the final waits for both semi-finals, then pairs the winners', () {
      final start = _tournament(['a', 'b', 'c', 'd'], hasFinal: true, hasSemiFinals: true);
      String better(Fixture f) => [f.teamAId, f.teamBId].reduce((x, y) => x.compareTo(y) < 0 ? x : y);
      var (t, matches) = _play(start, [for (final f in start.fixtures) better(f)]);
      t = t.withFixtures(progressOf(t, matches).nextRound);

      (t, matches) = _record(t, matches, 'sf1', _won(_team('d'), _team('a')));
      expect(progressOf(t, matches).nextRound, isEmpty);

      (t, matches) = _record(t, matches, 'sf2', _won(_team('b'), _team('c')));
      final p = progressOf(t, matches);
      expect(_pair(p.nextRound.single), ('d', 'b'));
      expect(p.nextRound.single.id, finalFixtureId);
    });

    test('two groups give crossed semi-finals', () {
      final start = _tournament(['a', 'b', 'c', 'd'],
          hasFinal: true, hasSemiFinals: true, twoGroups: true);
      // Group A is a and c; group B is b and d.
      final (t, matches) = _play(start, ['a', 'b']);
      final p = progressOf(t, matches);
      expect(p.tables.map((g) => g.name), ['Group A', 'Group B']);
      expect(p.nextRound.map(_pair), [('a', 'd'), ('b', 'c')]);
    });

    test('two groups with a final pair the group winners', () {
      final start = _tournament(['a', 'b', 'c', 'd'], hasFinal: true, twoGroups: true);
      final (t, matches) = _play(start, ['c', 'd']);
      expect(_pair(progressOf(t, matches).nextRound.single), ('c', 'd'));
    });
  });

  group('scheduling', () {
    final start = DateTime(2026, 12, 5, 9);

    test('fills each day, then moves to the next', () {
      final fixtures = _tournament(['a', 'b', 'c', 'd']).fixtures;
      final dated = scheduleFixtures(fixtures, start, perDay: 2);
      expect(dated[0].scheduledAt, DateTime(2026, 12, 5, 9));
      expect(dated[1].scheduledAt, DateTime(2026, 12, 5, 11));
      expect(dated[2].scheduledAt, DateTime(2026, 12, 6, 9));
      expect(dated[5].scheduledAt, DateTime(2026, 12, 7, 11));
    });

    test('runs across the end of a month', () {
      final fixtures = _tournament(['a', 'b', 'c']).fixtures;
      final dated = scheduleFixtures(fixtures, DateTime(2026, 12, 31, 9), perDay: 1);
      expect(dated.last.scheduledAt, DateTime(2027, 1, 2, 9));
    });

    test('needs at least one match a day', () {
      expect(() => scheduleFixtures(const [], start, perDay: 0), throwsArgumentError);
    });

    test('a later round is dated after the latest game', () {
      final base = _tournament(['a', 'b', 'c'], hasFinal: true);
      final dated = base.withCorrected(scheduleFixtures(base.fixtures, start, perDay: 1));
      final added = dated.withFixtures(const [
        Fixture(id: 'final', label: 'Final', teamAId: 'a', teamBId: 'b', knockout: true),
      ]);
      expect(added.finalFixture!.scheduledAt, DateTime(2026, 12, 8, 9));
    });

    test('semi-finals on one day start two hours apart', () {
      final base = _tournament(['a', 'b', 'c', 'd'], hasFinal: true, hasSemiFinals: true);
      final dated = base.withCorrected(scheduleFixtures(base.fixtures, start, perDay: 3));
      final added = dated.withFixtures(const [
        Fixture(id: 'sf1', label: 'S1', teamAId: 'a', teamBId: 'b', knockout: true),
        Fixture(id: 'sf2', label: 'S2', teamAId: 'c', teamBId: 'd', knockout: true),
      ]);
      final gap = added.fixtures.last.scheduledAt!.difference(added.fixtures[6].scheduledAt!);
      expect(gap, const Duration(hours: 2));
    });

    test('an unscheduled tournament stays unscheduled', () {
      final added = _tournament(['a', 'b', 'c'], hasFinal: true).withFixtures(const [
        Fixture(id: 'final', label: 'Final', teamAId: 'a', teamBId: 'b', knockout: true),
      ]);
      expect(added.finalFixture!.scheduledAt, isNull);
    });

    test('one game can move, and linking a match keeps its date', () {
      final base = _tournament(['a', 'b', 'c']);
      final moved = base.withFixtureDate('f1', start).withMatch('f1', 'm1');
      expect(moved.fixtures.first.scheduledAt, start);
      expect(moved.fixtures.first.matchId, 'm1');
      expect(moved.fixtures[1].scheduledAt, isNull);
    });

    test('a date survives a JSON round trip', () {
      final t = _tournament(['a', 'b']).withFixtureDate('f1', DateTime.utc(2026, 12, 5, 3, 30));
      final back = Tournament.fromJson(t.toJson());
      expect(back.fixtures.single.scheduledAt, DateTime.utc(2026, 12, 5, 3, 30));
    });
  });

  group('abandoned games', () {
    MatchState abandoned(Team first, Team second) {
      final at = DateTime.utc(2026);
      final setup = MatchSetup(
        id: 'rain',
        teamA: first,
        teamB: second,
        rules: MatchRules(oversPerInnings: 1),
        tossWinnerId: first.id,
        tossDecision: TossDecision.bat,
      );
      return ScoringEngine.replay(setup, [MatchAbandoned(id: 'e', at: at, reason: 'Rain')]);
    }

    test('an abandoned league game counts as played', () {
      final (t, matches) = _record(_tournament(['a', 'b']), const {}, 'f1', abandoned(_team('a'), _team('b')));
      final p = progressOf(t, matches);
      expect(p.fixtures.single.isFinished, isTrue);
      expect(p.tables.single.teams.map((team) => team.points), [1, 1]);
      expect(p.nextRound, isEmpty);
      expect(p.championId, isNotNull);
    });

    test('an abandoned final goes to a Super Over', () {
      final start = _tournament(['a', 'b', 'c'], hasFinal: true);
      final winners = [
        for (final f in start.fixtures) f.teamAId == 'a' || f.teamBId == 'a' ? 'a' : 'b',
      ];
      var (t, matches) = _play(start, winners);
      t = t.withFixtures(progressOf(t, matches).nextRound);
      (t, matches) = _record(t, matches, 'final', abandoned(_team('a'), _team('b')));

      final p = progressOf(t, matches);
      expect(p.championId, isNull);
      expect(p.nextRound.single.isDecider, isTrue);
    });
  });

  group('player of the tournament', () {
    test('waits for a champion, then is the top MVP', () {
      final start = _tournament(['a', 'b']);
      expect(progressOf(start, const {}).playerOfTheTournament, isNull);

      final (t, matches) = _play(start, ['a']);
      final p = progressOf(t, matches);
      expect(p.championId, 'a');
      expect(p.playerOfTheTournament!.playerId, p.book.mvp.first.playerId);
    });
  });

  group('corrected results', () {
    (Tournament, Map<String, MatchState>) semisPlayed() {
      final start = _tournament(['a', 'b', 'c', 'd'], hasFinal: true, hasSemiFinals: true);
      String better(Fixture f) => [f.teamAId, f.teamBId].reduce((x, y) => x.compareTo(y) < 0 ? x : y);
      var (t, matches) = _play(start, [for (final f in start.fixtures) better(f)]);
      t = t.withFixtures(progressOf(t, matches).nextRound);
      (t, matches) = _record(t, matches, 'sf1', _won(_team('a'), _team('d')));
      (t, matches) = _record(t, matches, 'sf2', _won(_team('b'), _team('c')));
      return (t.withFixtures(progressOf(t, matches).nextRound), matches);
    }

    test('nothing is outdated while results stand', () {
      final (t, matches) = semisPlayed();
      expect(progressOf(t, matches).outdated, isEmpty);
    });

    test('a changed semi-final flags the final with the right teams', () {
      final (t, matches) = semisPlayed();
      final changed = {...matches, 'ko-sf1': _won(_team('d'), _team('a'))};
      final p = progressOf(t, changed);
      final fix = p.outdated.single;
      expect(fix.id, finalFixtureId);
      expect(_pair(fix), ('d', 'b'));

      final corrected = t.withCorrected(p.outdated);
      expect(_pair(corrected.finalFixture!), ('d', 'b'));
      expect(progressOf(corrected, changed).outdated, isEmpty);
    });

    test('home and away order alone is not a difference', () {
      final (t, matches) = semisPlayed();
      final swapped = t.withCorrected(const [
        Fixture(id: 'final', label: 'Final', teamAId: 'b', teamBId: 'a', knockout: true),
      ]);
      expect(progressOf(swapped, matches).outdated, isEmpty);
    });

    test('a semi-final reopened by a deleted match flags nothing yet', () {
      final (t, matches) = semisPlayed();
      final reopened = {...matches}..remove('ko-sf1');
      expect(progressOf(t, reopened).outdated, isEmpty);
    });
  });

  group('tied knockouts', () {
    (Tournament, Map<String, MatchState>) atFinal() {
      final start = _tournament(['a', 'b', 'c'], hasFinal: true);
      final winners = [
        for (final f in start.fixtures) f.teamAId == 'a' || f.teamBId == 'a' ? 'a' : 'b',
      ];
      final (t, matches) = _play(start, winners);
      return (t.withFixtures(progressOf(t, matches).nextRound), matches);
    }

    test('a tied final offers a Super Over, second side batting first', () {
      var (t, matches) = atFinal();
      (t, matches) = _record(t, matches, 'final', _tied(_team('a'), _team('b')));
      final p = progressOf(t, matches);

      expect(p.championId, isNull);
      expect(p.isFinished, isFalse);
      final superOver = p.nextRound.single;
      expect(superOver.isDecider, isTrue);
      expect(superOver.deciderOf, 'final');
      expect(superOver.label, 'Final Super Over');
      expect(_pair(superOver), ('b', 'a'));
    });

    test('winning the Super Over wins the title', () {
      var (t, matches) = atFinal();
      (t, matches) = _record(t, matches, 'final', _tied(_team('a'), _team('b')));
      final superOver = progressOf(t, matches).nextRound.single;
      t = t.withFixtures([superOver]);
      expect(progressOf(t, matches).nextRound, isEmpty, reason: 'it is scheduled now');

      (t, matches) = _record(t, matches, superOver.id, _won(_team('a'), _team('b')));
      final p = progressOf(t, matches);
      expect(p.championId, 'a');
      expect(p.isFinished, isTrue);
      expect(p.nextRound, isEmpty);
    });

    test('a tied Super Over offers another', () {
      var (t, matches) = atFinal();
      (t, matches) = _record(t, matches, 'final', _tied(_team('a'), _team('b')));
      final first = progressOf(t, matches).nextRound.single;
      t = t.withFixtures([first]);
      (t, matches) = _record(t, matches, first.id, _tied(_team('b'), _team('a'), superOver: true));

      final second = progressOf(t, matches).nextRound.single;
      expect(second.label, 'Final Super Over 2');
      expect(_pair(second), ('a', 'b'));
      expect(second.id, isNot(first.id));
      expect(progressOf(t, matches).championId, isNull);
    });

    test('a tied semi-final is settled the same way, and sets up the final', () {
      final start = _tournament(['a', 'b', 'c', 'd'], hasFinal: true, hasSemiFinals: true);
      String better(Fixture f) => [f.teamAId, f.teamBId].reduce((x, y) => x.compareTo(y) < 0 ? x : y);
      var (t, matches) = _play(start, [for (final f in start.fixtures) better(f)]);
      t = t.withFixtures(progressOf(t, matches).nextRound);
      (t, matches) = _record(t, matches, 'sf1', _tied(_team('a'), _team('d')));
      (t, matches) = _record(t, matches, 'sf2', _won(_team('b'), _team('c')));

      final superOver = progressOf(t, matches).nextRound.single;
      expect(superOver.label, 'Semi-final 1 Super Over');
      t = t.withFixtures([superOver]);
      (t, matches) = _record(t, matches, superOver.id, _won(_team('d'), _team('a')));

      expect(_pair(progressOf(t, matches).nextRound.single), ('d', 'b'));
    });

    test('a tied league game has no Super Over, each side takes a point', () {
      final start = _tournament(['a', 'b']);
      final (t, matches) = _record(start, const {}, 'f1', _tied(_team('a'), _team('b')));
      final p = progressOf(t, matches);
      expect(p.nextRound, isEmpty);
      expect(p.tables.single.teams.map((team) => team.points), [1, 1]);
    });

    test('a Super Over ends at two wickets and stays out of stats', () {
      final at = DateTime.utc(2026);
      final team = Team(id: 'x', name: 'X', players: [
        for (var i = 1; i <= 11; i++) Player(id: 'x$i', name: 'X$i'),
      ]);
      final setup = MatchSetup(
        id: 'so',
        teamA: team,
        teamB: _team('b'),
        rules: MatchRules(oversPerInnings: 1, superOver: true),
        tossWinnerId: 'x',
        tossDecision: TossDecision.bat,
      );
      BallBowled out(String id) => BallBowled(
            id: id,
            at: at,
            wicket: Wicket(type: DismissalType.bowled, batterOutId: id),
          );
      final state = ScoringEngine.replay(setup, [
        OpenersSelected(id: 'e1', at: at, strikerId: 'x1', nonStrikerId: 'x2'),
        BowlerChanged(id: 'e2', at: at, bowlerId: 'b1'),
        out('x1'),
        NewBatter(id: 'e3', at: at, batterId: 'x3'),
        out('x3'),
      ]);
      expect(state.phase, MatchPhase.inningsBreak);

      final book = computeStats([_tied(_team('a'), _team('b'), superOver: true)]);
      expect(book.isEmpty, isTrue);
    });

    test('a Super Over keeps two wickets out of reach for small sides', () {
      expect(MatchRules(oversPerInnings: 1, superOver: true).maxWicketsFor(2), 1);
      expect(MatchRules(oversPerInnings: 1, superOver: true).maxWicketsFor(11), 2);
      expect(MatchRules(oversPerInnings: 1).maxWicketsFor(11), 10);
    });
  });

  group('storage', () {
    test('survives a JSON round trip', () {
      final t = _tournament(['a', 'b', 'c'], hasFinal: true, venue: 'Ground')
          .withMatch('f1', 'm1')
          .withFixtures(const [
        Fixture(id: 'final', label: 'Final', teamAId: 'a', teamBId: 'b', knockout: true),
      ]);
      final back = Tournament.fromJson(t.toJson());
      expect(back.toJson(), t.toJson());
      expect(back.fixtures.first.matchId, 'm1');
      expect(back.finalFixture!.knockout, isTrue);
    });

    test('a missing knockout field reads as a league game', () {
      final f = Fixture.fromJson(const {'id': 'x', 'label': 'L', 'teamAId': 'a', 'teamBId': 'b'});
      expect(f.knockout, isFalse);
      expect(f.matchId, isNull);
      expect(f.isDecider, isFalse);
    });

    test('a tournament saved before formats existed still reads', () {
      final old = _tournament(['a', 'b', 'c']).toJson()
        ..remove('legs')
        ..remove('groups')
        ..remove('hasSemiFinals');
      final back = Tournament.fromJson(old);
      expect(back.legs, 1);
      expect(back.hasSemiFinals, isFalse);
      expect(back.groups.single, ['a', 'b', 'c']);
    });

    test('groups, legs and Super Overs survive a round trip', () {
      final t = _tournament(['a', 'b', 'c', 'd'],
              hasFinal: true, hasSemiFinals: true, twoGroups: true, legs: 2)
          .withFixtures(const [
        Fixture(id: 'so', label: 'SO', teamAId: 'a', teamBId: 'b', knockout: true, deciderOf: 'final'),
      ]);
      final back = Tournament.fromJson(t.toJson());
      expect(back.toJson(), t.toJson());
      expect(back.fixtures.last.deciderOf, 'final');
    });

    test('rules saved before Super Overs existed still read', () {
      final json = MatchRules(oversPerInnings: 5).toJson()..remove('superOver');
      expect(MatchRules.fromJson(json).superOver, isFalse);
      expect(MatchRules.fromJson(MatchRules(oversPerInnings: 1, superOver: true).toJson()).superOver, isTrue);
    });
  });

  group('knockout cup', () {
    List<(String, String)> sides(List<BracketGame> games, Tournament t) =>
        [for (final g in games) (t.sideName(g.a), t.sideName(g.b))];

    test('eight teams pair in draw order, then winners meet', () {
      final t = _cup(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
      expect([for (final g in t.bracket) g.id], ['qf1', 'qf2', 'qf3', 'qf4', 'sf1', 'sf2', 'final']);
      expect([for (final f in t.fixtures) _pair(f)], [('a', 'b'), ('c', 'd'), ('e', 'f'), ('g', 'h')]);
      expect(t.fixtures.every((f) => f.knockout), isTrue);
      expect(sides(t.bracket.skip(4).toList(), t), [
        ('Winner of Quarter-final 1', 'Winner of Quarter-final 2'),
        ('Winner of Quarter-final 3', 'Winner of Quarter-final 4'),
        ('Winner of Semi-final 1', 'Winner of Semi-final 2'),
      ]);
    });

    test('twelve teams: the first four get byes, each to meet a first-round winner', () {
      final t = _cup([for (var i = 0; i < 12; i++) String.fromCharCode(97 + i)]);
      final opening = t.bracket.where((g) => g.round == 'Round of 16').toList();
      expect([for (final g in opening) g.label], [
        'Round of 16 Match 1',
        'Round of 16 Match 2',
        'Round of 16 Match 3',
        'Round of 16 Match 4',
      ]);
      expect([for (final f in t.fixtures) _pair(f)], [('e', 'f'), ('g', 'h'), ('i', 'j'), ('k', 'l')]);
      expect(sides(t.bracket.where((g) => g.round == 'Quarter-final').toList(), t), [
        ('Team A', 'Winner of Round of 16 Match 1'),
        ('Team B', 'Winner of Round of 16 Match 2'),
        ('Team C', 'Winner of Round of 16 Match 3'),
        ('Team D', 'Winner of Round of 16 Match 4'),
      ]);
    });

    test('a round with one game has no number', () {
      final three = _cup(['a', 'b', 'c']);
      expect([for (final g in three.bracket) g.label], ['Semi-final', 'Final']);
      expect(sides(three.bracket, three), [('Team B', 'Team C'), ('Team A', 'Winner of Semi-final')]);

      final five = _cup(['a', 'b', 'c', 'd', 'e']);
      expect([for (final g in five.bracket) g.label], ['Quarter-final', 'Semi-final 1', 'Semi-final 2', 'Final']);
      expect(sides(five.bracket, five).sublist(1, 3), [
        ('Team A', 'Winner of Quarter-final'),
        ('Team B', 'Team C'),
      ]);
    });

    test('any size: every team is drawn once and every winner goes on once', () {
      for (var n = 3; n <= maxKnockoutTeams; n++) {
        final ids = [for (var i = 0; i < n; i++) 't$i'];
        final games = knockoutBracket(ids);
        expect(games, hasLength(n - 1), reason: '$n teams');
        expect(games.map((g) => g.id).toSet(), hasLength(n - 1));
        expect(games.last.id, finalFixtureId);
        final drawn = [
          for (final g in games)
            for (final side in [g.a, g.b])
              if (side case DrawnTeam(:final teamId)) teamId,
        ];
        expect(drawn..sort(), [...ids]..sort(), reason: '$n teams');
        final fed = [
          for (final g in games)
            for (final side in [g.a, g.b])
              if (side case WinnerOf(:final fixtureId)) fixtureId,
        ];
        expect(fed..sort(), [for (final g in games.take(n - 2)) g.id]..sort(), reason: '$n teams');
      }
    });

    test('each game opens as soon as its two teams are known, through to a champion', () {
      var t = _cup(['a', 'b', 'c', 'd', 'e', 'f']);
      var matches = <String, MatchState>{};
      var p = progressOf(t, matches);
      expect(p.nextRound, isEmpty);
      expect(p.totalCount, 5);
      expect(p.bracketTeams['sf1'], ('a', null));
      expect(p.tables.single.teams, hasLength(6), reason: 'a cup has no league, but stats list every team');

      (t, matches) = _win(t, matches, 'qf1', 'c');
      p = progressOf(t, matches);
      expect([for (final f in p.nextRound) (f.id, _pair(f))], [('sf1', ('a', 'c'))],
          reason: 'the semi-final need not wait for the other quarter-final');

      t = t.withFixtures(p.nextRound);
      (t, matches) = _win(t, matches, 'qf2', 'f');
      t = t.withFixtures(progressOf(t, matches).nextRound);
      (t, matches) = _win(t, matches, 'sf1', 'a');
      (t, matches) = _win(t, matches, 'sf2', 'f');
      p = progressOf(t, matches);
      expect(p.championId, isNull);
      expect(_pair(p.nextRound.single), ('a', 'f'));

      t = t.withFixtures(p.nextRound);
      (t, matches) = _win(t, matches, finalFixtureId, 'f');
      p = progressOf(t, matches);
      expect(p.championId, 'f');
      expect(p.winners, {'qf1': 'c', 'qf2': 'f', 'sf1': 'a', 'sf2': 'f', finalFixtureId: 'f'});
      expect(p.finishedCount, 5);
      expect(p.totalCount, 5);
      expect(p.nextRound, isEmpty);
    });

    test('a tied game goes to a Super Over, and its winner goes on', () {
      var t = _cup(['a', 'b', 'c']);
      var matches = <String, MatchState>{};
      (t, matches) = _record(t, matches, 'sf1', _tied(_team('b'), _team('c')));
      var p = progressOf(t, matches);
      final superOver = p.nextRound.single;
      expect(superOver.deciderOf, 'sf1');
      expect(superOver.label, 'Semi-final Super Over');

      t = t.withFixtures(p.nextRound);
      (t, matches) = _win(t, matches, superOver.id, 'c');
      p = progressOf(t, matches);
      expect(_pair(p.nextRound.single), ('a', 'c'));
      expect(p.winners['sf1'], 'c', reason: 'the Super Over decides who went through');
    });

    test('a corrected result flags the next game', () {
      var t = _cup(['a', 'b', 'c']);
      var matches = <String, MatchState>{};
      (t, matches) = _win(t, matches, 'sf1', 'b');
      t = t.withFixtures(progressOf(t, matches).nextRound);
      final changed = {...matches, 'ko-sf1': _won(_team('c'), _team('b'))};
      expect(_pair(progressOf(t, changed).outdated.single), ('a', 'c'));
    });

    test('rejects shapes a cup cannot have', () {
      final teams = [for (final id in ['a', 'b', 'c', 'd']) _team(id)];
      Tournament cup({bool hasFinal = true, bool semis = false, int legs = 1, List<List<String>>? groups}) =>
          Tournament(
            id: 'c',
            name: 'C',
            oversPerInnings: 1,
            hasFinal: hasFinal,
            hasSemiFinals: semis,
            legs: legs,
            groups: groups,
            format: TournamentFormat.knockout,
            teams: teams,
            fixtures: const [],
            createdAt: DateTime.utc(2026),
          );
      expect(cup, returnsNormally);
      expect(() => cup(hasFinal: false), throwsArgumentError);
      expect(() => cup(semis: true), throwsArgumentError);
      expect(() => cup(legs: 2), throwsArgumentError);
      expect(() => cup(groups: splitIntoTwoGroups(teams)), throwsArgumentError);
      expect(() => _cup([for (var i = 0; i <= maxKnockoutTeams; i++) 't$i']), throwsArgumentError);
    });
  });

  group('quarter-finals after a league', () {
    final eight = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

    test('one league sends the top eight: 1 v 8, 4 v 5, 2 v 7, 3 v 6', () {
      final start = _tournament(eight, hasFinal: true, hasSemiFinals: true, hasQuarterFinals: true);
      var (t, matches) = _play(start, [for (final f in start.fixtures) _better(f)]);
      final p = progressOf(t, matches);
      expect([for (final f in p.nextRound) (f.label, _pair(f))], [
        ('Quarter-final 1', ('a', 'h')),
        ('Quarter-final 2', ('d', 'e')),
        ('Quarter-final 3', ('b', 'g')),
        ('Quarter-final 4', ('c', 'f')),
      ]);
      expect(p.totalCount, 28 + 7);
      expect(start.sideName(start.bracket.first.b), '8th in the table');

      t = t.withFixtures(p.nextRound);
      for (final (id, winner) in [('qf1', 'a'), ('qf2', 'd'), ('qf3', 'b'), ('qf4', 'c')]) {
        (t, matches) = _win(t, matches, id, winner);
      }
      expect([for (final f in progressOf(t, matches).nextRound) _pair(f)], [('a', 'd'), ('b', 'c')]);
    });

    test('two groups cross over, so a group\'s top two meet only in the final', () {
      final start = _tournament(eight,
          hasFinal: true, hasSemiFinals: true, hasQuarterFinals: true, twoGroups: true);
      final (t, matches) = _play(start, [for (final f in start.fixtures) _better(f)]);
      // Group A is a, c, e, g and group B is b, d, f, h, each in that order.
      expect([for (final f in progressOf(t, matches).nextRound) _pair(f)], [
        ('a', 'h'),
        ('d', 'e'),
        ('b', 'g'),
        ('c', 'f'),
      ]);
      expect(start.sideName(start.bracket.first.b), 'Group B 4th');
    });

    test('rejects quarter-finals without semi-finals or enough teams', () {
      expect(() => _tournament(eight, hasFinal: true, hasQuarterFinals: true), throwsArgumentError);
      expect(
        () => _tournament(eight.take(7).toList(), hasFinal: true, hasSemiFinals: true, hasQuarterFinals: true),
        throwsArgumentError,
      );
      expect(
        () => _tournament(eight.take(7).toList(),
            hasFinal: true, hasSemiFinals: true, hasQuarterFinals: true, twoGroups: true),
        throwsArgumentError,
        reason: 'a group of 3 has no 4th place',
      );
    });

    test('a league without a final has no bracket', () {
      final t = _tournament(['a', 'b', 'c']);
      expect(t.bracket, isEmpty);
      expect(progressOf(t, const {}).bracketTeams, isEmpty);
    });
  });

  group('prizes, entry fees and notes', () {
    Tournament withMoney() => _tournament(['a', 'b', 'c']).withDetails(
          prizes: const [
            Prize(title: 'Winner', reward: 'Rs 25,000 + trophy'),
            Prize(title: 'Player of the series', reward: 'Bat'),
          ],
          entryFee: 2500,
          rules: '  Tennis ball. Fees not refundable.  ',
        );

    test('what each team has paid and still owes', () {
      final t = withMoney().withPaid('a', 1000).withPaid('b', 3000);
      expect(t.paidBy('a'), 1000);
      expect(t.dueFrom('a'), 1500);
      expect(t.dueFrom('b'), 0, reason: 'paying more never shows a negative balance');
      expect(t.dueFrom('c'), 2500);
      expect(t.withPaid('a', 0).paid.containsKey('a'), isFalse);
      expect(_tournament(['a', 'b']).dueFrom('a'), isNull, reason: 'no entry fee');
    });

    test('notes are trimmed, and details can be cleared', () {
      final t = withMoney();
      expect(t.rules, 'Tennis ball. Fees not refundable.');
      final cleared = t.withDetails(prizes: const [], entryFee: null, rules: '   ');
      expect(cleared.prizes, isEmpty);
      expect(cleared.entryFee, isNull);
      expect(cleared.rules, isNull);
    });

    test('rejects a blank prize, a zero fee, and payments that make no sense', () {
      final t = _tournament(['a', 'b']);
      expect(() => t.withDetails(prizes: const [Prize(title: 'Winner', reward: ' ')], entryFee: null, rules: null),
          throwsArgumentError);
      expect(() => t.withDetails(prizes: const [], entryFee: 0, rules: null), throwsArgumentError);
      expect(() => t.withPaid('zz', 100), throwsArgumentError);
      expect(() => t.withPaid('a', -1), throwsArgumentError);
    });

    test('everything survives a round trip, and the public copy leaves out payments', () {
      final t = withMoney().withPaid('a', 1000);
      final back = Tournament.fromJson(t.toJson());
      expect(back.toJson(), t.toJson());
      expect(back.prizes.first.reward, 'Rs 25,000 + trophy');
      expect(back.paidBy('a'), 1000);

      final public = t.toPublicJson();
      expect(public.containsKey('paid'), isFalse);
      expect(public['entryFee'], 2500);
      expect(Tournament.fromJson(public).paid, isEmpty);
    });

    test('a cup and its quarter-finals survive a round trip', () {
      final cup = _cup(['a', 'b', 'c', 'd', 'e']);
      expect(Tournament.fromJson(cup.toJson()).isKnockout, isTrue);
      final league = _tournament(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
          hasFinal: true, hasSemiFinals: true, hasQuarterFinals: true);
      expect(Tournament.fromJson(league.toJson()).hasQuarterFinals, isTrue);
    });

    test('a plain league is stored exactly as before these fields existed', () {
      final json = _tournament(['a', 'b', 'c']).toJson();
      for (final key in ['format', 'hasQuarterFinals', 'prizes', 'entryFee', 'paid', 'rules']) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      expect((json['fixtures']! as List<Object?>).every((f) => !(f! as Json).containsKey('venue')), isTrue);
    });
  });

  group('a ground per fixture', () {
    test('names the match, and a blank one falls back to the tournament\'s', () {
      final t = _tournament(['a', 'b'], venue: 'Oval');
      final moved = t.withFixtureVenue('f1', ' Park ');
      expect(moved.titleOf(moved.fixtures.single), 'Cup Match 1 · Park');
      final back = moved.withFixtureVenue('f1', '  ');
      expect(back.titleOf(back.fixtures.single), 'Cup Match 1 · Oval');
    });

    test('is kept when the match starts or the date moves, and survives storage', () {
      final t = _tournament(['a', 'b'])
          .withFixtureVenue('f1', 'Park')
          .withMatch('f1', 'm1')
          .withFixtureDate('f1', DateTime.utc(2026, 12, 1, 9));
      final f = Tournament.fromJson(t.toJson()).fixtures.single;
      expect(f.venue, 'Park');
      expect(f.matchId, 'm1');
      expect(f.scheduledAt, DateTime.utc(2026, 12, 1, 9));
      expect(f.withDate(null).venue, 'Park');
    });
  });

  test('titles name the fixture and the ground', () {
    final fixture = _tournament(['a', 'b']).fixtures.single;
    expect(_tournament(['a', 'b']).titleOf(fixture), 'Cup Match 1');
    expect(_tournament(['a', 'b'], venue: 'Oval').titleOf(fixture), 'Cup Match 1 · Oval');
  });

  test('stats can list teams yet to play', () {
    final book = computeStats(const [], entrants: [_team('a')]);
    expect(book.isEmpty, isTrue);
    expect(book.teams.single.name, 'Team A');
  });
}
