import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

Team _team(String id, int size) => Team(
      id: id,
      name: 'Team ${id.toUpperCase()}',
      players: [
        for (var i = 1; i <= size; i++) Player(id: '$id$i', name: 'Player $id$i'),
      ],
    );

MatchSetup _setup({int size = 3, int overs = 1, String a = 'a', String b = 'b', int ballsPerOver = 6}) =>
    MatchSetup(
      id: 'm',
      teamA: _team(a, size),
      teamB: _team(b, size),
      rules: MatchRules(oversPerInnings: overs, ballsPerOver: ballsPerOver),
      tossWinnerId: a,
      tossDecision: TossDecision.bat,
    );

/// Records events the way the app does, and replays them for a state.
class _Match {
  _Match(this.setup);

  final MatchSetup setup;
  final _events = <MatchEvent>[];

  String get _id => 'e${_events.length}';
  final _at = DateTime.utc(2026);

  void openers(String striker, String nonStriker) =>
      _events.add(OpenersSelected(id: _id, at: _at, strikerId: striker, nonStrikerId: nonStriker));

  void bowler(String id) => _events.add(BowlerChanged(id: _id, at: _at, bowlerId: id));

  void balls(List<int> runs) {
    for (final r in runs) {
      _events.add(BallBowled(id: _id, at: _at, runsOffBat: r, boundary: r == 4 || r == 6));
    }
  }

  void wicket(DismissalType type, String out, {String? fielder, int runs = 0}) =>
      _events.add(BallBowled(
        id: _id,
        at: _at,
        runsOffBat: runs,
        wicket: Wicket(type: type, batterOutId: out, fielderId: fielder),
      ));

  void newBatter(String id) => _events.add(NewBatter(id: _id, at: _at, batterId: id));

  MatchState get state => ScoringEngine.replay(setup, _events);
}

/// Team A 11/1 in an over, Team B 2/1 in an over. Team A wins by 9 runs.
MatchState _aBeatsB({String a = 'a', String b = 'b'}) =>
    _playAWin(_Match(_setup(a: a, b: b)), a, b).state;

_Match _playAWin(_Match m, String a, String b) => m
    ..openers('${a}1', '${a}2')
    ..bowler('${b}1')
    ..balls([4, 6])
    ..wicket(DismissalType.caught, '${a}1', fielder: '${b}2')
    ..newBatter('${a}3')
    ..balls([1, 0, 0])
    ..openers('${b}1', '${b}2')
    ..bowler('${a}1')
    ..balls([1, 1])
    ..wicket(DismissalType.bowled, '${b}1')
    ..newBatter('${b}3')
    ..balls([0, 0, 0]);

PlayerStats _player(StatsBook book, String id) => book.players.firstWhere((p) => p.playerId == id);

TeamStats _teamStats(StatsBook book, String id) => book.teams.firstWhere((t) => t.teamId == id);

