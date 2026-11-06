import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/screens/scorecard_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/format.dart';
import 'package:bnp_scorer/widgets/overs_timeline.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Team _team(String id) => Team(
      id: id,
      name: 'Team ${id.toUpperCase()}',
      players: [
        for (var i = 1; i <= 4; i++) Player(id: '$id$i', name: 'Player $id$i'),
      ],
    );

final _at = DateTime.utc(2026);

final _setup = MatchSetup(
  id: 'm',
  teamA: _team('a'),
  teamB: _team('b'),
  rules: MatchRules(oversPerInnings: 2),
  tossWinnerId: 'a',
  tossDecision: TossDecision.bat,
);

MatchEvent _ball(String id, {int runs = 0}) =>
    BallBowled(id: id, at: _at, runsOffBat: runs, boundary: runs == 4);

/// Over 1 goes 7/0 with a change of bowler. Over 2 is under way, at 12/1.
List<MatchEvent> _events() => [
      OpenersSelected(id: 'e1', at: _at, strikerId: 'a1', nonStrikerId: 'a2'),
      BowlerChanged(id: 'e2', at: _at, bowlerId: 'b1'),
      _ball('e3', runs: 4),
      _ball('e4', runs: 1),
      BowlerChanged(id: 'e5', at: _at, bowlerId: 'b2'),
      _ball('e6', runs: 2),
      _ball('e7'),
      _ball('e8'),
      _ball('e9'),
      BowlerChanged(id: 'e10', at: _at, bowlerId: 'b3'),
      _ball('e11', runs: 4),
      BallBowled(id: 'e12', at: _at, extra: ExtraType.wide),
      BallBowled(
        id: 'e13',
        at: _at,
        wicket: const Wicket(type: DismissalType.bowled, batterOutId: 'a1'),
      ),
    ];

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  Future<void> pumpTimeline(WidgetTester tester, MatchState state) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: OversTimeline(state: state)),
    ));
    await tester.pump();
  }

  group('the over data', () {
    final overs = ScoringEngine.replay(_setup, _events()).current.overs;

    test('carries the score each over ended on', () {
      expect(overs[0].scoreAfter, 7);
      expect(overs[0].wicketsAfter, 0);
      expect(overs[1].scoreAfter, 12);
      expect(overs[1].wicketsAfter, 1);
      expect(overs[1].runs, 5);
    });

    test('names everyone involved, without repeats', () {
      expect(overs[0].bowlerIds, ['b1', 'b2']);
      expect(overs[0].batterIds, ['a1', 'a2']);
      expect(overs[1].bowlerIds, ['b3']);
    });

    test('keeps every ball, extras included', () {
      expect(overs[1].balls, hasLength(3));
      expect(overs[1].balls[1].isLegal, isFalse);
    });

    test('a retirement between balls shows in the next score', () {
      final state = ScoringEngine.replay(_setup, [
        ..._events().take(4),
        BatterRetired(id: 'r', at: _at, batterId: 'a2', hurt: false),
        NewBatter(id: 'n', at: _at, batterId: 'a3'),
        _ball('e6'),
      ]);
      expect(state.current.overs.single.wicketsAfter, 1);
    });

    test('retired hurt is not a wicket', () {
      final state = ScoringEngine.replay(_setup, [
        ..._events().take(4),
        BatterRetired(id: 'r', at: _at, batterId: 'a2', hurt: true),
        NewBatter(id: 'n', at: _at, batterId: 'a3'),
        _ball('e6'),
      ]);
      expect(state.current.overs.single.wicketsAfter, 0);
    });
  });

  test('the headline reads bowlers to batters', () {
    final overs = ScoringEngine.replay(_setup, _events()).current.overs;
    expect(overHeadline(_setup, overs[0]), 'Player b1 & Player b2 to Player a1 & Player a2');
  });

  group('the list', () {
    testWidgets('puts the newest over first', (tester) async {
      await pumpTimeline(tester, ScoringEngine.replay(_setup, _events()));
      final newest = tester.getTopLeft(find.text('Ov 2')).dy;
      final older = tester.getTopLeft(find.text('Ov 1')).dy;
      expect(newest, lessThan(older));
      expect(find.text('12-1'), findsOneWidget);
      expect(find.text('7-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows each ball as a chip', (tester) async {
      await pumpTimeline(tester, ScoringEngine.replay(_setup, _events()));
      expect(find.text('Wd'), findsOneWidget);
      expect(find.text('W'), findsOneWidget);
      expect(find.text('4'), findsNWidgets(2));
    });

    testWidgets('opens on the latest innings and can switch', (tester) async {
      final matches = demoMatches(DateTime.utc(2026, 11, 6));
      final record = matches.firstWhere((m) => m.id == 'demo-match-1');
      final state = ScoringEngine.replay(record.setup, record.events);
      await pumpTimeline(tester, state);

      final first = state.setup.teamById(state.innings.first.battingTeamId).name;
      final second = state.setup.teamById(state.innings.last.battingTeamId).name;
      bool selected(String team) =>
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, team)).selected;
      expect(selected(second), isTrue);

      await tester.tap(find.widgetWithText(ChoiceChip, first));
      await tester.pump();
      expect(selected(first), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('real squad names fit at 360 dp', (tester) async {
      final matches = demoMatches(DateTime.utc(2026, 11, 6));
      for (final id in ['demo-match-1', 'demo-match-5', 'demo-live']) {
        final record = matches.firstWhere((m) => m.id == id);
        await pumpTimeline(tester, ScoringEngine.replay(record.setup, record.events));
        expect(tester.takeException(), isNull, reason: id);
      }
    });

    testWidgets('before a ball it says so', (tester) async {
      await pumpTimeline(tester, ScoringEngine.replay(_setup, const []));
      expect(find.text('No balls bowled yet.'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
    });
  });

  testWidgets('the scorecard has an Overs tab', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = InMemoryMatchRepository();
    await repo.save(sampleRecord(events: const []));
    await tester.pumpWidget(ProviderScope(
      overrides: [matchRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.light(), home: const ScorecardScreen(matchId: 'm1')),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Overs'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('No balls bowled yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
