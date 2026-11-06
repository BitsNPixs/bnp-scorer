import 'package:bnp_scorer/screens/scoring_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump(_settle);
}

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  testWidgets('a scorer can start a match and hit a four', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final repo = InMemoryMatchRepository();
    await repo.save(sampleRecord());

    await tester.pumpWidget(ProviderScope(
      overrides: [matchRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ScoringScreen(matchId: 'm1'),
      ),
    ));
    await tester.pump(_settle);

    expect(find.text('Opening batters'), findsOneWidget);
    await _tapText(tester, 'Asha');
    await _tapText(tester, 'Arun');
    await _tapText(tester, 'Start innings');

    expect(find.text('Who is bowling?'), findsOneWidget);
    await _tapText(tester, 'Bilal');

    await _tapText(tester, 'FOUR');
    expect(find.text('4s 1 · 6s 0 · SR 400.0'), findsOneWidget);
    expect(repo.records['m1']!.events, hasLength(3));

    await _tapText(tester, 'Undo');
    expect(find.text('4s 0 · 6s 0 · SR 0.0'), findsWidgets);
  });

  testWidgets('a match can be abandoned, and undo brings it back', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final repo = InMemoryMatchRepository();
    await repo.save(sampleRecord());
    await tester.pumpWidget(ProviderScope(
      overrides: [matchRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ScoringScreen(matchId: 'm1'),
      ),
    ));
    await tester.pump(_settle);

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pump(_settle);
    await tester.tap(find.text('Abandon match'));
    await tester.pump(_settle);
    await tester.tap(find.text('Abandon'));
    await tester.pump(_settle);
    await tester.pump(_settle);

    expect(find.text('No result'), findsWidgets);
    expect(repo.records['m1']!.events.single, isA<MatchAbandoned>());

    await tester.tap(find.byTooltip('Undo last action'));
    await tester.pump(_settle);
    await tester.pump(_settle);
    expect(repo.records['m1']!.events, isEmpty);
    expect(find.text('Opening batters'), findsOneWidget);
  });
}
