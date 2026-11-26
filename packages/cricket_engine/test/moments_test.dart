import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'engine_test.dart' show Scorer, setup;

/// The moment the scorer's last event made.
MatchMoment? last(Scorer s) =>
    momentOf(ScoringEngine.replay(s.setup, s.events.sublist(0, s.events.length - 1)), s.state);

/// Bowls [play] as the next ball: a new bowler (b1 and b2 in turn) when an
/// over is done, and [striker], if given, back on strike first.
void ball(Scorer s, void Function() play, {String? striker}) {
  if (s.state.phase == MatchPhase.awaitingBowler) s.bowler(s.inn.lastOverBowlerId == 'b1' ? 'b2' : 'b1');
  if (striker != null && s.inn.strikerId != striker) s.swap();
  play();
}

void main() {
  test('the first ball starts the match, and nothing before it does', () {
    final s = Scorer(setup())..openers('a1', 'a2');
    expect(last(s), isNull);
    s.bowler('b1');
    expect(last(s), isNull);
    s.runs(1);
    expect(last(s), const MatchMoment(MomentKind.started));
    s.runs(1);
    expect(last(s), isNull, reason: 'an ordinary ball');
  });

  test('a wicket names the batter out; a retirement hurt is no wicket', () {
    final s = Scorer(setup(overs: 5))
      ..start()
      ..runs(1);
    s.out(DismissalType.bowled);
    expect(last(s), const MatchMoment(MomentKind.wicket, playerId: 'a2'));
    s.newBatter('a3');
    expect(last(s), isNull);
    s.retire('a1', hurt: true);
    expect(last(s), isNull);
  });

  test('fifty and hundred come once each, as they are passed', () {
    final s = Scorer(setup(overs: 20))..start();
    for (var i = 0; i < 8; i++) {
      ball(s, s.six, striker: 'a1');
    }
    expect(s.inn.batters.first.runs, 48);
    ball(s, s.four, striker: 'a1');
    expect(last(s), const MatchMoment(MomentKind.fifty, playerId: 'a1'), reason: '48 to 52');
    ball(s, s.six, striker: 'a1');
    expect(last(s), isNull, reason: 'already past 50');
    for (var i = 0; i < 7; i++) {
      ball(s, s.six, striker: 'a1');
    }
    expect(s.inn.batters.first.runs, 100);
    expect(last(s), const MatchMoment(MomentKind.hundred, playerId: 'a1'));
  });

  test('a fifth wicket is a five-for, told instead of the wicket', () {
    final s = Scorer(setup(overs: 5))..start();
    for (var i = 3; i <= 6; i++) {
      s.out(DismissalType.bowled);
      s.newBatter('a$i');
    }
    s.dots(2); // b1's over ends on 4 wickets
    for (var i = 0; i < 6; i++) {
      ball(s, () => s.runs(0)); // b2's over
    }
    ball(s, () => s.out(DismissalType.bowled)); // b1 again
    expect(s.inn.bowlers.firstWhere((b) => b.playerId == 'b1').wickets, 5);
    expect(last(s), const MatchMoment(MomentKind.fiveWickets, playerId: 'b1'));
  });

  test('the end of the first innings is the break; the winning run is the result', () {
    final s = Scorer(setup(overs: 1))
      ..start()
      ..runs(1)
      ..runs(2)
      ..runs(3)
      ..dots(2);
    s.four();
    expect(last(s), const MatchMoment(MomentKind.inningsBreak));
    s.openers('b1', 'b2');
    expect(last(s), isNull);
    s.bowler('a1');
    s.six();
    expect(last(s), isNull, reason: 'the chase starting is not the match starting');
    s.four();
    s.runs(1);
    expect(last(s), const MatchMoment(MomentKind.result));
  });

  test('an undo or a correction makes no moment', () {
    final s = Scorer(setup())..start();
    s.out(DismissalType.bowled);
    final after = s.state;
    final before = ScoringEngine.replay(s.setup, s.events.sublist(0, s.events.length - 1));
    expect(momentOf(after, before), isNull, reason: 'undo');
    expect(momentOf(before, before), isNull);
  });
}
