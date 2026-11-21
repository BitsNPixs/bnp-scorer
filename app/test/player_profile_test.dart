import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/data/player_directory.dart';
import 'package:bnp_scorer/screens/player_profile_screen.dart';
import 'package:bnp_scorer/screens/scoring_screen.dart';
import 'package:bnp_scorer/screens/watch_match_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/format.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);
final _now = DateTime.utc(2026, 11, 6);
const _other = Scorer(uid: 'u2', name: 'Bilal Scorer');

/// The demo matches, oldest first, replayed.
final _demo = demoMatches(_now)..sort((a, b) => a.createdAt.compareTo(b.createdAt));
final _book = computeStats(_demo.map((m) => ScoringEngine.replay(m.setup, m.events)));

String _cell(WidgetTester tester, String row, String column) =>
    tester.widget<Text>(find.byKey(ValueKey('stat:$row:$column'))).data!;

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  Future<void> pump(
    WidgetTester tester,
    String playerId, {
    bool seeded = true,
    FakeCloudMatches? cloud,
    FakePlayerDirectory? directory,
  }) async {
    // 360 dp wide, like the smallest phones the app is tested at.
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = InMemoryMatchRepository();
    if (seeded) await seedDemoMatches(repo, now: _now);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(repo),
        tournamentRepositoryProvider.overrideWithValue(InMemoryTournamentRepository()),
        cloudMatchesProvider.overrideWithValue(cloud),
        playerDirectoryProvider.overrideWithValue(directory),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: PlayerProfileScreen(playerId: playerId)),
    ));
    await settle(tester);
  }

  Future<void> showTab(WidgetTester tester, String tab) async {
    final finder = find.descendant(of: find.byType(TabBar), matching: find.text(tab));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  testWidgets('the header and Info tab show the player, their form and teams', (tester) async {
    final top = _book.batters.first;
    await pump(tester, top.playerId);

    expect(find.text(top.name), findsWidgets);
    expect(find.text(plural(top.matches, 'match')), findsOneWidget);
    expect(find.text('PERSONAL INFORMATION'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('RECENT FORM · BATTING'), findsOneWidget);
    final innings = top.batting.innings < 5 ? top.batting.innings : 5;
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(innings));
    expect(find.text(top.teamName), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Batting table adds up like the engine', (tester) async {
    final top = _book.batters.first;
    await pump(tester, top.playerId);
    await showTab(tester, 'Batting');

    expect(_cell(tester, 'Matches', 'All'), '${top.matches}');
    expect(_cell(tester, 'Runs', 'All'), '${top.batting.runs}');
    expect(_cell(tester, 'Highest', 'All'), highScoreText(top.batting.high));
    expect(_cell(tester, 'Average', 'All'), decimal(top.batting.average));
    expect(_cell(tester, 'Ducks', 'All'), '${top.batting.ducks}');
    // Every demo match is ten overs: one format, so no format columns.
    expect(find.byKey(const ValueKey('stat:Runs:T10')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Last 10 counts only the latest ten matches', (tester) async {
    // The busiest all-rounder, so both tables have numbers.
    final regular = _book.players
        .where((p) => p.batting.innings > 0 && p.bowling.innings > 0)
        .reduce((a, b) => a.matches >= b.matches ? a : b);
    await pump(tester, regular.playerId);
    await showTab(tester, 'Batting');
    await tester.tap(find.text('Last 10'));
    await settle(tester);
    expect(_cell(tester, 'Matches', 'All'), '${regular.matches < 10 ? regular.matches : 10}');

    // The choice carries over to the bowling table.
    await showTab(tester, 'Bowling');
    expect(_cell(tester, 'Matches', 'All'), '${regular.matches < 10 ? regular.matches : 10}');
  });

  testWidgets('a player who never bowled gets a note, not a table of zeros', (tester) async {
    final batter = _book.players.firstWhere((p) => p.bowling.innings == 0 && p.batting.innings > 0);
    await pump(tester, batter.playerId);
    await showTab(tester, 'Bowling');
    expect(find.text('Has not bowled in these matches.'), findsOneWidget);
    expect(find.byKey(const ValueKey('stat:Wickets:All')), findsNothing);
  });

  testWidgets('the Bowling table adds up like the engine', (tester) async {
    final top = _book.bowlers.first;
    await pump(tester, top.playerId);
    await showTab(tester, 'Bowling');
    // The headline repeats the three numbers that matter most.
    expect(find.text('${top.bowling.wickets}'), findsNWidgets(2));
    expect(find.text(bestBowlingText(top.bowling.best)), findsNWidgets(2));

    expect(_cell(tester, 'Wickets', 'All'), '${top.bowling.wickets}');
    expect(_cell(tester, 'Overs', 'All'), top.bowling.oversText);
    expect(_cell(tester, 'Best', 'All'), bestBowlingText(top.bowling.best));
    expect(_cell(tester, 'Economy', 'All'), decimal(top.bowling.economy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Career tab shows debut and last match, and opens them', (tester) async {
    final top = _book.batters.first;
    await pump(tester, top.playerId);
    await showTab(tester, 'Career');

    expect(find.text('ALL MATCHES'), findsOneWidget);
    expect(find.text('Debut'), findsWidgets);
    expect(find.textContaining('vs '), findsWidgets);
    // Ten-over matches only: the longer formats were never played.
    expect(find.text('Not played'), findsNWidgets(4));
    expect(tester.takeException(), isNull);

    await tester.tap(find.textContaining('vs ').first);
    await settle(tester);
    expect(find.byType(ScoringScreen), findsOneWidget);
  });

  testWidgets('a match published from another phone counts and opens read-only', (tester) async {
    final played = _demo.firstWhere((m) => ScoringEngine.replay(m.setup, m.events).isCompleted);
    final playerId = played.setup.teamA.players.first.id;
    final cloud = FakeCloudMatches();
    await cloud.publish(
      MatchRecord(setup: played.setup, events: played.events, createdAt: played.createdAt, updatedAt: played.updatedAt),
      _other,
    );
    await pump(tester, playerId, seeded: false, cloud: cloud);

    expect(find.text('1 match'), findsOneWidget);
    await tester.tap(find.text('View all matches'));
    await settle(tester);
    expect(find.text('1 match'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await showTab(tester, 'Career');
    await tester.tap(find.textContaining('vs ').first);
    await settle(tester);
    expect(find.byType(WatchMatchScreen), findsOneWidget);
  });

  testWidgets('without the cloud it says so and shows this phone', (tester) async {
    final top = _book.batters.first;
    await pump(tester, top.playerId, cloud: FakeCloudMatches()..failReads = true);
    expect(find.text('Could not reach the cloud. Showing matches on this phone only.'), findsOneWidget);
    expect(find.text(plural(top.matches, 'match')), findsOneWidget);
  });

  testWidgets('a claimed profile is marked verified, an invited one not', (tester) async {
    final top = _book.batters.first;
    final directory = FakePlayerDirectory()
      ..players[top.playerId] = PlayerProfile(id: top.playerId, name: top.name, ownerUid: 'u9');
    await pump(tester, top.playerId, directory: directory);
    expect(find.text('Verified'), findsOneWidget);

    final invited = FakePlayerDirectory()..players[top.playerId] = PlayerProfile(id: top.playerId, name: 'Ravi');
    await pump(tester, top.playerId, directory: invited);
    expect(find.text('Invited, not claimed yet'), findsOneWidget);
    // The directory's name wins over the one in old scorecards.
    expect(find.text('Ravi'), findsWidgets);
  });

  testWidgets('a player with no finished match says so on every tab', (tester) async {
    await pump(tester, 'nobody', seeded: false);
    expect(find.text('Player'), findsWidgets);
    expect(find.text('No finished matches yet.'), findsOneWidget);
    for (final tab in ['Batting', 'Bowling', 'Career']) {
      await showTab(tester, tab);
      expect(find.text('No finished matches yet.'), findsOneWidget, reason: tab);
    }
    expect(tester.takeException(), isNull);
  });

  group('career tables', () {
    CareerMatch match(String id, int overs, DateTime at) {
      final record = sampleRecord(id: id, overs: overs);
      final dated = MatchRecord(setup: record.setup, events: record.events, createdAt: at, updatedAt: at);
      return (record: dated, state: ScoringEngine.replay(dated.setup, dated.events), onPhone: true);
    }

    test('one format gives only the All column', () {
      final played = [match('a', 10, _now), match('b', 6, _now)];
      expect(careerColumns(played, played).map((c) => c.$1), ['All']);
    });

    test('more than one format adds a column for each format played', () {
      final played = [match('a', 10, _now), match('b', 20, _now), match('c', 8, _now)];
      final columns = careerColumns(played, played);
      expect(columns.map((c) => c.$1), ['All', 'T10', 'T20']);
      expect(columns[1].$2.map((m) => m.record.id), ['a', 'c']);
      expect(columns[2].$2.map((m) => m.record.id), ['b']);
    });

    test('periods pick this year or the latest ten', () {
      final played = [
        match('old', 10, DateTime(2025, 6)),
        for (var i = 0; i < 11; i++) match('m$i', 10, DateTime(2026, 3, i + 1)),
      ];
      final now = DateTime(2026, 11, 6);
      expect(matchesIn(played, CareerPeriod.career, now), hasLength(12));
      expect(matchesIn(played, CareerPeriod.thisYear, now).map((m) => m.record.id), isNot(contains('old')));
      expect(matchesIn(played, CareerPeriod.lastTen, now).map((m) => m.record.id).first, 'm1');
      expect(matchesIn(played.take(3).toList(), CareerPeriod.lastTen, now), hasLength(3));
    });
  });
}
