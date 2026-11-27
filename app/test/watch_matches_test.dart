import 'package:bnp_scorer/app.dart';
import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/app_settings.dart';
import 'package:bnp_scorer/data/cloud_matches.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/screens/watch_match_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/match_card.dart';
import 'package:bnp_scorer/widgets/score_header.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);
const _asha = Scorer(uid: 'u1', name: 'Asha Scorer');
final _at = DateTime.utc(2026, 11, 17, 10);

/// A published match: openers, a bowler, then [balls] off the bat, last
/// saved just now unless [savedAgo] says how long ago.
MatchRecord _match(List<int> balls, {String id = 'pub1', Duration savedAgo = Duration.zero}) {
  final record = sampleRecord(id: id, events: [
    OpenersSelected(id: 'o', at: _at, strikerId: 'a1', nonStrikerId: 'a2'),
    BowlerChanged(id: 'b', at: _at, bowlerId: 'b1'),
    for (final (i, runs) in balls.indexed)
      BallBowled(id: 'r$i', at: _at, runsOffBat: runs, boundary: runs == 4 || runs == 6),
  ]);
  return MatchRecord(
    setup: record.setup,
    events: record.events,
    createdAt: _at,
    updatedAt: DateTime.now().subtract(savedAgo),
    publishedBy: 'u1',
  );
}

