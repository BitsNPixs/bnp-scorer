import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/format.dart';
import 'package:bnp_scorer/widgets/innings_scorecard.dart';
import 'package:bnp_scorer/widgets/result_hero.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _settle = Duration(milliseconds: 400);
final _now = DateTime.utc(2026, 11, 6);

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  late List<MatchRecord> demo;
  setUpAll(() => demo = demoMatches(_now));

  /// The demo cup final: a finished match with wickets, extras and boundaries.
  MatchRecord cupFinal() => demo.firstWhere((m) => m.setup.venue?.contains('BNP Cup Final') ?? false);
  MatchState replay(MatchRecord r) => ScoringEngine.replay(r.setup, r.events);

  /// Innings indexes the summary card asked to open.
  late List<int> opened;

  /// One innings' scorecard on its own, as the match screen's tab shows it.
  Future<void> pump(
    WidgetTester tester,
    MatchRecord record, {
    int innings = 0,
    ThemeData? theme,
    bool reduceMotion = false,
    bool settle = true,
  }) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final state = replay(record);
    opened = [];
    await tester.pumpWidget(MaterialApp(
      theme: theme ?? AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        body: InningsScorecard(state: state, innings: state.innings[innings], onInnings: opened.add),
      ),
    ));
    if (!settle) return;
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  Finder inFirstTab(Finder finder) => find.descendant(of: find.byType(InningsScorecard).first, matching: finder);

  /// Scrolls the first tab until [finder] is built and on screen; the list
  /// builds lazily, so lower sections do not exist until scrolled to.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: inFirstTab(find.byType(Scrollable)).first);
    await tester.pump(_settle);
  }

  group('result hero', () {
    testWidgets('shows every innings, the result and the Player of the Match', (tester) async {
      final record = cupFinal();
      final state = replay(record);
      await pump(tester, record);

      final hero = find.byType(ResultHero).first;
      for (final inn in state.innings) {
        final team = state.setup.teamById(inn.battingTeamId).name;
        expect(find.descendant(of: hero, matching: find.text(team)), findsOneWidget, reason: team);
        expect(find.descendant(of: hero, matching: find.text(scoreLine(inn))), findsOneWidget, reason: team);
      }
      expect(find.descendant(of: hero, matching: find.text(matchStatus(state))), findsOneWidget);
      expect(find.descendant(of: hero, matching: find.text('RESULT')), findsOneWidget);
      expect(find.descendant(of: hero, matching: find.text('PLAYER OF THE MATCH')), findsOneWidget);
      expect(
        find.descendant(of: hero, matching: find.text(playerName(state.setup, playerOfTheMatch(state)!))),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a match in progress says LIVE and the state of play', (tester) async {
      final record = demo.firstWhere((m) => m.id == 'demo-live');
      final state = replay(record);
      expect(state.isCompleted, isFalse);
      await pump(tester, record);

      final hero = find.byType(ResultHero).first;
      expect(find.descendant(of: hero, matching: find.text('LIVE')), findsOneWidget);
      expect(find.descendant(of: hero, matching: find.text('RESULT')), findsNothing);
      expect(find.descendant(of: hero, matching: find.text(matchStatus(state))), findsOneWidget);
    });
  });

  group('batting', () {
    testWidgets('run bars are proportional to runs, with the top scorer full length', (tester) async {
      final record = cupFinal();
      final inn = replay(record).innings.first;
      await pump(tester, record);

      final scorers = inn.batters.where((b) => b.runs > 0).toList();
      final top = scorers.map((b) => b.runs).reduce((a, b) => a > b ? a : b);
      final factors = [
        for (final e in inFirstTab(find.byType(FractionallySizedBox)).evaluate())
          (e.widget as FractionallySizedBox).widthFactor!,
      ];
      expect(factors, [for (final b in scorers) b.runs / top]);

      // Measured, not just configured: the top bar fills its track.
      final bars = inFirstTab(find.byType(FractionallySizedBox));
      final topIndex = scorers.indexWhere((b) => b.runs == top);
      final topBar = tester.getSize(bars.at(topIndex));
      final track = tester.getSize(find.ancestor(of: bars.at(topIndex), matching: find.byType(Container)).first);
      expect(topBar.width, closeTo(track.width, 0.5));
      expect(topBar.height, 4);
    });

    testWidgets('not-out scores carry a star and the dismissal reads "not out"', (tester) async {
      final record = cupFinal();
      final inn = replay(record).innings.first;
      await pump(tester, record);

      for (final b in inn.batters) {
        final notOut = b.dismissal == null;
        expect(inFirstTab(find.text(notOut ? '${b.runs}*' : '${b.runs}')), findsWidgets, reason: b.playerId);
      }
      expect(
        inFirstTab(find.text('not out')),
        findsNWidgets(inn.batters.where((b) => b.dismissal == null).length),
      );
    });

    testWidgets('extras list only the kinds that happened', (tester) async {
      final record = cupFinal();
      final e = replay(record).innings.first.extras;
      await pump(tester, record);

      for (final (label, count) in [('wd', e.wides), ('nb', e.noBalls), ('b', e.byes), ('lb', e.legByes)]) {
        expect(inFirstTab(find.text('$label $count')), count > 0 ? findsOneWidget : findsNothing, reason: label);
      }
    });

    testWidgets('every number sits under its column heading', (tester) async {
      final record = cupFinal();
      final inn = replay(record).innings.first;
      await pump(tester, record);

      final batter = inn.batters.firstWhere((b) => b.dismissal != null);
      final runsCell = inFirstTab(find.text('${batter.runs}')).first;
      expect(tester.getTopRight(runsCell).dx, closeTo(tester.getTopRight(inFirstTab(find.text('R')).first).dx, 0.5));
      final srCell = inFirstTab(find.text(batter.strikeRate.toStringAsFixed(1))).first;
      expect(tester.getTopRight(srCell).dx, closeTo(tester.getTopRight(inFirstTab(find.text('SR'))).dx, 0.5));
    });
  });

  testWidgets('the fall of wickets is a timeline, one evenly spaced marker per wicket', (tester) async {
    final record = cupFinal();
    final inn = replay(record).innings.first;
    expect(inn.fallOfWickets.length, greaterThan(1), reason: 'the test needs two wickets');
    await pump(tester, record);
    await scrollTo(tester, inFirstTab(find.text('Fall of wickets')));

    final centres = [
      for (final f in inn.fallOfWickets) tester.getCenter(inFirstTab(find.text('${f.runs}-${f.wicketNumber}'))).dx,
    ];
    for (var i = 1; i < centres.length; i++) {
      expect(centres[i] - centres[i - 1], closeTo(104, 0.5), reason: 'wicket ${i + 1}');
    }
  });

  testWidgets('the best bowling figures are marked, once', (tester) async {
    final record = cupFinal();
    final inn = replay(record).innings.first;
    final best = inn.bowlers.where((f) => f.wickets > 0).reduce(
          (a, b) => b.wickets > a.wickets || (b.wickets == a.wickets && b.runs < a.runs) ? b : a,
        );
    await pump(tester, record);
    await scrollTo(tester, inFirstTab(find.text('Best figures')));

    expect(inFirstTab(find.text('Best figures')), findsOneWidget);
    final row = find.ancestor(of: inFirstTab(find.text('Best figures')), matching: find.byType(Row)).first;
    expect(
      find.descendant(of: row, matching: find.text(playerName(record.setup, best.playerId))),
      findsOneWidget,
      reason: 'the label sits in the row of the best bowler',
    );
  });

  testWidgets('with reduced motion the bars are full length at once', (tester) async {
    final record = cupFinal();
    await pump(tester, record, reduceMotion: true, settle: false);
    final inn = replay(record).innings.first;
    final top = inn.batters.map((b) => b.runs).reduce((a, b) => a > b ? a : b);
    final first = inFirstTab(find.byType(FractionallySizedBox)).evaluate().first.widget as FractionallySizedBox;
    expect(first.widthFactor, inn.batters.firstWhere((b) => b.runs > 0).runs / top);
  });

  testWidgets('tapping an innings in the summary card asks for its tab', (tester) async {
    final record = cupFinal();
    await pump(tester, record);
    final second = replay(record).innings[1];
    final team = record.setup.teamById(second.battingTeamId).name;
    await tester.tap(find.descendant(of: find.byType(ResultHero), matching: find.text(team)));
    await tester.pump(_settle);
    expect(opened, [1]);
  });

  testWidgets('every demo innings fits at 360 dp in the dark theme', (tester) async {
    for (final record in demo) {
      for (var i = 0; i < replay(record).innings.length; i++) {
        await pump(tester, record, innings: i, theme: AppTheme.dark());
        expect(tester.takeException(), isNull, reason: '${record.id} innings ${i + 1}');
      }
    }
  });
}
