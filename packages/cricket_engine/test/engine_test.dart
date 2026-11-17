import 'dart:convert';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

Team team(String id, int size) => Team(
      id: id,
      name: id.toUpperCase(),
      players: [
        for (var i = 1; i <= size; i++) Player(id: '$id$i', name: '$id player $i'),
      ],
    );

MatchSetup setup({
  int overs = 2,
  int sizeA = 11,
  int sizeB = 11,
  bool lastManStands = false,
  int? maxOversPerBowler,
  String tossWinner = 'a',
  TossDecision decision = TossDecision.bat,
}) =>
    MatchSetup(
      id: 'm1',
      teamA: team('a', sizeA),
      teamB: team('b', sizeB),
      rules: MatchRules(
        oversPerInnings: overs,
        lastManStands: lastManStands,
        maxOversPerBowler: maxOversPerBowler,
      ),
      tossWinnerId: tossWinner,
      tossDecision: decision,
    );

/// Test helper that records events the same way the app does.
class Scorer {
  Scorer(this.setup);

  final MatchSetup setup;
  final events = <MatchEvent>[];
  var _next = 0;
  final _at = DateTime.utc(2026, 11, 5);

  MatchState get state => ScoringEngine.replay(setup, events);
  InningsState get inn => state.current;

  String _id() => 'e${_next++}';

  void add(MatchEvent e) {
    ScoringEngine.apply(setup, events, e);
    events.add(e);
  }

  /// Asserts the event is rejected and the log is unchanged.
  void rejects(MatchEvent e) {
    final before = events.length;
    expect(() => add(e), throwsA(isA<ScoringException>()));
    expect(events.length, before);
  }

  OpenersSelected openersEvent(String s, String ns) =>
      OpenersSelected(id: _id(), at: _at, strikerId: s, nonStrikerId: ns);
  BowlerChanged bowlerEvent(String id) =>
      BowlerChanged(id: _id(), at: _at, bowlerId: id);
  BallBowled ballEvent({
    int bat = 0,
    ExtraType extra = ExtraType.none,
    int extraRuns = 0,
    bool boundary = false,
    Wicket? wicket,
    bool legByes = false,
  }) =>
      BallBowled(
        id: _id(),
        at: _at,
        runsOffBat: bat,
        extra: extra,
        extraRuns: extraRuns,
        boundary: boundary,
        wicket: wicket,
        legByes: legByes,
      );

  void openers(String s, String ns) => add(openersEvent(s, ns));
  void bowler(String id) => add(bowlerEvent(id));
  void runs(int r, {bool boundary = false}) =>
      add(ballEvent(bat: r, boundary: boundary));
  void four() => runs(4, boundary: true);
  void six() => runs(6, boundary: true);
  void dots(int n) {
    for (var i = 0; i < n; i++) {
      runs(0);
    }
  }

  void wide([int extraRuns = 0]) =>
      add(ballEvent(extra: ExtraType.wide, extraRuns: extraRuns));
  void noBall({int bat = 0, int byes = 0, bool boundary = false}) => add(
      ballEvent(extra: ExtraType.noBall, bat: bat, extraRuns: byes, boundary: boundary));
  void bye(int r) => add(ballEvent(extra: ExtraType.bye, extraRuns: r));
  void legBye(int r) => add(ballEvent(extra: ExtraType.legBye, extraRuns: r));

  Wicket wicketOf(DismissalType type, {String? out, String? fielder}) =>
      Wicket(type: type, batterOutId: out ?? inn.strikerId!, fielderId: fielder);

  void out(
    DismissalType type, {
    String? batter,
    String? fielder,
    int bat = 0,
    ExtraType extra = ExtraType.none,
    int extraRuns = 0,
  }) =>
      add(ballEvent(
        bat: bat,
        extra: extra,
        extraRuns: extraRuns,
        wicket: wicketOf(type, out: batter, fielder: fielder),
      ));