class _BrokenCloud extends FakeCloudMatches {
  @override
  Stream<List<PublishedMatch>> recent({int limit = 30}) => Stream.error(StateError('offline'));
}

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  /// The whole app at 360 dp, with or without the cloud.
  Future<void> pumpApp(WidgetTester tester, {CloudMatches? cloud}) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(AppSettings(prefs)),
        matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
        teamRepositoryProvider.overrideWithValue(InMemoryTeamRepository()),
        tournamentRepositoryProvider.overrideWithValue(InMemoryTournamentRepository()),
        if (cloud != null) ...[
          cloudMatchesProvider.overrideWithValue(cloud),
          accountsProvider.overrideWithValue(FakeAccounts()),
        ],
      ],
      child: const BnpScorerApp(),
    ));
    await settle(tester);
  }

  Future<void> showEveryone(WidgetTester tester) async {
    await tester.tap(find.text('Everyone'));
    await settle(tester);
  }

  testWidgets('a build without the cloud has no Everyone switch', (tester) async {
    await pumpApp(tester);
    expect(find.text('Everyone'), findsNothing);
    expect(find.text('My matches'), findsNothing);
  });

  testWidgets('with no matches of your own, Everyone is still there and says what to do', (tester) async {
    await pumpApp(tester, cloud: FakeCloudMatches());
    expect(find.text('My matches'), findsOneWidget);
    await showEveryone(tester);
    expect(find.textContaining('No public matches yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lost connection is explained', (tester) async {
    await pumpApp(tester, cloud: _BrokenCloud());
    await showEveryone(tester);
    expect(find.text('Could not load public matches. Check your connection and try again.'), findsOneWidget);
  });

  testWidgets('published matches show who scores them, and cannot be deleted here', (tester) async {
    final cloud = FakeCloudMatches();
    await cloud.publish(_match([4]), _asha);
    await pumpApp(tester, cloud: cloud);
    await showEveryone(tester);

    expect(find.text('Scored by Asha Scorer'), findsOneWidget);
    expect(find.text('Live and recent'), findsOneWidget);
    final scorer = tester.getRect(find.text('Scored by Asha Scorer'));
    expect(scorer.right, lessThanOrEqualTo(360));

    // Holding a public card offers no delete; letting go simply opens it.
    await tester.longPress(find.text('Scored by Asha Scorer'));
    await settle(tester);
    expect(find.text('Delete this match?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('watching a match is read-only and follows every ball', (tester) async {
    final cloud = FakeCloudMatches();
    await cloud.publish(_match([4]), _asha);
    await pumpApp(tester, cloud: cloud);
    await showEveryone(tester);
    await tester.tap(find.text('Scored by Asha Scorer'));
    await settle(tester);

    expect(find.byType(WatchMatchScreen), findsOneWidget);
    expect(find.text('4s 1 · 6s 0 · SR 400.0'), findsOneWidget);
    expect(find.textContaining('Scored by Asha Scorer. Updates as each ball'), findsOneWidget);
    expect(find.text('OUT'), findsNothing, reason: 'no score pad');
    expect(find.byTooltip('Undo last action'), findsNothing);
    expect(find.byTooltip('Share'), findsOneWidget);

    // A watcher can pass the match on as a link to its page.
    await tester.tap(find.byTooltip('Share'));
    await settle(tester);
    expect(find.text('Share a link to the match'), findsOneWidget);
    await tester.tapAt(const Offset(180, 40));
    await settle(tester);

    // The scorer hits a six.
    await cloud.publish(_match([4, 6]), _asha);
    await settle(tester);
    expect(find.text('4s 1 · 6s 1 · SR 500.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a match nobody has scored for hours says STOPPED, not LIVE', (tester) async {
    final cloud = FakeCloudMatches();
    await cloud.publish(_match([4], id: 'old', savedAgo: const Duration(hours: 7)), _asha);
    await cloud.publish(_match([6], id: 'new', savedAgo: const Duration(hours: 5)), const Scorer(uid: 'u2', name: 'Bala'));
    await pumpApp(tester, cloud: cloud);
    await showEveryone(tester);

    final oldCard = find.ancestor(of: find.text('Scored by Asha Scorer'), matching: find.byType(MatchCard));
    final newCard = find.ancestor(of: find.text('Scored by Bala'), matching: find.byType(MatchCard));
    expect(find.descendant(of: oldCard, matching: find.text('STOPPED')), findsOneWidget);
    expect(find.descendant(of: oldCard, matching: find.text('LIVE')), findsNothing);
    expect(find.descendant(of: newCard, matching: find.text('LIVE')), findsOneWidget);
    expect(find.descendant(of: newCard, matching: find.text('STOPPED')), findsNothing);
    final tag = tester.getSize(find.byType(StatusTag));
    expect(tag.width, lessThan(120), reason: 'a small tag, not a bar across the card');
    expect(tag.height, lessThan(32));

    // Watching it says so too, and why.
    await tester.tap(find.text('Scored by Asha Scorer'));
    await settle(tester);
    expect(find.byType(WatchMatchScreen), findsOneWidget);
    final header = find.byType(ScoreHeader);
    expect(find.descendant(of: header, matching: find.text('STOPPED')), findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('LIVE')), findsNothing);
    expect(find.textContaining('No ball for some hours'), findsOneWidget);

    // The scorer comes back and bowls: live again.
    await cloud.publish(_match([4, 1], id: 'old'), _asha);
    await settle(tester);
    expect(find.descendant(of: header, matching: find.text('LIVE')), findsOneWidget);
    expect(find.descendant(of: header, matching: find.text('STOPPED')), findsNothing);
    expect(find.textContaining('Updates as each ball'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a match unpublished while watching says so', (tester) async {
    final cloud = FakeCloudMatches();
    await cloud.publish(_match([1]), _asha);
    await pumpApp(tester, cloud: cloud);
    await showEveryone(tester);
    await tester.tap(find.text('Scored by Asha Scorer'));
    await settle(tester);

    await cloud.unpublish('pub1');
    await settle(tester);
    expect(find.text(WatchMatchScreen.goneMessage), findsOneWidget);
  });

  group('WatchMatchScreen on its own', () {
    Future<void> pumpWatch(WidgetTester tester, FakeCloudMatches cloud) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [cloudMatchesProvider.overrideWithValue(cloud)],
        child: MaterialApp(theme: AppTheme.dark(), home: const WatchMatchScreen(matchId: 'pub1')),
      ));
      await settle(tester);
    }

    testWidgets('a match this app cannot read gets a clear message', (tester) async {
      final cloud = FakeCloudMatches();
      await cloud.publish(_match([1]), _asha);
      cloud.unreadable.add('pub1');
      await pumpWatch(tester, cloud);
      expect(find.text(WatchMatchScreen.unreadableMessage), findsOneWidget);
    });

    testWidgets('a log that does not replay is not shown as a scorecard', (tester) async {
      final cloud = FakeCloudMatches();
      final good = _match([1]);
      // A ball before any openers: the engine refuses it.
      final broken = MatchRecord(
        setup: good.setup,
        events: [BallBowled(id: 'x', at: _at, runsOffBat: 1)],
        createdAt: _at,
        updatedAt: _at,
        publishedBy: 'u1',
      );
      await cloud.publish(broken, _asha);
      await pumpWatch(tester, cloud);
      expect(find.text(WatchMatchScreen.unreadableMessage), findsOneWidget);
    });

    testWidgets('a finished match opens on its result', (tester) async {
      final cloud = FakeCloudMatches();
      await cloud.publish(_match([4]), _asha);
      final record = cloud.published['pub1']!;
      await cloud.publish(
        record.withEvents([...record.events, MatchAbandoned(id: 'end', at: _at, reason: 'Rain')]),
        _asha,
      );
      await pumpWatch(tester, cloud);
      expect(find.text('Result'), findsOneWidget);
      expect(find.text('Live'), findsNothing);
    });
  });

  group('parsePublishedMatch', () {
    test('reads a document back into the match and its scorer', () {
      final record = _match([4]);
      final parsed = parsePublishedMatch({...record.toJson(), 'ownerUid': 'u1', 'ownerName': 'Asha Scorer', 'schema': 1});
      expect(parsed.ownerName, 'Asha Scorer');
      expect(parsed.record.events, hasLength(3));
      expect(parsed.record.publishedBy, 'u1');
    });

    test('refuses a newer format instead of showing it wrongly', () {
      final record = _match([4]);
      expect(
        () => parsePublishedMatch({...record.toJson(), 'ownerUid': 'u1', 'schema': FirestoreCloudMatches.schema + 1}),
        throwsFormatException,
      );
    });
  });
}
