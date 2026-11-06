import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/screens/home_screen.dart';
import 'package:bnp_scorer/screens/stats_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/format.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  Future<void> pump(WidgetTester tester, Widget home, {bool seeded = true}) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = InMemoryMatchRepository();
    if (seeded) await seedDemoMatches(repo, now: DateTime.utc(2026, 11, 6));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(repo),
        tournamentRepositoryProvider.overrideWithValue(InMemoryTournamentRepository()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    ));
    await settle(tester);
  }

  testWidgets('home opens the stats screen', (tester) async {
    await pump(tester, const HomeScreen());
    await tester.tap(find.byTooltip('Stats'));
    await settle(tester);
    expect(find.text('Teams'), findsOneWidget);
  });

  testWidgets('before any result it explains itself', (tester) async {
    await pump(tester, const StatsScreen(), seeded: false);
    expect(find.text('Stats appear here once a match has finished.'), findsOneWidget);
  });

  testWidgets('the table ranks teams by the engine', (tester) async {
    await pump(tester, const StatsScreen());
    final book = computeStats(
      demoMatches(DateTime.utc(2026, 11, 6)).map((m) => ScoringEngine.replay(m.setup, m.events)),
    );
    final y = [for (final t in book.teams) tester.getTopLeft(find.text(t.name)).dy];
    expect(y, orderedEquals([...y]..sort()));
    expect(find.text('${book.teams.first.points}'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a team opens its profile and then a player', (tester) async {
    await pump(tester, const StatsScreen());
    await tester.tap(find.text('Team D'));
    await settle(tester);

    expect(find.text('ALL MATCHES'), findsOneWidget);
    expect(find.text('Net run rate'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await settle(tester);
    expect(find.text('TOP BATTERS'), findsOneWidget);
    await tester.tap(find.text('runs').first);
    await settle(tester);

    expect(find.text('BATTING'), findsOneWidget);
    expect(find.text('Strike rate'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every player profile fits at 360 dp', (tester) async {
    await pump(tester, const StatsScreen());
    await tester.tap(find.text('Batting'));
    await settle(tester);
    expect(find.text('runs'), findsWidgets);

    await tester.tap(find.text('Bowling'));
    await settle(tester);
    expect(find.text('wkts'), findsWidgets);
    await tester.tap(find.text('wkts').first);
    await settle(tester);

    expect(find.text('BOWLING'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the boundaries tab ranks hitters', (tester) async {
    await pump(tester, const StatsScreen());
    await tester.ensureVisible(find.text('Boundaries'));
    await settle(tester);
    await tester.tap(find.text('Boundaries'));
    await settle(tester);
    expect(find.text('hits'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('dates read naturally', () {
    expect(shortDate(DateTime(2026, 11, 6)), '6 Nov');
    expect(fixtureDate(DateTime(2026, 12, 5, 9)), 'Sat 5 Dec, 9:00 AM');
    expect(fixtureDate(DateTime(2026, 12, 5, 14, 5)), 'Sat 5 Dec, 2:05 PM');
    expect(fixtureDate(DateTime(2026, 12, 5)), 'Sat 5 Dec, 12:00 AM');
    expect(fixtureDate(DateTime(2026, 12, 5, 12)), 'Sat 5 Dec, 12:00 PM');
  });

  test('stat text helpers', () {
    expect(decimal(null), '—');
    expect(decimal(12.345, 1), '12.3');
    expect(signedDecimal(1.5), '+1.50');
    expect(signedDecimal(-0.25), '-0.25');
    expect(signedDecimal(0), '+0.00');
    expect(signedDecimal(null), '—');
    expect(highScoreText(const HighScore(runs: 48, notOut: true)), '48*');
    expect(highScoreText(const HighScore(runs: 48, notOut: false)), '48');
    expect(bestBowlingText(const BestBowling(wickets: 3, runs: 16)), '3/16');
    expect(plural(1, 'match'), '1 match');
    expect(plural(2, 'match'), '2 matches');
    expect(plural(2, 'run'), '2 runs');
  });
}