  void newBatter(String id) =>
      add(NewBatter(id: _id(), at: _at, batterId: id));
  void retire(String id, {required bool hurt}) =>
      add(BatterRetired(id: _id(), at: _at, batterId: id, hurt: hurt));
  void swap() => add(StrikeSwapped(id: _id(), at: _at));
  void close(String reason) =>
      add(InningsClosed(id: _id(), at: _at, reason: reason));

  /// Openers a1/a2 and bowler b1: ready for the first ball.
  void start() {
    openers('a1', 'a2');
    bowler('b1');
  }
}

void main() {
  group('toss', () {
    test('decides who bats first', () {
      expect(setup(tossWinner: 'a', decision: TossDecision.bat).firstBattingTeamId, 'a');
      expect(setup(tossWinner: 'a', decision: TossDecision.bowl).firstBattingTeamId, 'b');
      expect(setup(tossWinner: 'b', decision: TossDecision.bat).firstBattingTeamId, 'b');
      expect(setup(tossWinner: 'b', decision: TossDecision.bowl).firstBattingTeamId, 'a');
    });

    test('rejects a toss winner that is not playing', () {
      expect(() => setup(tossWinner: 'x'), throwsArgumentError);
    });
  });

  group('phases', () {
    test('openers, then bowler, then play', () {
      final s = Scorer(setup());
      expect(s.state.phase, MatchPhase.awaitingOpeners);
      s.openers('a1', 'a2');
      expect(s.state.phase, MatchPhase.awaitingBowler);
      s.bowler('b1');
      expect(s.state.phase, MatchPhase.inPlay);
    });

    test('a ball before a bowler is chosen is rejected', () {
      final s = Scorer(setup())..openers('a1', 'a2');
      s.rejects(s.ballEvent(bat: 1));
    });

    test('invalid openers are rejected', () {
      final s = Scorer(setup());
      s.rejects(s.openersEvent('a1', 'a1'));
      s.rejects(s.openersEvent('a1', 'b1'));
      s.openers('a1', 'a2');
      s.rejects(s.openersEvent('a3', 'a4'));
    });
  });

  group('runs and strike', () {
    test('odd runs rotate strike, boundaries are counted', () {
      final s = Scorer(setup())..start();
      s.runs(1);
      expect(s.inn.strikerId, 'a2');
      s.runs(2);
      expect(s.inn.strikerId, 'a2');
      s.four();
      s.six();
      final a2 = s.inn.batter('a2')!;
      expect(a2.runs, 12);
      expect(a2.balls, 3);
      expect(a2.fours, 1);
      expect(a2.sixes, 1);
      expect(s.inn.runs, 13);
      expect(s.inn.bowler('b1')!.runs, 13);
    });

    test('a boundary must be 4 or 6', () {
      final s = Scorer(setup())..start();
      s.rejects(s.ballEvent(bat: 3, boundary: true));
    });

    test('end of over swaps strike and needs a different bowler', () {
      final s = Scorer(setup())..start();
      s.dots(6);
      expect(s.inn.strikerId, 'a2');
      expect(s.inn.oversText, '1');
      expect(s.state.phase, MatchPhase.awaitingBowler);
      expect(s.inn.eligibleBowlerIds, isNot(contains('b1')));
      expect(s.inn.completedOvers.single.length, 6);
      s.rejects(s.bowlerEvent('b1'));
      s.bowler('b2');
      expect(s.state.phase, MatchPhase.inPlay);
    });

    test('partnership counts all runs and balls faced, not wides', () {
      final s = Scorer(setup())..start();
      s.noBall();
      s.wide();
      s.runs(1); // free hit
      expect(s.inn.partnershipRuns, 3);
      expect(s.inn.partnershipBalls, 2);
    });

    test('manual strike swap', () {
      final s = Scorer(setup())..start();
      s.swap();
      expect(s.inn.strikerId, 'a2');
      expect(s.inn.nonStrikerId, 'a1');
    });
  });

  group('extras', () {
    test('wide: penalty run, not a legal ball, not faced', () {
      final s = Scorer(setup())..start();
      s.wide();
      expect(s.inn.runs, 1);
      expect(s.inn.legalBalls, 0);
      expect(s.inn.extras.wides, 1);
      expect(s.inn.batter('a1')!.balls, 0);
      final b1 = s.inn.bowler('b1')!;
      expect(b1.runs, 1);
      expect(b1.wides, 1);
      expect(b1.legalBalls, 0);
      expect(s.inn.currentOver.single.label, 'Wd');
    });

    test('wide with runs run rotates strike; wide boundary', () {
      final s = Scorer(setup())..start();
      s.wide(1);
      expect(s.inn.runs, 2);
      expect(s.inn.extras.wides, 2);
      expect(s.inn.strikerId, 'a2');
      s.wide(4);
      expect(s.inn.extras.wides, 7);
      expect(s.inn.strikerId, 'a2');
    });

    test('wide cannot have runs off the bat', () {
      final s = Scorer(setup())..start();
      s.rejects(s.ballEvent(extra: ExtraType.wide, bat: 1));
    });

    test('no-ball: bat runs to batter, counts as faced, gives a free hit', () {
      final s = Scorer(setup())..start();
      s.noBall(bat: 1);
      expect(s.inn.runs, 2);
      expect(s.inn.extras.noBalls, 1);
      expect(s.inn.legalBalls, 0);
      final a1 = s.inn.batter('a1')!;
      expect(a1.runs, 1);
      expect(a1.balls, 1);
      final b1 = s.inn.bowler('b1')!;
      expect(b1.runs, 2);
      expect(b1.noBalls, 1);
      expect(s.inn.strikerId, 'a2');
      expect(s.inn.isFreeHit, isTrue);
      expect(s.inn.currentOver.single.label, 'Nb+1');
    });

    test('free hit: only run out allowed, survives a wide, ends on a legal ball', () {
      final s = Scorer(setup())..start();
      s.noBall();
      s.rejects(s.ballEvent(wicket: s.wicketOf(DismissalType.bowled)));
      s.wide();
      expect(s.inn.isFreeHit, isTrue);
      s.rejects(s.ballEvent(
        extra: ExtraType.wide,
        wicket: s.wicketOf(DismissalType.stumped),
      ));
      s.runs(0);
      expect(s.inn.isFreeHit, isFalse);
    });

    test('run out is allowed on a free hit', () {
      final s = Scorer(setup())..start();
      s.noBall();
      s.out(DismissalType.runOut, bat: 1, batter: 'a2');
      expect(s.inn.wickets, 1);
      expect(s.inn.runs, 2);
      expect(s.inn.bowler('b1')!.wickets, 0);
    });

    test('no-ball byes go to byes, not the bowler', () {
      final s = Scorer(setup())..start();
      s.noBall(byes: 2);
      expect(s.inn.runs, 3);
      expect(s.inn.extras.byes, 2);
      expect(s.inn.bowler('b1')!.runs, 1);
      expect(s.inn.batter('a1')!.runs, 0);
    });

    test('no-ball leg byes go to leg byes, not byes or the bowler', () {
      final s = Scorer(setup())..start();
      s.add(s.ballEvent(extra: ExtraType.noBall, extraRuns: 3, legByes: true));
      expect(s.inn.runs, 4);
      expect(s.inn.extras.legByes, 3);
      expect(s.inn.extras.byes, 0);
      expect(s.inn.extras.noBalls, 1);
      expect(s.inn.bowler('b1')!.runs, 1);
      expect(s.inn.batter('a1')!.runs, 0);
      expect(s.inn.batter('a1')!.balls, 1);
      expect(s.inn.legalBalls, 0);
      expect(s.inn.strikerId, 'a2', reason: '3 completed runs change ends');
      expect(s.inn.isFreeHit, isTrue);
    });

    test('leg byes only on a no-ball, with runs and none off the bat', () {
      final s = Scorer(setup())..start();
      s.rejects(s.ballEvent(extraRuns: 1, legByes: true));
      s.rejects(s.ballEvent(extra: ExtraType.wide, extraRuns: 1, legByes: true));
      s.rejects(s.ballEvent(extra: ExtraType.bye, extraRuns: 1, legByes: true));
      s.rejects(s.ballEvent(extra: ExtraType.noBall, legByes: true));
      s.rejects(s.ballEvent(extra: ExtraType.noBall, bat: 1, extraRuns: 1, legByes: true));
    });

    test('byes and leg byes: legal, faced, not charged to the bowler', () {
      final s = Scorer(setup())..start();
      s.bye(1);
      expect(s.inn.runs, 1);
      expect(s.inn.extras.byes, 1);
      expect(s.inn.legalBalls, 1);
      expect(s.inn.batter('a1')!.balls, 1);
      expect(s.inn.batter('a1')!.runs, 0);
      expect(s.inn.bowler('b1')!.runs, 0);
      expect(s.inn.bowler('b1')!.dots, 1);
      expect(s.inn.strikerId, 'a2');
      s.legBye(4);
      expect(s.inn.extras.legByes, 4);
      expect(s.inn.strikerId, 'a2');
      expect(s.inn.currentOver.map((b) => b.label), ['1B', '4Lb']);
    });

    test('byes need runs and no bat runs', () {
      final s = Scorer(setup())..start();
      s.rejects(s.ballEvent(extra: ExtraType.bye));
      s.rejects(s.ballEvent(extra: ExtraType.legBye, extraRuns: 1, bat: 1));
    });
  });

  group('wickets', () {
    test('caught: credited to bowler, new batter takes strike', () {
      final s = Scorer(setup())..start();
      s.runs(2);
      s.out(DismissalType.caught, fielder: 'b3');
      expect(s.inn.wickets, 1);
      final a1 = s.inn.batter('a1')!;
      expect(a1.isOut, isTrue);
      expect(a1.dismissal!.bowlerId, 'b1');
      expect(a1.dismissal!.fielderId, 'b3');
      expect(s.inn.bowler('b1')!.wickets, 1);
      expect(s.inn.fallOfWickets.single.runs, 2);
      expect(s.inn.fallOfWickets.single.batterId, 'a1');
      expect(s.inn.partnershipRuns, 0);
      expect(s.state.phase, MatchPhase.awaitingBatter);
      expect(s.inn.availableBatterIds, isNot(contains('a1')));
      expect(s.inn.availableBatterIds, isNot(contains('a2')));
      s.rejects(s.ballEvent());
      s.newBatter('a3');
      expect(s.inn.strikerId, 'a3');
      expect(s.inn.nonStrikerId, 'a2');
      expect(s.state.phase, MatchPhase.inPlay);
    });

    test('wicket on the last ball of the over: new batter at the other end', () {
      final s = Scorer(setup())..start();
      s.dots(5);
      s.out(DismissalType.bowled);
      expect(s.inn.strikerId, 'a2');
      expect(s.inn.nonStrikerId, isNull);
      expect(s.state.phase, MatchPhase.awaitingBatter);
      s.newBatter('a3');
      expect(s.inn.nonStrikerId, 'a3');
      expect(s.state.phase, MatchPhase.awaitingBowler);
    });

    test('run out of the non-striker keeps completed runs', () {
      final s = Scorer(setup())..start();
      s.out(DismissalType.runOut, batter: 'a2', bat: 1, fielder: 'b2');
      expect(s.inn.runs, 1);
      expect(s.inn.batter('a1')!.runs, 1);
      expect(s.inn.batter('a2')!.isOut, isTrue);
      expect(s.inn.batter('a2')!.dismissal!.bowlerId, isNull);
      expect(s.inn.currentOver.single.label, '1+W');
      expect(s.state.phase, MatchPhase.awaitingBatter);
    });

    test('illegal dismissals are rejected', () {
      final s = Scorer(setup())..start();
      s.rejects(s.ballEvent(wicket: s.wicketOf(DismissalType.stumped, out: 'a2')));
      s.rejects(s.ballEvent(bat: 1, wicket: s.wicketOf(DismissalType.caught)));
      s.rejects(s.ballEvent(
        extra: ExtraType.wide,
        wicket: s.wicketOf(DismissalType.bowled),
      ));
      s.rejects(s.ballEvent(wicket: s.wicketOf(DismissalType.retiredHurt)));
      s.rejects(s.ballEvent(wicket: s.wicketOf(DismissalType.caught, fielder: 'a5')));
    });

    test('stumped off a wide counts the wide and the wicket', () {
      final s = Scorer(setup())..start();
      s.out(DismissalType.stumped, extra: ExtraType.wide, fielder: 'b2');
      expect(s.inn.runs, 1);
      expect(s.inn.extras.wides, 1);
      expect(s.inn.wickets, 1);
      expect(s.inn.bowler('b1')!.wickets, 1);
      expect(s.inn.currentOver.single.label, 'Wd+W');
    });

    test('all out ends the innings', () {
      final s = Scorer(setup(sizeA: 3))..start();
      s.out(DismissalType.bowled);
      s.newBatter('a3');
      s.out(DismissalType.lbw);
      expect(s.inn.isComplete, isTrue);
      expect(s.inn.closeReason, 'All out');
      expect(s.state.phase, MatchPhase.inningsBreak);
    });

    test('last man stands: lone batter keeps strike until out', () {
      final s = Scorer(setup(sizeA: 2, lastManStands: true))..start();
      s.out(DismissalType.bowled);
      expect(s.state.phase, MatchPhase.inPlay);
      expect(s.inn.strikerId, 'a2');
      expect(s.inn.nonStrikerId, isNull);
      s.runs(1);
      expect(s.inn.strikerId, 'a2');
      s.out(DismissalType.bowled);
      expect(s.inn.closeReason, 'All out');
    });
  });

  group('retirements', () {
    test('retired hurt is not a wicket and the batter can return', () {
      final s = Scorer(setup())..start();
      s.four();
      s.retire('a1', hurt: true);
      expect(s.inn.wickets, 0);
      expect(s.state.phase, MatchPhase.awaitingBatter);
      expect(s.inn.availableBatterIds, contains('a1'));
      s.newBatter('a3');
      expect(s.inn.strikerId, 'a3');
      s.out(DismissalType.bowled);
      s.newBatter('a1');
      final a1 = s.inn.batter('a1')!;
      expect(a1.runs, 4);
      expect(a1.dismissal, isNull);
      expect(s.inn.batters.length, 3);
    });

    test('retired out counts as a wicket', () {
      final s = Scorer(setup())..start();
      s.retire('a2', hurt: false);
      expect(s.inn.wickets, 1);
      expect(s.inn.fallOfWickets.single.batterId, 'a2');
      expect(s.inn.batter('a2')!.isOut, isTrue);
    });

    test('only batters at the crease can retire', () {
      final s = Scorer(setup())..start();
      s.rejects(BatterRetired(id: 'x', at: DateTime.utc(2026), batterId: 'a5', hurt: true));
    });
  });

  group('bowling', () {
    test('maiden over', () {
      final s = Scorer(setup())..start();
      s.dots(6);
      final b1 = s.inn.bowler('b1')!;
      expect(b1.maidens, 1);
      expect(b1.overs(6), '1');
      expect(b1.dots, 6);
    });

    test('mid-over change: allowed, no maiden, previous bowler is the replacement', () {
      final s = Scorer(setup())..start();
      s.dots(2);
      s.rejects(s.bowlerEvent('b1'));
      s.bowler('b2');
      s.dots(4);
      expect(s.inn.bowler('b1')!.legalBalls, 2);
      expect(s.inn.bowler('b2')!.legalBalls, 4);
      expect(s.inn.bowler('b1')!.maidens, 0);
      expect(s.inn.bowler('b2')!.maidens, 0);
      expect(s.inn.lastOverBowlerId, 'b2');
      // Law 17.8: no one bowls parts of two consecutive overs.
      expect(s.inn.eligibleBowlerIds, isNot(contains('b1')));
      expect(s.inn.eligibleBowlerIds, isNot(contains('b2')));
      s.rejects(s.bowlerEvent('b1'));
      s.bowler('b3');
    });

    test('a bowler replaced before bowling a ball gets no figures', () {
      final s = Scorer(setup())..start();
      s.bowler('b2');
      expect(s.inn.bowler('b1'), isNull);
      s.dots(1);
      expect(s.inn.bowlers.map((b) => b.playerId), ['b2']);
    });

    test('max overs per bowler', () {
      final s = Scorer(setup(overs: 3, maxOversPerBowler: 1))..start();
      s.dots(6);
      s.bowler('b2');
      s.dots(6);
      expect(s.inn.eligibleBowlerIds, isNot(contains('b1')));
      s.rejects(s.bowlerEvent('b1'));
      s.bowler('b3');
    });

    test('max overs: a part over counts, so a new over must fit the limit', () {
      final s = Scorer(setup(overs: 3, maxOversPerBowler: 1))..start();
      s.dots(2);
      s.bowler('b2');
      s.dots(4);
      s.bowler('b3');
      s.dots(6);
      // b1 (0.2) and b2 (0.4) have each started an over.
      expect(s.inn.eligibleBowlerIds, isNot(contains('b1')));
      expect(s.inn.eligibleBowlerIds, isNot(contains('b2')));
      s.rejects(s.bowlerEvent('b1'));
      s.bowler('b4');
    });

    test('bowler must be in the fielding side', () {
      final s = Scorer(setup())..openers('a1', 'a2');
      s.rejects(s.bowlerEvent('a3'));
    });
  });

  group('innings and result', () {
    Scorer firstInningsOfTen() {
      final s = Scorer(setup(overs: 1))..start();
      s.runs(1);
      s.runs(2);
      s.runs(3);
      s.dots(2);
      s.four();
      return s;
    }

    test('overs completed ends the innings and sets the target', () {
      final s = firstInningsOfTen();
      expect(s.inn.runs, 10);
      expect(s.inn.closeReason, 'Overs completed');
      expect(s.state.phase, MatchPhase.inningsBreak);
      s.rejects(s.ballEvent());
      s.openers('b1', 'b2');
      expect(s.state.innings.length, 2);
      expect(s.inn.battingTeamId, 'b');
      expect(s.inn.target, 11);
      s.rejects(s.bowlerEvent('b3'));
      s.bowler('a1');
      expect(s.state.phase, MatchPhase.inPlay);
    });

    test('chase won by wickets', () {
      final s = firstInningsOfTen()
        ..openers('b1', 'b2')
        ..bowler('a1');
      s.six();
      expect(s.inn.runsNeeded, 5);
      expect(s.inn.requiredRunRate, closeTo(6.0, 0.001));
      s.four();
      s.runs(1);
      final r = s.state.result!;
      expect(s.state.phase, MatchPhase.completed);
      expect(r.kind, ResultKind.wickets);
      expect(r.winnerTeamId, 'b');
      expect(r.margin, 10);
      expect(r.ballsRemaining, 3);
      expect(s.inn.closeReason, 'Target reached');
    });

    test('no wicket after the winning runs', () {
      final s = firstInningsOfTen()
        ..openers('b1', 'b2')
        ..bowler('a1');
      s.six();
      s.runs(2); // 8: three needed
      s.rejects(s.ballEvent(
        bat: 3,
        wicket: s.wicketOf(DismissalType.runOut, out: 'b1'),
      ));
      s.out(DismissalType.runOut, batter: 'b2', bat: 1); // short of the target
      expect(s.inn.runs, 9);
      expect(s.state.phase, MatchPhase.awaitingBatter);
    });

    test('defended by runs', () {
      final s = firstInningsOfTen()
        ..openers('b1', 'b2')
        ..bowler('a1');
      s.dots(6);
      final r = s.state.result!;
      expect(r.kind, ResultKind.runs);
      expect(r.winnerTeamId, 'a');
      expect(r.margin, 10);
    });

    test('tie, then the match rejects further events', () {
      final s = firstInningsOfTen()
        ..openers('b1', 'b2')
        ..bowler('a1');
      s.four();
      s.four();
      s.runs(2);
      s.dots(3);
      expect(s.state.result!.kind, ResultKind.tie);
      expect(s.state.result!.winnerTeamId, isNull);
      s.rejects(s.ballEvent());
      s.rejects(StrikeSwapped(id: 'x', at: DateTime.utc(2026)));
    });

    test('innings can be closed early', () {
      final s = Scorer(setup())..start();
      s.runs(3);
      s.close('Declared');
      expect(s.state.phase, MatchPhase.inningsBreak);
      expect(s.state.innings.first.closeReason, 'Declared');
    });
  });

  group('event log', () {
    test('undo is a replay without the last event', () {
      final s = Scorer(setup())..start();
      s.runs(1);
      s.four();
      final undone =
          ScoringEngine.replay(s.setup, s.events.sublist(0, s.events.length - 1));
      expect(undone.current.runs, 1);
      expect(undone.current.strikerId, 'a2');
      expect(undone.eventCount, s.events.length - 1);
    });

    test('events and setup survive a JSON round trip', () {
      final s = Scorer(setup())..start();
      s.four();
      s.wide(1);
      s.noBall(bat: 2);
      s.runs(1); // free hit
      s.out(DismissalType.caught, fielder: 'b4');
      s.newBatter('a3');
      s.retire('a3', hurt: true);

      final setupJson = jsonDecode(jsonEncode(s.setup.toJson())) as Map<String, Object?>;
      final eventsJson = jsonDecode(jsonEncode([for (final e in s.events) e.toJson()]))
          as List<Object?>;
      final restoredSetup = MatchSetup.fromJson(setupJson);
      final restoredEvents = [
        for (final e in eventsJson) MatchEvent.fromJson(e! as Map<String, Object?>),
      ];

      final original = s.inn;
      final restored = ScoringEngine.replay(restoredSetup, restoredEvents).current;
      expect(restored.runs, original.runs);
      expect(restored.wickets, original.wickets);
      expect(restored.strikerId, original.strikerId);
      expect(restored.extras.total, original.extras.total);
      expect(restoredSetup.teamA.players.length, 11);
      expect(restoredEvents.map((e) => e.id), s.events.map((e) => e.id));
    });

    test('no-ball leg byes survive JSON, and older logs read as byes', () {
      final s = Scorer(setup())..start();
      final legByes = s.ballEvent(extra: ExtraType.noBall, extraRuns: 2, legByes: true);
      final byes = s.ballEvent(extra: ExtraType.noBall, extraRuns: 2);
      expect(byes.toJson().containsKey('legByes'), isFalse,
          reason: 'balls without leg byes keep the original format');

      final restored = MatchEvent.fromJson(
        jsonDecode(jsonEncode(legByes.toJson())) as Map<String, Object?>,
      ) as BallBowled;
      expect(restored.legByes, isTrue);
      expect((MatchEvent.fromJson(byes.toJson()) as BallBowled).legByes, isFalse);
    });

    test('unknown event types are rejected', () {
      expect(
        () => MatchEvent.fromJson({'type': 'nope', 'id': 'x', 'at': '2026-01-01T00:00:00Z'}),
        throwsFormatException,
      );
    });
  });

  test('allowedDismissals matches the laws', () {
    expect(allowedDismissals(ExtraType.none, freeHit: false),
        containsAll([DismissalType.bowled, DismissalType.caught, DismissalType.runOut]));
    expect(allowedDismissals(ExtraType.none, freeHit: false),
        isNot(contains(DismissalType.retiredHurt)));
    expect(allowedDismissals(ExtraType.wide, freeHit: false),
        {DismissalType.stumped, DismissalType.hitWicket, DismissalType.runOut,
         DismissalType.obstructingTheField});
    expect(allowedDismissals(ExtraType.noBall, freeHit: false),
        {DismissalType.runOut, DismissalType.obstructingTheField});
    expect(allowedDismissals(ExtraType.none, freeHit: true),
        {DismissalType.runOut, DismissalType.obstructingTheField});
  });

  test('formatOvers', () {
    expect(formatOvers(0, 6), '0');
    expect(formatOvers(9, 6), '1.3');
    expect(formatOvers(12, 6), '2');
  });
}
