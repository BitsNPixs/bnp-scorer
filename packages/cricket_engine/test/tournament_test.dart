import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

Team _team(String id) => Team(
      id: id,
      name: 'Team ${id.toUpperCase()}',
      players: [
        for (var i = 1; i <= 3; i++) Player(id: '$id$i', name: 'Player $id$i'),
      ],
    );

Tournament _tournament(List<String> ids, {bool hasFinal = false, String? venue}) {
  final teams = [for (final id in ids) _team(id)];
  return Tournament(
    id: 't',
    name: 'Cup',
    oversPerInnings: 1,
    hasFinal: hasFinal,
    teams: teams,
    fixtures: roundRobinFixtures(teams),
    createdAt: DateTime.utc(2026),
    venue: venue,
  );
}

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
      expect(p.table, hasLength(3));
      expect(p.table.every((t) => t.played == 0 && t.netRunRate == null), isTrue);
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
      expect(p.table.first.teamId, 'a');
      expect(p.table.first.points, 4);
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
      expect(p.finalists!.$1.teamId, 'a');
      expect(p.finalists!.$2.teamId, 'b');
      expect(p.championId, isNull);
      expect(p.isFinished, isFalse);
      expect(p.totalCount, 4);
    });

    test('no finalists while a league game is unplayed', () {
      final start = _tournament(['a', 'b', 'c'], hasFinal: true);
      final (t, matches) = _play(start, [start.fixtures[0].teamAId]);
      expect(progressOf(t, matches).finalists, isNull);
    });

    test('the final decides the champion and stays out of the table', () {
      final start = _tournament(['a', 'b', 'c'], hasFinal: true);
      final winners = [
        for (final f in start.fixtures) f.teamAId == 'a' || f.teamBId == 'a' ? 'a' : 'b',
      ];
      final (league, matches) = _play(start, winners);
      final withFinal = league.withFinal('a', 'b');
      expect(progressOf(withFinal, matches).finalists, isNull);

      final done = withFinal.withMatch('final', 'final-match');
      final p = progressOf(done, {...matches, 'final-match': _won(_team('b'), _team('a'))});

      expect(p.championId, 'b');
      expect(p.isFinished, isTrue);
      expect(p.table.first.teamId, 'a', reason: 'the final does not change the table');
      expect(p.table.first.played, 2);
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
      expect(p.table.every((t) => t.played == 0), isTrue);
    });
  });

  group('storage', () {
    test('survives a JSON round trip', () {
      final t = _tournament(['a', 'b', 'c'], hasFinal: true, venue: 'Ground')
          .withMatch('f1', 'm1')
          .withFinal('a', 'b');
      final back = Tournament.fromJson(t.toJson());
      expect(back.toJson(), t.toJson());
      expect(back.fixtures.first.matchId, 'm1');
      expect(back.finalFixture!.knockout, isTrue);
    });

    test('a missing knockout field reads as a league game', () {
      final f = Fixture.fromJson(const {'id': 'x', 'label': 'L', 'teamAId': 'a', 'teamBId': 'b'});
      expect(f.knockout, isFalse);
      expect(f.matchId, isNull);
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
