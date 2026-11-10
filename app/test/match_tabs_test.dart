import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/screens/scoring_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/format.dart';
import 'package:bnp_scorer/widgets/innings_scorecard.dart';
import 'package:bnp_scorer/widgets/match_charts.dart';
import 'package:bnp_scorer/widgets/match_result_tab.dart';
import 'package:bnp_scorer/widgets/overs_timeline.dart';
import 'package:bnp_scorer/widgets/phase_panels.dart';
import 'package:bnp_scorer/widgets/score_pad.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);
final _at = DateTime.utc(2026, 11, 5);

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  late List<MatchRecord> demo;
  setUpAll(() => demo = demoMatches(DateTime.utc(2026, 11, 6)));
  MatchState replay(MatchRecord r) => ScoringEngine.replay(r.setup, r.events);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(_settle);
    }
  }

  Future<void> pump(WidgetTester tester, MatchRecord record) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = InMemoryMatchRepository();
    await repo.save(record);
    await tester.pumpWidget(ProviderScope(
      overrides: [matchRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: AppTheme.light(), home: ScoringScreen(matchId: record.setup.id)),
    ));
    await settle(tester);
  }

  List<String> tabLabels(WidgetTester tester) => [
        for (final tab in tester.widgetList<Tab>(find.byType(Tab))) tab.text!,
      ];

  Future<void> tapTab(WidgetTester tester, String label) async {
    final tab = find.widgetWithText(Tab, label);
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await settle(tester);
  }

  group('while scoring', () {
    testWidgets('the scorecard is a tab away: Live, each innings, Overs, Charts', (tester) async {
      final record = demo.firstWhere((m) => m.id == 'demo-live');
      final state = replay(record);
      await pump(tester, record);

      expect(tabLabels(tester), [
        'Live',
        for (final inn in state.innings) '${state.setup.teamById(inn.battingTeamId).name} ${scoreLine(inn)}',
        'Overs',
        'Charts',
      ]);
      expect(tester.getTopLeft(find.byType(Tab).first).dx, greaterThanOrEqualTo(12), reason: 'clear of the edge');
      expect(find.byType(ScorePad), findsOneWidget);

      await tapTab(tester, tabLabels(tester)[1]);
      expect(find.byType(InningsScorecard), findsOneWidget);
      expect(find.byType(ScorePad), findsNothing);

      await tapTab(tester, 'Live');
      expect(find.byType(ScorePad), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a swipe on the pad does not leave the Live tab', (tester) async {
      await pump(tester, demo.firstWhere((m) => m.id == 'demo-live'));
      await tester.fling(find.byType(PadButton).first, const Offset(-300, 0), 1500);
      await settle(tester);
      expect(find.byType(ScorePad), findsOneWidget);
      expect(find.byType(InningsScorecard), findsNothing);
    });

    testWidgets('starting the second innings adds its tab', (tester) async {
      // One over a side, with five balls of the first innings bowled.
      await pump(
        tester,
        sampleRecord(overs: 1, events: [
          OpenersSelected(id: 'o', at: _at, strikerId: 'a1', nonStrikerId: 'a2'),
          BowlerChanged(id: 'b', at: _at, bowlerId: 'b1'),
          for (var i = 0; i < 5; i++) BallBowled(id: 'e$i', at: _at, runsOffBat: 1),
        ]),
      );
      expect(tabLabels(tester).where((l) => l.startsWith('Bazaar Strikers')), isEmpty);

      Future<void> tapIt(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await settle(tester);
      }

      await tapIt(find.descendant(of: find.byType(ScorePad), matching: find.text('1')));
      Finder chase(String name) => find.descendant(of: find.byType(InningsBreakPanel), matching: find.text(name));
      await tapIt(chase('Bilal'));
      await tapIt(chase('Bharat'));
      await tapIt(find.text('Start innings'));

      expect(tabLabels(tester).where((l) => l.startsWith('Bazaar Strikers')), hasLength(1));
      expect(tabLabels(tester).first, 'Live');
      expect(tester.takeException(), isNull);
    });
  });

  group('after the result', () {
    MatchRecord cupFinal() => demo.firstWhere((m) => m.setup.venue?.contains('BNP Cup Final') ?? false);

    testWidgets('opens on Result with the stars of the match and shortcuts, no extra button', (tester) async {
      await pump(tester, cupFinal());
      expect(tabLabels(tester).first, 'Result');
      expect(find.byType(MatchResultTab), findsOneWidget);
      expect(find.text('TOP BATTER'), findsOneWidget);
      expect(find.text('BEST BOWLER'), findsOneWidget);
      expect(find.text('Full scorecard'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the two star cards share the row evenly', (tester) async {
      await pump(tester, cupFinal());
      final bat = tester.getSize(find.ancestor(of: find.text('TOP BATTER'), matching: find.byType(Material)).first);
      final ball = tester.getSize(find.ancestor(of: find.text('BEST BOWLER'), matching: find.byType(Material)).first);
      expect(bat.width, closeTo(ball.width, 0.5));
      expect(bat.width, greaterThan(140));
    });

    testWidgets('the top batter card opens the innings they batted in', (tester) async {
      final record = cupFinal();
      final state = replay(record);
      var best = (innings: 0, runs: -1, balls: 0);
      for (final (i, inn) in state.innings.indexed) {
        for (final b in inn.batters) {
          if (b.runs > best.runs || (b.runs == best.runs && b.balls < best.balls)) {
            best = (innings: i, runs: b.runs, balls: b.balls);
          }
        }
      }
      await pump(tester, record);
      await tester.tap(find.text('TOP BATTER'));
      await settle(tester);

      final shown = tester.widget<InningsScorecard>(find.byType(InningsScorecard));
      expect(shown.innings.number, state.innings[best.innings].number);
    });

    testWidgets('the shortcut tiles open Overs and Charts', (tester) async {
      await pump(tester, cupFinal());
      Finder tile(String title) => find.descendant(of: find.byType(MatchResultTab), matching: find.text(title));
      await tester.ensureVisible(tile('Overs'));
      await tester.pump(_settle);
      await tester.tap(tile('Overs'));
      await settle(tester);
      expect(find.byType(OversTimeline), findsOneWidget);

      await tapTab(tester, 'Result');
      await tester.ensureVisible(tile('Charts'));
      await tester.pump(_settle);
      await tester.tap(tile('Charts'));
      await settle(tester);
      expect(find.byType(MatchCharts), findsOneWidget);
    });

    testWidgets('with the match over, a swipe moves between tabs', (tester) async {
      await pump(tester, cupFinal());
      await tester.fling(find.byType(MatchResultTab), const Offset(-300, 0), 1500);
      await settle(tester);
      expect(find.byType(InningsScorecard), findsOneWidget);
    });
  });
}
