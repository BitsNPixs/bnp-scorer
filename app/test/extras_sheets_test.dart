import 'package:bnp_scorer/screens/scoring_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

/// A match with openers and a bowler set, ready for the first ball.
Future<InMemoryMatchRepository> _pumpInPlay(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final at = DateTime.utc(2026, 11, 5);
  final repo = InMemoryMatchRepository();
  await repo.save(sampleRecord(events: [
    OpenersSelected(id: 'e1', at: at, strikerId: 'a1', nonStrikerId: 'a2'),
    BowlerChanged(id: 'e2', at: at, bowlerId: 'b1'),
  ]));
  await tester.pumpWidget(ProviderScope(
    overrides: [matchRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(theme: AppTheme.light(), home: const ScoringScreen(matchId: 'm1')),
  ));
  await tester.pump(_settle);
  return repo;
}

Finder _inSheet(Finder finder) => find.descendant(of: find.byType(BottomSheet), matching: finder);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  // A sheet's animation starts on the frame after the tap.
  await tester.pump();
  await tester.pump(_settle);
}

BallBowled _lastBall(InMemoryMatchRepository repo) => repo.records['m1']!.events.last as BallBowled;

InningsState _innings(InMemoryMatchRepository repo) {
  final record = repo.records['m1']!;
  return ScoringEngine.replay(record.setup, record.events).current;
}

/// Every chip in the open sheet fits on screen and is sized to its label.
void _expectChipsFit(WidgetTester tester) {
  final chips = _inSheet(find.byType(ChoiceChip));
  expect(chips, findsWidgets);
  for (final element in chips.evaluate()) {
    final chip = find.byWidget(element.widget);
    final rect = tester.getRect(chip);
    final label = tester.getSize(find.descendant(of: chip, matching: find.byType(Text)).first);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(rect.width, lessThan(label.width + 80), reason: 'a chip should not stretch past its label');
  }
}

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  group('no-ball sheet', () {
    testWidgets('leg byes off a no-ball are recorded as leg byes', (tester) async {
      final repo = await _pumpInPlay(tester);
      await _tap(tester, find.text('NB'));
      _expectChipsFit(tester);

      await _tap(tester, _inSheet(find.text('Leg byes')));
      expect(_inSheet(find.text('0')), findsNothing, reason: 'leg byes need a run');
      await _tap(tester, _inSheet(find.text('2')));

      final ball = _lastBall(repo);
      expect(ball.extra, ExtraType.noBall);
      expect(ball.extraRuns, 2);
      expect(ball.legByes, isTrue);
      expect(ball.runsOffBat, 0);
      final extras = _innings(repo).extras;
      expect(extras.legByes, 2);
      expect(extras.byes, 0);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('byes and runs off the bat still go where they did', (tester) async {
      final repo = await _pumpInPlay(tester);
      await _tap(tester, find.text('NB'));
      await _tap(tester, _inSheet(find.text('Byes')));
      await _tap(tester, _inSheet(find.text('1')));
      expect(_lastBall(repo).legByes, isFalse);
      expect(_innings(repo).extras.byes, 1);

      await _tap(tester, find.text('NB'));
      expect(_inSheet(find.text('0')), findsOneWidget, reason: 'opens on runs off the bat');
      await _tap(tester, _inSheet(find.text('4')));
      final ball = _lastBall(repo);
      expect(ball.runsOffBat, 4);
      expect(ball.boundary, isTrue);
      expect(ball.extraRuns, 0);
    });
  });

  group('wicket sheet', () {
    testWidgets('a run out off a bye gives the runs to byes, not the batter', (tester) async {
      final repo = await _pumpInPlay(tester);
      await _tap(tester, find.text('OUT'));
      _expectChipsFit(tester);

      await _tap(tester, _inSheet(find.text('Bye')));
      expect(_inSheet(find.text('Caught')), findsNothing, reason: 'only run outs off a bye');
      await _tap(tester, _inSheet(find.text('Run out')));
      expect(_inSheet(find.text('0')), findsNothing, reason: 'a bye needs a run');
      _expectChipsFit(tester);
      await _tap(tester, _inSheet(find.text('2')));
      await _tap(tester, _inSheet(find.text('Confirm wicket')));

      final ball = _lastBall(repo);
      expect(ball.extra, ExtraType.bye);
      expect(ball.extraRuns, 2);
      expect(ball.runsOffBat, 0);
      expect(ball.wicket!.type, DismissalType.runOut);
      final inn = _innings(repo);
      expect(inn.extras.byes, 2);
      expect(inn.batter('a1')!.runs, 0);
      expect(inn.wickets, 1);
    });

    testWidgets('a run out off a leg bye starts on one run', (tester) async {
      final repo = await _pumpInPlay(tester);
      await _tap(tester, find.text('OUT'));
      await _tap(tester, _inSheet(find.text('Leg bye')));
      await _tap(tester, _inSheet(find.text('Run out')));
      await _tap(tester, _inSheet(find.text('Confirm wicket')));

      final ball = _lastBall(repo);
      expect(ball.extra, ExtraType.legBye);
      expect(ball.extraRuns, 1);
      expect(_innings(repo).extras.legByes, 1);
    });

    testWidgets('a run out off a legal ball still credits the batter', (tester) async {
      final repo = await _pumpInPlay(tester);
      await _tap(tester, find.text('OUT'));
      await _tap(tester, _inSheet(find.text('Run out')));
      await _tap(tester, _inSheet(find.text('1')));
      await _tap(tester, _inSheet(find.text('Confirm wicket')));

      final ball = _lastBall(repo);
      expect(ball.extra, ExtraType.none);
      expect(ball.runsOffBat, 1);
      expect(ball.extraRuns, 0);
      expect(_innings(repo).batter('a1')!.runs, 1);
    });
  });
}
