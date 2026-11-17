import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/screens/scoring_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/surface_panel.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);
final _at = DateTime.utc(2026, 11, 17);

BallBowled _dot(int i) => BallBowled(id: 'd$i', at: _at);

/// Bowling side [bowlers] long; b1 bowls the first two balls, then b2 the
/// rest of the over.
MatchRecord _afterSplitOver(List<String> bowlers) => MatchRecord(
      setup: MatchSetup(
        id: 'm1',
        teamA: Team(id: 'a', name: 'Ammapet Kings', players: const [
          Player(id: 'a1', name: 'Asha'),
          Player(id: 'a2', name: 'Arun'),
          Player(id: 'a3', name: 'Anil'),
        ]),
        teamB: Team(id: 'b', name: 'Bazaar Strikers', players: [
          for (final (i, name) in bowlers.indexed) Player(id: 'b${i + 1}', name: name),
        ]),
        rules: MatchRules(oversPerInnings: 3),
        tossWinnerId: 'a',
        tossDecision: TossDecision.bat,
      ),
      events: [
        OpenersSelected(id: 'o', at: _at, strikerId: 'a1', nonStrikerId: 'a2'),
        BowlerChanged(id: 'c1', at: _at, bowlerId: 'b1'),
        _dot(1),
        _dot(2),
        BowlerChanged(id: 'c2', at: _at, bowlerId: 'b2'),
        for (var i = 3; i <= 6; i++) _dot(i),
      ],
      createdAt: _at,
      updatedAt: _at,
    );

Future<InMemoryMatchRepository> _pump(WidgetTester tester, MatchRecord record) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = InMemoryMatchRepository();
  await repo.save(record);
  await tester.pumpWidget(ProviderScope(
    overrides: [matchRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(theme: AppTheme.light(), home: const ScoringScreen(matchId: 'm1')),
  ));
  await tester.pump(_settle);
  return repo;
}

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  testWidgets('two bowlers after a mid-over change: a note explains, and play goes on', (tester) async {
    final repo = await _pump(tester, _afterSplitOver(['Bilal', 'Bharat']));

    expect(find.text('Who is bowling?'), findsOneWidget);
    final note = find.text(BowlingRelaxation.partOver.message);
    expect(note, findsOneWidget);
    final banner = tester.getRect(find.byType(NoticeBanner));
    expect(banner.left, greaterThanOrEqualTo(0));
    expect(banner.right, lessThanOrEqualTo(360));
    expect(tester.getRect(note).height, greaterThan(20), reason: 'the note wraps rather than clipping');
    expect(find.text('Bowled last over'), findsOneWidget, reason: 'Bharat bowled the last ball');

    await tester.ensureVisible(find.text('Bilal'));
    await tester.tap(find.text('Bilal'));
    // The panel switch animates from the frame after the tap.
    await tester.pump();
    await tester.pump(_settle);

    final last = repo.records['m1']!.events.last;
    expect(last, isA<BowlerChanged>().having((e) => e.bowlerId, 'bowlerId', 'b1'));
    expect(find.text(BowlingRelaxation.partOver.message), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('usual play shows no note, and says why a bowler is greyed out', (tester) async {
    await _pump(tester, _afterSplitOver(['Bilal', 'Bharat', 'Bose']));

    expect(find.byType(NoticeBanner), findsNothing);
    expect(find.text('Bowled last over'), findsNWidgets(2), reason: 'Bilal and Bharat both bowled in it');
    expect(tester.takeException(), isNull);
  });
}