void main() {
  group('batting', () {
    final book = computeStats([_aBeatsB()]);

    test('adds up an innings', () {
      final b = _player(book, 'a1').batting;
      expect(b.innings, 1);
      expect(b.runs, 10);
      expect(b.balls, 3);
      expect(b.fours, 1);
      expect(b.sixes, 1);
      expect(b.notOuts, 0);
      expect(b.average, 10);
      expect(b.strikeRate, closeTo(333.33, 0.01));
      expect(b.high!.runs, 10);
      expect(b.high!.notOut, isFalse);
    });

    test('a batter never out has no average', () {
      final b = _player(book, 'a3').batting;
      expect(b.notOuts, 1);
      expect(b.average, isNull);
      expect(b.high!.notOut, isTrue);
    });

    test('a non-striker who faced no ball still counts as an innings', () {
      final m = _Match(_setup())
        ..openers('a1', 'a2')
        ..bowler('b1')
        ..balls([0, 0, 0, 0, 0, 0]);
      m.openers('b1', 'b2');
      m.bowler('a1');
      m.balls([0, 0, 0, 0, 0, 0]);
      final b = _player(computeStats([m.state]), 'a2').batting;
      expect(b.innings, 1);
      expect(b.balls, 0);
      expect(b.strikeRate, isNull);
    });

    test('a player who did not bat has no innings', () {
      expect(_player(book, 'b3').batting.innings, 1);
      final m = _Match(_setup(size: 4))
        ..openers('a1', 'a2')
        ..bowler('b1')
        ..balls([1, 1, 1, 1, 1, 1])
        ..openers('b1', 'b2')
        ..bowler('a1')
        ..balls([0, 0, 0, 0, 0, 0]);
      final stats = computeStats([m.state]);
      expect(_player(stats, 'a4').matches, 1);
      expect(_player(stats, 'a4').batting.innings, 0);
      expect(stats.batters.map((p) => p.playerId), isNot(contains('a4')));
    });

    test('fifties and hundreds are counted apart', () {
      // 31 an over, and the last-ball single keeps a1 on strike.
      BattingStats overs(int count) {
        final m = _Match(_setup(size: 2, overs: 20))..openers('a1', 'a2');
        for (var over = 0; over < count; over++) {
          m
            ..bowler(over.isEven ? 'b1' : 'b2')
            ..balls([6, 6, 6, 6, 6, 1]);
        }
        return _player(computeStats([_finished(m)]), 'a1').batting;
      }

      expect(overs(1).runs, 31);
      expect(overs(1).fifties, 0);
      expect(overs(2).runs, 62);
      expect(overs(2).fifties, 1);
      expect(overs(4).runs, 124);
      expect(overs(4).fifties, 0);
      expect(overs(4).hundreds, 1);
    });

    test('a not-out score beats the same score out', () {
      const out = HighScore(runs: 30, notOut: false);
      const notOut = HighScore(runs: 30, notOut: true);
      expect(notOut.beats(out), isTrue);
      expect(out.beats(notOut), isFalse);
    });
  });

  group('bowling', () {
    final book = computeStats([_aBeatsB()]);

    test('adds up a spell', () {
      final b = _player(book, 'b1').bowling;
      expect(b.innings, 1);
      expect(b.legalBalls, 6);
      expect(b.oversText, '1');
      expect(b.runs, 11);
      expect(b.wickets, 1);
      expect(b.economy, 11);
      expect(b.average, 11);
      expect(b.strikeRate, 6);
      expect(b.best!.wickets, 1);
      expect(b.best!.runs, 11);
    });

    test('run outs are not credited to the bowler', () {
      final m = _Match(_setup())
        ..openers('a1', 'a2')
        ..bowler('b1')
        ..wicket(DismissalType.runOut, 'a1', fielder: 'b3');
      final stats = computeStats([_finished(m)]);
      expect(_player(stats, 'b1').bowling.wickets, 0);
      expect(_player(stats, 'b3').fielding.runOuts, 1);
    });

    test('more wickets beat cheaper figures, then fewer runs decide', () {
      const three = BestBowling(wickets: 3, runs: 30);
      const two = BestBowling(wickets: 2, runs: 5);
      const twoDear = BestBowling(wickets: 2, runs: 9);
      expect(three.beats(two), isTrue);
      expect(two.beats(twoDear), isTrue);
      expect(twoDear.beats(two), isFalse);
    });

    test('a bowler without a wicket has no average or strike rate', () {
      const b = BowlingStats(legalBalls: 6, runs: 4);
      expect(b.average, isNull);
      expect(b.strikeRate, isNull);
      expect(b.economy, 4);
    });
  });

  group('fielding', () {
    test('catches and stumpings go to the fielder', () {
      final m = _Match(_setup(size: 4))
        ..openers('a1', 'a2')
        ..bowler('b1')
        ..wicket(DismissalType.caught, 'a1', fielder: 'b2')
        ..newBatter('a3')
        ..wicket(DismissalType.stumped, 'a3', fielder: 'b3');
      final stats = computeStats([_finished(m)]);
      expect(_player(stats, 'b2').fielding.catches, 1);
      expect(_player(stats, 'b3').fielding.stumpings, 1);
    });

    test('a catch with no fielder recorded is simply not counted', () {
      final m = _Match(_setup())
        ..openers('a1', 'a2')
        ..bowler('b1')
        ..wicket(DismissalType.caught, 'a1');
      final stats = computeStats([_finished(m)]);
      expect(stats.players.every((p) => p.fielding.catches == 0), isTrue);
    });
  });

  group('teams', () {
    test('win, loss, points and totals', () {
      final book = computeStats([_aBeatsB()]);
      final a = _teamStats(book, 'a');
      final b = _teamStats(book, 'b');
      expect(a.played, 1);
      expect(a.won, 1);
      expect(a.points, 2);
      expect(a.highest, 11);
      expect(a.lowest, 11);
      expect(a.runsFor, 11);
      expect(a.runsAgainst, 2);
      expect(a.form, [MatchOutcome.won]);
      expect(b.lost, 1);
      expect(b.points, 0);
      expect(b.form, [MatchOutcome.lost]);
    });

    test('net run rate is scored rate minus conceded rate', () {
      final book = computeStats([_aBeatsB()]);
      expect(_teamStats(book, 'a').netRunRate, closeTo(9, 0.001));
      expect(_teamStats(book, 'b').netRunRate, closeTo(-9, 0.001));
    });

    test('a side bowled out is charged its full overs', () {
      final m = _Match(_setup(size: 2, overs: 2))
        ..openers('a1', 'a2')
        ..bowler('b1')
        ..balls([4])
        ..wicket(DismissalType.bowled, 'a1')
        ..openers('b1', 'b2')
        ..bowler('a1')
        ..balls([1, 1, 1, 1, 1]);
      final state = m.state;
      expect(state.isCompleted, isTrue, reason: 'Team B chased 5 in the over');
      final a = _teamStats(computeStats([state]), 'a');
      expect(a.oversFaced, 2);
      expect(a.oversBowled, closeTo(5 / 6, 0.001));
    });

    test('a chase that ends early uses the overs actually faced', () {
      final m = _Match(_setup())
        ..openers('a1', 'a2')
        ..bowler('b1')
        ..balls([1, 0, 0, 0, 0, 0])
        ..openers('b1', 'b2')
        ..bowler('a1')
        ..balls([6]);
      expect(_teamStats(computeStats([m.state]), 'b').oversFaced, closeTo(1 / 6, 0.001));
    });

    test('a tie gives each side a point', () {
      final m = _Match(_setup())
        ..openers('a1', 'a2')
        ..bowler('b1')
        ..balls([1, 0, 0, 0, 0, 0])
        ..openers('b1', 'b2')
        ..bowler('a1')
        ..balls([1, 0, 0, 0, 0, 0]);
      final book = computeStats([m.state]);
      expect(_teamStats(book, 'a').tied, 1);
      expect(_teamStats(book, 'a').points, 1);
      expect(_teamStats(book, 'b').points, 1);
      expect(_teamStats(book, 'a').form, [MatchOutcome.tied]);
    });

    test('form keeps the order the matches were played in', () {
      final won = _aBeatsB();
      final lost = _aBeatsB(a: 'c', b: 'a');
      expect(_teamStats(computeStats([won, lost]), 'a').form, [MatchOutcome.won, MatchOutcome.lost]);
      expect(_teamStats(computeStats([lost, won]), 'a').form, [MatchOutcome.lost, MatchOutcome.won]);
    });

    test('points rank first, then net run rate', () {
      // a and c each win once; a by more, so a leads.
      final narrow = _Match(_setup(a: 'c', b: 'd'))
        ..openers('c1', 'c2')
        ..bowler('d1')
        ..balls([1, 1, 0, 0, 0, 0])
        ..openers('d1', 'd2')
        ..bowler('c1')
        ..balls([0, 0, 0, 0, 0, 0]);
      final book = computeStats([narrow.state, _aBeatsB()]);
      expect(book.teams.map((t) => t.teamId), ['a', 'c', 'd', 'b']);
    });
  });

  group('no result', () {
    MatchState abandoned() {
      final m = _Match(_setup())
        ..openers('a1', 'a2')
        ..bowler('b1')
        ..balls([6, 4]);
      return ScoringEngine.replay(m.setup, [
        ...m._events,
        MatchAbandoned(id: 'x', at: m._at, reason: 'Rain'),
      ]);
    }

    test('gives each side a point', () {
      final book = computeStats([abandoned()]);
      for (final id in ['a', 'b']) {
        final team = _teamStats(book, id);
        expect(team.noResults, 1);
        expect(team.played, 1);
        expect(team.points, 1);
        expect(team.form, [MatchOutcome.noResult]);
      }
    });

    test('stays out of net run rate and totals', () {
      final a = _teamStats(computeStats([abandoned()]), 'a');
      expect(a.netRunRate, isNull);
      expect(a.runsFor, 0);
      expect(a.highest, 0);
    });

    test('a side with results keeps its net run rate', () {
      final a = _teamStats(computeStats([_aBeatsB(), abandoned()]), 'a');
      expect(a.netRunRate, closeTo(9, 0.001));
      expect(a.points, 3);
    });

    test('runs still count for the batter', () {
      expect(_player(computeStats([abandoned()]), 'a1').batting.runs, 10);
    });
  });

  group('the book', () {
    test('adds a player up across matches under one id', () {
      final book = computeStats([_aBeatsB(), _aBeatsB()]);
      final p = _player(book, 'a1');
      expect(book.matches, 2);
      expect(p.matches, 2);
      expect(p.batting.innings, 2);
      expect(p.batting.runs, 20);
      expect(p.bowling.innings, 2);
    });

    test('leaves unfinished matches out', () {
      final live = _Match(_setup())
        ..openers('a1', 'a2')
        ..bowler('b1')
        ..balls([6]);
      final book = computeStats([_aBeatsB(), live.state]);
      expect(book.matches, 1);
      expect(_player(book, 'a1').batting.runs, 10);
    });

    test('no finished matches gives an empty book', () {
      final book = computeStats(const []);
      expect(book.isEmpty, isTrue);
      expect(book.teams, isEmpty);
      expect(book.batters, isEmpty);
    });

    test('lists batters by runs and bowlers by wickets', () {
      final book = computeStats([_aBeatsB()]);
      expect(book.batters.first.playerId, 'a1');
      expect(book.bowlers.map((p) => p.playerId).take(2), containsAll(['a1', 'b1']));
      final cheapest = book.bowlers.first;
      expect(cheapest.bowling.runs, lessThan(book.bowlers[1].bowling.runs));
    });

    test('a renamed team uses its latest name', () {
      final first = _aBeatsB();
      final renamed = MatchSetup(
        id: 'm2',
        teamA: Team(id: 'a', name: 'New name', players: first.setup.teamA.players),
        teamB: first.setup.teamB,
        rules: first.setup.rules,
        tossWinnerId: 'a',
        tossDecision: TossDecision.bat,
      );
      final book = computeStats([first, _playAWin(_Match(renamed), 'a', 'b').state]);
      expect(_teamStats(book, 'a').name, 'New name');
      expect(_teamStats(book, 'a').played, 2);
      expect(_player(book, 'a1').teamName, 'New name');
    });

    test('overs are reported in six-ball overs for an eight-ball match', () {
      final m = _Match(_setup(ballsPerOver: 8))
        ..openers('a1', 'a2')
        ..bowler('b1')
        ..balls([0, 0, 0, 0, 0, 0, 0, 0])
        ..openers('b1', 'b2')
        ..bowler('a1')
        ..balls([0, 0, 0, 0, 0, 0, 0, 0]);
      final book = computeStats([m.state]);
      expect(_player(book, 'b1').bowling.oversText, '1.2');
      expect(_teamStats(book, 'a').oversFaced, 1);
    });
  });
}

/// Closes the current innings and a second one, so [m] counts as finished.
MatchState _finished(_Match m) {
  final closed = [
    ...m._events,
    InningsClosed(id: 'x1', at: m._at, reason: 'test'),
    OpenersSelected(id: 'x2', at: m._at, strikerId: 'b1', nonStrikerId: 'b2'),
    InningsClosed(id: 'x3', at: m._at, reason: 'test'),
  ];
  return ScoringEngine.replay(m.setup, closed);
}
