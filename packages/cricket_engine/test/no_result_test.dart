import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

Team _team(String id) => Team(
      id: id,
      name: id,
      players: [
        for (var i = 1; i <= 3; i++) Player(id: '$id$i', name: '$id$i'),
      ],
    );

final _setup = MatchSetup(
  id: 'm',
  teamA: _team('a'),
  teamB: _team('b'),
  rules: MatchRules(oversPerInnings: 1),
  tossWinnerId: 'a',
  tossDecision: TossDecision.bat,
);

final _at = DateTime.utc(2026);
final _abandon = MatchAbandoned(id: 'x', at: _at, reason: 'Rain');

void main() {
  test('a match can be abandoned before a ball is bowled', () {
    final state = ScoringEngine.replay(_setup, [_abandon]);
    expect(state.isCompleted, isTrue);
    expect(state.result!.kind, ResultKind.noResult);
    expect(state.result!.winnerTeamId, isNull);
  });

  test('a match can be abandoned at the innings break', () {
    final state = ScoringEngine.replay(_setup, [
      OpenersSelected(id: 'e1', at: _at, strikerId: 'a1', nonStrikerId: 'a2'),
      BowlerChanged(id: 'e2', at: _at, bowlerId: 'b1'),
      for (var i = 0; i < 6; i++) BallBowled(id: 'b$i', at: _at),
      _abandon,
    ]);
    expect(state.result!.kind, ResultKind.noResult);
  });

  test('a finished match cannot be abandoned', () {
    expect(
      () => ScoringEngine.replay(_setup, [
        _abandon,
        MatchAbandoned(id: 'y', at: _at, reason: 'Rain'),
      ]),
      throwsA(isA<ScoringException>()),
    );
  });

  test('nothing can be scored after it', () {
    expect(
      () => ScoringEngine.replay(_setup, [
        _abandon,
        OpenersSelected(id: 'e1', at: _at, strikerId: 'a1', nonStrikerId: 'a2'),
      ]),
      throwsA(isA<ScoringException>()),
    );
  });

  test('undo is a replay without it', () {
    final events = <MatchEvent>[
      OpenersSelected(id: 'e1', at: _at, strikerId: 'a1', nonStrikerId: 'a2'),
      _abandon,
    ];
    expect(ScoringEngine.replay(_setup, events).isCompleted, isTrue);

    final undone = ScoringEngine.replay(_setup, events.sublist(0, 1));
    expect(undone.isCompleted, isFalse);
    expect(undone.result, isNull);
    expect(undone.phase, MatchPhase.awaitingBowler);
  });

  test('survives a JSON round trip', () {
    final back = MatchEvent.fromJson(_abandon.toJson());
    expect(back, isA<MatchAbandoned>());
    expect((back as MatchAbandoned).reason, 'Rain');
  });
}
