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
