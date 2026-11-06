import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/screens/scorecard_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/match_charts.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  final matches = demoMatches(DateTime.utc(2026, 11, 6));
  final finished = matches.firstWhere((m) => m.id == 'demo-match-1');
  final live = matches.firstWhere((m) => m.id == 'demo-live');
  MatchState replay(MatchRecord m) => ScoringEngine.replay(m.setup, m.events);
  final chart = find.byWidgetPredicate((w) => w is SizedBox && w.height == 180).first;

  Future<void> pumpCharts(WidgetTester tester, MatchState state) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: MatchCharts(state: state)),
    ));
    await tester.pump();
  }

  testWidgets('both charts draw at 360 dp, with both teams in the legend', (tester) async {
    await pumpCharts(tester, replay(finished));
    expect(find.text('RUNS PER OVER'), findsOneWidget);
    expect(find.text('RUN RACE'), findsOneWidget);
    expect(find.text('Team A'), findsNWidgets(2));
    expect(find.text('Team B'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping reads an over', (tester) async {
    await pumpCharts(tester, replay(finished));
    expect(find.text('Tap a chart to read an over'), findsNWidgets(2));

    await tester.tapAt(tester.getCenter(chart));
    await tester.pump();

    expect(find.textContaining(RegExp(r'^Over \d+: Team')), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging across moves the reading', (tester) async {
    await pumpCharts(tester, replay(finished));
    final left = tester.getTopLeft(chart) + const Offset(40, 90);
    await tester.dragFrom(left, const Offset(200, 0));
    await tester.pump();
    expect(find.textContaining(RegExp(r'^Over \d+')), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a match in its first innings shows one team', (tester) async {
    final setup = replay(finished).setup;
    final at = DateTime.utc(2026);
    final first = setup.teamById(setup.firstBattingTeamId);
    final second = setup.opponentOf(first.id);
    final state = ScoringEngine.replay(setup, [
      OpenersSelected(id: 'e1', at: at, strikerId: first.players[0].id, nonStrikerId: first.players[1].id),
      BowlerChanged(id: 'e2', at: at, bowlerId: second.players[8].id),
      BallBowled(id: 'e3', at: at, runsOffBat: 4, boundary: true),
    ]);
    await pumpCharts(tester, state);
    expect(find.text(first.name), findsNWidgets(2));
    expect(find.text(second.name), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a match with no balls draws empty axes without failing', (tester) async {
    await pumpCharts(tester, ScoringEngine.replay(replay(finished).setup, const []));
    await tester.tapAt(tester.getCenter(chart));
    await tester.pump();
    expect(find.text('Tap a chart to read an over'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the scorecard has a charts tab, also in dark mode', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = InMemoryMatchRepository();
    await repo.save(live);
    await tester.pumpWidget(ProviderScope(
      overrides: [matchRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.dark(), home: ScorecardScreen(matchId: live.id)),
    ));
    await tester.pump(_settle);

    await tester.ensureVisible(find.text('Charts'));
    await tester.pump(_settle);
    await tester.tap(find.text('Charts'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
    expect(find.text('RUNS PER OVER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
