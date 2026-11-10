import 'package:bnp_scorer/screens/scoring_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/score_header.dart';
import 'package:bnp_scorer/widgets/scoring_sheets.dart';
import 'package:bnp_scorer/widgets/stadium_effects.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);
final _at = DateTime.utc(2026, 11, 5);

/// Openers and a bowler, so the next tap scores a ball.
List<MatchEvent> _start(String striker, String nonStriker, String bowler, String tag) => [
      OpenersSelected(id: '$tag-o', at: _at, strikerId: striker, nonStrikerId: nonStriker),
      BowlerChanged(id: '$tag-b', at: _at, bowlerId: bowler),
    ];

List<MatchEvent> _singles(int count, String tag) => [
      for (var i = 0; i < count; i++) BallBowled(id: '$tag-$i', at: _at, runsOffBat: 1),
    ];

/// One over a side: team a made 6, team b has 5 with one ball left, so a four wins it.
List<MatchEvent> get _oneBallFromVictory => [
      ..._start('a1', 'a2', 'b1', 'i1'),
      ..._singles(6, 'i1'),
      ..._start('b1', 'b2', 'a1', 'i2'),
      ..._singles(5, 'i2'),
    ];

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  Future<void> pumpScoring(
    WidgetTester tester,
    List<MatchEvent> events, {
    int overs = 2,
    bool reduceMotion = false,
    ThemeData? theme,
  }) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = InMemoryMatchRepository();
    await repo.save(sampleRecord(overs: overs, events: events));
    await tester.pumpWidget(ProviderScope(
      overrides: [matchRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: const ScoringScreen(matchId: 'm1'),
      ),
    ));
    await tester.pump(_settle);
  }

  Future<void> tapKey(WidgetTester tester, String label) async {
    final key = find.text(label);
    await tester.ensureVisible(key);
    await tester.tap(key);
    // The first pump starts any sheet or burst animation; the second plays it.
    await tester.pump();
    await tester.pump(_settle);
  }

  /// Waits out a burst so the next one starts clean. The first pump starts
  /// the animation's clock; the second runs it past the end, since an
  /// animation only reports done once its time is up.
  Future<void> waitOutBurst(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(ScoreHeader.burstDuration + const Duration(milliseconds: 50));
  }

  group('boundary and wicket bursts', () {
    testWidgets('a four, a six and a wicket each get their own, which then clears', (tester) async {
      await pumpScoring(tester, _start('a1', 'a2', 'b1', 'i1'));

      await tapKey(tester, 'FOUR');
      expect(find.text('FOUR!'), findsOneWidget);
      await waitOutBurst(tester);
      expect(find.text('FOUR!'), findsNothing);

      await tapKey(tester, 'SIX');
      expect(find.text('SIX!'), findsOneWidget);
      await waitOutBurst(tester);
      expect(find.text('SIX!'), findsNothing);

      await tapKey(tester, 'OUT');
      await tapKey(tester, 'Bowled');
      await tapKey(tester, 'Confirm wicket');
      expect(find.text('WICKET!'), findsOneWidget);
      await waitOutBurst(tester);
      expect(find.text('WICKET!'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the burst sits inside the score card', (tester) async {
      await pumpScoring(tester, _start('a1', 'a2', 'b1', 'i1'));
      await tapKey(tester, 'SIX');

      final card = tester.getRect(find.byType(ScoreHeader));
      final burst = tester.getRect(find.text('SIX!'));
      expect(card.contains(burst.center), isTrue, reason: 'card $card, burst $burst');
      expect(burst.width, lessThan(card.width));
    });

    testWidgets('ordinary runs and undo do not celebrate', (tester) async {
      await pumpScoring(tester, _start('a1', 'a2', 'b1', 'i1'));

      await tapKey(tester, '1');
      expect(find.textContaining('!'), findsNothing);

      await tapKey(tester, 'FOUR');
      await waitOutBurst(tester);
      await tapKey(tester, 'Undo');
      expect(find.text('FOUR!'), findsNothing, reason: 'taking a four back is no celebration');
    });

    testWidgets('reduced motion skips it', (tester) async {
      await pumpScoring(tester, _start('a1', 'a2', 'b1', 'i1'), reduceMotion: true);
      await tapKey(tester, 'FOUR');
      expect(find.text('FOUR!'), findsNothing);
      expect(find.text('4s 1 · 6s 0 · SR 400.0'), findsOneWidget, reason: 'the ball still counts');
    });
  });

  group('result confetti', () {
    testWidgets('the winning ball throws confetti, which then clears', (tester) async {
      await pumpScoring(tester, _oneBallFromVictory, overs: 1);
      expect(find.byType(ConfettiBurst), findsNothing);

      await tapKey(tester, 'FOUR');
      expect(find.textContaining('won by'), findsWidgets);
      expect(find.byType(ConfettiBurst), findsOneWidget);
      final confetti = tester.getSize(find.byType(ConfettiBurst));
      expect(confetti.width, 360, reason: 'falls across the whole screen');

      await tester.pump(ConfettiBurst.duration);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening a finished match does not', (tester) async {
      await pumpScoring(
        tester,
        [..._oneBallFromVictory, BallBowled(id: 'win', at: _at, runsOffBat: 4, boundary: true)],
        overs: 1,
      );
      expect(find.textContaining('won by'), findsWidgets);
      expect(find.byType(ConfettiBurst), findsNothing);
    });

    testWidgets('reduced motion skips it', (tester) async {
      await pumpScoring(tester, _oneBallFromVictory, overs: 1, reduceMotion: true);
      await tapKey(tester, 'FOUR');
      expect(find.textContaining('won by'), findsWidgets);
      expect(find.byType(ConfettiBurst), findsNothing);
    });
  });

  group('dark theme', () {
    testWidgets('scoring fits at 360 dp, in play and at the result', (tester) async {
      await pumpScoring(tester, _oneBallFromVictory, overs: 1, theme: AppTheme.dark());
      expect(find.text('FOUR'), findsOneWidget);
      await tapKey(tester, 'FOUR');
      await tester.pump(ConfettiBurst.duration);
      expect(find.text('Full scorecard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('RoundOption', () {
    Future<Color?> labelColor(WidgetTester tester, Color fill) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RoundOption(label: '2', color: fill, selected: true, onTap: () {})),
      ));
      return tester.widget<Text>(find.text('2')).style?.color;
    }

    testWidgets('selected text is dark on neon and white on deep colours', (tester) async {
      expect(await labelColor(tester, AppColors.neon), AppColors.night);
      expect(await labelColor(tester, AppColors.turf), Colors.white);
      expect(await labelColor(tester, AppColors.extra), Colors.white);
    });
  });
}
