import 'package:bnp_scorer/screens/new_match_screen.dart';
import 'package:bnp_scorer/screens/scoring_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/match_charts.dart';
import 'package:bnp_scorer/widgets/wagon_wheel.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

Team _team(String id) => Team(
      id: id,
      name: 'Team ${id.toUpperCase()}',
      players: [
        for (var i = 1; i <= 3; i++) Player(id: '$id$i', name: 'Player $id$i'),
      ],
    );

MatchSetup _setup({bool trackShots = true}) => MatchSetup(
      id: 'm1',
      teamA: _team('a'),
      teamB: _team('b'),
      rules: MatchRules(oversPerInnings: 2, trackShots: trackShots),
      tossWinnerId: 'a',
      tossDecision: TossDecision.bat,
    );

List<MatchEvent> _events() {
  final at = DateTime.utc(2026);
  return [
    OpenersSelected(id: 'e1', at: at, strikerId: 'a1', nonStrikerId: 'a2'),
    BowlerChanged(id: 'e2', at: at, bowlerId: 'b1'),
    BallBowled(id: 'e3', at: at, runsOffBat: 4, boundary: true, shotZone: ShotZone.cover),
    BallBowled(id: 'e4', at: at, runsOffBat: 6, boundary: true, shotZone: ShotZone.midOn),
    BallBowled(id: 'e5', at: at, runsOffBat: 1, shotZone: ShotZone.cover),
    BallBowled(id: 'e6', at: at, runsOffBat: 2, shotZone: ShotZone.fineLeg),
    BallBowled(id: 'e7', at: at, runsOffBat: 2),
  ];
}

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  Future<InMemoryMatchRepository> pumpScoring(WidgetTester tester, List<MatchEvent> events, {bool trackShots = true}) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = InMemoryMatchRepository();
    final at = DateTime.utc(2026);
    await repo.save(MatchRecord(setup: _setup(trackShots: trackShots), events: events, createdAt: at, updatedAt: at));
    await tester.pumpWidget(ProviderScope(
      overrides: [matchRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.light(), home: const ScoringScreen(matchId: 'm1')),
    ));
    await tester.pump(_settle);
    return repo;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(_settle);
    }
  }

  List<MatchEvent> ready() => _events().take(2).toList();

  group('scoring', () {
    testWidgets('a scoring shot asks where it went', (tester) async {
      final repo = await pumpScoring(tester, ready());
      await tester.tap(find.text('FOUR'));
      await settle(tester);
      expect(find.text('Where did it go?'), findsOneWidget);

      await tester.tap(find.text('Cover'));
      await settle(tester);

      final ball = repo.records['m1']!.events.last as BallBowled;
      expect(ball.runsOffBat, 4);
      expect(ball.boundary, isTrue);
      expect(ball.shotZone, ShotZone.cover);
    });

    testWidgets('skipping still records the ball', (tester) async {
      final repo = await pumpScoring(tester, ready());
      await tester.tap(find.text('FOUR'));
      await settle(tester);
      await tester.tap(find.text('Skip'));
      await settle(tester);

      final ball = repo.records['m1']!.events.last as BallBowled;
      expect(ball.runsOffBat, 4);
      expect(ball.shotZone, isNull);
    });

    testWidgets('with the rule off nothing extra is asked', (tester) async {
      final repo = await pumpScoring(tester, ready(), trackShots: false);
      await tester.tap(find.text('FOUR'));
      await settle(tester);
      expect(find.text('Where did it go?'), findsNothing);
      expect(repo.records['m1']!.events, hasLength(3));
    });
  });

  testWidgets('the rule is off by default and can be turned on', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 6000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final matches = InMemoryMatchRepository();
    final teams = InMemoryTeamRepository();
    await teams.save(_team('a'));
    await teams.save(_team('b'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(matches),
        teamRepositoryProvider.overrideWithValue(teams),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const NewMatchScreen()),
    ));
    await settle(tester);

    await tester.tap(find.text('Saved teams').first);
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Team A'));
    await settle(tester);
    await tester.tap(find.text('Saved teams').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Team B'));
    await settle(tester);

    await tester.tap(find.text('House rules'));
    await settle(tester);
    await tester.ensureVisible(find.text('Record shot direction'));
    await settle(tester);
    await tester.tap(find.text('Record shot direction'));
    await settle(tester);
    await tester.tap(find.text('Start match'));
    await settle(tester);

    expect(matches.records.values.single.setup.rules.trackShots, isTrue);
  });

  group('the chart', () {
    Future<void> pumpChart(WidgetTester tester, List<MatchEvent> events, {bool trackShots = true}) async {
      tester.view
        ..physicalSize = const Size(1080, 6000)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MatchCharts(state: ScoringEngine.replay(_setup(trackShots: trackShots), events)),
        ),
      ));
      await tester.pump();
    }

    String zoneTotal(WidgetTester tester, String zone) {
      final row = find.ancestor(of: find.text(zone), matching: find.byType(Row)).first;
      final texts = tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)));
      return texts.last.data!;
    }

    testWidgets('adds runs by zone and counts each kind of shot', (tester) async {
      await pumpChart(tester, _events());
      expect(find.byType(WagonWheel), findsOneWidget);
      expect(find.text('4s: 1'), findsOneWidget);
      expect(find.text('6s: 1'), findsOneWidget);
      expect(find.text('1 to 3: 2'), findsOneWidget, reason: 'the untracked 2 is left out');
      expect(zoneTotal(tester, 'Cover'), '5');
      expect(zoneTotal(tester, 'Mid-on'), '6');
      expect(zoneTotal(tester, 'Point'), '0');
      expect(tester.takeException(), isNull);
    });

    testWidgets('filters to one batter', (tester) async {
      await pumpChart(tester, _events());
      await tester.tap(find.widgetWithText(ChoiceChip, 'Player a2'));
      await tester.pump();
      expect(find.text('1 to 3: 1'), findsOneWidget);
      expect(find.text('4s: 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is hidden when no shots were tracked', (tester) async {
      await pumpChart(tester, _events().take(2).toList(), trackShots: false);
      expect(find.byType(WagonWheel), findsNothing);
    });
  });
}
