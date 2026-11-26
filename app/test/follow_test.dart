import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/app_settings.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/data/push_messages.dart';
import 'package:bnp_scorer/data/syncing_match_repository.dart';
import 'package:bnp_scorer/screens/home_screen.dart';
import 'package:bnp_scorer/screens/watch_match_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/format.dart';
import 'package:bnp_scorer/widgets/push_settings.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);
const _asha = Scorer(uid: 'u1', name: 'Asha Scorer');
const _viewer = Scorer(uid: 'viewer', name: 'Vijay');

/// Builds a match event by event, as the scoring screen does.
class _Match {
  _Match({int overs = 2}) : record = sampleRecord(overs: overs);

  MatchRecord record;
  var _n = 0;
  final _at = DateTime.utc(2026, 11, 5);

  MatchState get state => ScoringEngine.replay(record.setup, record.events);

  void add(MatchEvent e) => record = record.withEvents([...record.events, e]);
  String _id() => 'e${_n++}';

  void start() {
    add(OpenersSelected(id: _id(), at: _at, strikerId: 'a1', nonStrikerId: 'a2'));
    add(BowlerChanged(id: _id(), at: _at, bowlerId: 'b1'));
  }

  void runs(int r) => add(BallBowled(id: _id(), at: _at, runsOffBat: r, boundary: r >= 4));

  void caught(String fielder) => add(BallBowled(
        id: _id(),
        at: _at,
        runsOffBat: 0,
        wicket: Wicket(type: DismissalType.caught, batterOutId: state.current.strikerId!, fielderId: fielder),
      ));

  void bowler(String id) => add(BowlerChanged(id: _id(), at: _at, bowlerId: id));
}

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  group('what followers are told', () {
    test('the first ball starts the match', () {
      final m = _Match()..start();
      expect(matchHighlight(m.record), isNull, reason: 'picking a bowler is not news');
      m.runs(1);
      final h = matchHighlight(m.record)!;
      expect((h.seq, h.kind), (3, 'started'));
      expect(h.title, 'Ammapet Kings v Bazaar Strikers is underway');
      expect(h.body, 'Ammapet Kings batting first');
      m.runs(2);
      expect(matchHighlight(m.record), isNull, reason: 'an ordinary ball');
    });

    test('a wicket names the batter, how they went and the score', () {
      final m = _Match()
        ..start()
        ..runs(4)
        ..runs(1)
        ..runs(2);
      m.caught('b2');
      final h = matchHighlight(m.record)!;
      expect(h.kind, 'wicket');
      expect(h.title, 'WICKET! Arun c Bharat b Bilal 2 (2)');
      expect(h.body, 'Ammapet Kings 7/1 (0.4 ov) v Bazaar Strikers');
    });

    test('the innings break gives the target, and the result both scores', () {
      final m = _Match(overs: 1)..start();
      for (final r in [1, 2, 3, 0, 0]) {
        m.runs(r);
      }
      m.runs(4);
      final brk = matchHighlight(m.record)!;
      expect(brk.title, 'Innings break: Ammapet Kings 10/0 (1 ov)');
      expect(brk.body, 'Bazaar Strikers need 11 to win');

      m.add(OpenersSelected(id: 'o2', at: DateTime.utc(2026), strikerId: 'b1', nonStrikerId: 'b2'));
      m.bowler('a1');
      m.runs(6);
      m.runs(4);
      m.runs(1);
      final result = matchHighlight(m.record)!;
      expect(result.kind, 'result');
      expect(result.title, startsWith('Bazaar Strikers won by'));
      expect(result.body, 'Ammapet Kings 10/0 (1 ov) · Bazaar Strikers 11/0 (0.3 ov)');
    });

    test('long text is clipped to what the rules accept', () {
      expect(clip('abcdef', 10), 'abcdef');
      expect(clip('abcdefghijkl', 5), 'abcd…');
      expect(clip('x' * 500, highlightTitleMax), hasLength(highlightTitleMax));
    });

    test('a log that cannot be replayed makes no highlight', () {
      final m = _Match()..runs(1); // no openers yet
      expect(matchHighlight(m.record), isNull);
    });
  });

  group('publishing', () {
    test('each published ball carries its highlight, or none', () async {
      final cloud = FakeCloudMatches();
      final repository = SyncingMatchRepository(
        InMemoryMatchRepository(),
        cloud,
        FakeAccounts(signedIn: _asha),
        highlight: matchHighlight,
      );
      final m = _Match()..start();
      m.record = MatchRecord(
        setup: m.record.setup,
        events: m.record.events,
        createdAt: m.record.createdAt,
        updatedAt: m.record.updatedAt,
        publishedBy: 'u1',
      );
      m.runs(1);
      await repository.save(m.record);
      m.runs(1);
      await repository.save(m.record);
      await pumpEventQueue();
      expect([for (final h in cloud.highlights) h?.kind], ['started', null]);
    });
  });

  group('following', () {
    late ProviderContainer container;
    late FakeDeviceNotifications device;
    late FakePushDevices devices;

    Future<void> start({Map<String, Object> prefs = const {}, bool grant = true}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final stored = await SharedPreferences.getInstance();
      device = FakeDeviceNotifications(grant: grant);
      devices = FakePushDevices();
      container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings(stored)),
          deviceNotificationsProvider.overrideWithValue(device),
          accountsProvider.overrideWithValue(FakeAccounts(signedIn: _viewer)),
          pushMessagesProvider.overrideWithValue(FakePushMessages()),
          pushDevicesProvider.overrideWithValue(devices),
        ],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
    }

    FollowedMatchesNotifier follows() => container.read(followedMatchesProvider.notifier);

    test('following turns match updates on, asking once, and registers the match', () async {
      await start();
      container.listen(scorerProvider, (_, _) {});
      container.listen(pushSyncProvider, (_, _) {});
      await container.read(scorerProvider.future);
      expect(await follows().toggle('m1'), isNull);
      expect(device.prompts, 1);
      expect(container.read(pushKindsProvider), {PushKind.follow});
      await container.read(pushSyncProvider.future);
      expect(devices.saved.values.single.follows, ['m1']);

      expect(await follows().toggle('m2'), isNull);
      expect(device.prompts, 1, reason: 'asked only the first time');
      await container.read(pushSyncProvider.future);
      expect(devices.saved.values.single.follows, ['m1', 'm2']);

      await follows().toggle('m1');
      await container.read(pushSyncProvider.future);
      expect(devices.saved.values.single.follows, ['m2']);
    });

    test('a refusal follows nothing', () async {
      await start(grant: false);
      expect(await follows().toggle('m1'), notificationsOffMessage);
      expect(container.read(followedMatchesProvider), isEmpty);
    });

    test('a match followed more than two days ago is dropped', () async {
      final old = DateTime.now().subtract(const Duration(days: 3)).toUtc().toIso8601String();
      final recent = DateTime.now().subtract(const Duration(hours: 5)).toUtc().toIso8601String();
      await start(prefs: {AppSettings.followedMatchesKey: '{"old":"$old","recent":"$recent"}'});
      expect(container.read(followedMatchesProvider).keys, ['recent']);
    });

    test('a damaged list is forgotten, not fatal', () async {
      await start(prefs: {AppSettings.followedMatchesKey: '{oops'});
      expect(container.read(followedMatchesProvider), isEmpty);
    });
  });

  group('on screen', () {
    late FakeDeviceNotifications device;
    late FakePushMessages push;
    late FakeCloudMatches cloud;

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(_settle);
      }
    }

    Future<void> pump(WidgetTester tester, Widget home, {Scorer? signedIn = _viewer}) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      device = FakeDeviceNotifications(allowedNow: true);
      push = FakePushMessages();
      cloud = FakeCloudMatches();
      final m = _Match()
        ..start()
        ..runs(1);
      await cloud.publish(m.record, _asha);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings(prefs)),
          deviceNotificationsProvider.overrideWithValue(device),
          accountsProvider.overrideWithValue(FakeAccounts(signedIn: signedIn)),
          pushMessagesProvider.overrideWithValue(push),
          pushDevicesProvider.overrideWithValue(FakePushDevices()),
          cloudMatchesProvider.overrideWithValue(cloud),
          matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
          teamRepositoryProvider.overrideWithValue(InMemoryTeamRepository()),
          tournamentRepositoryProvider.overrideWithValue(InMemoryTournamentRepository()),
          scheduleRepositoryProvider.overrideWithValue(InMemoryScheduleRepository()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ));
      await settle(tester);
    }

    final bell = find.byType(FollowMatchButton);

    testWidgets('the bell on a watched match follows it, and taps again to stop', (tester) async {
      await pump(tester, const WatchMatchScreen(matchId: 'm1'));
      final button = find.descendant(of: bell, matching: find.byType(IconButton));
      expect(button, findsOneWidget);
      expect(tester.widget<IconButton>(button).isSelected, isFalse);
      await tester.tap(button);
      await settle(tester);
      expect(tester.widget<IconButton>(button).isSelected, isTrue);
      expect(find.textContaining("Following: you'll hear about wickets"), findsOneWidget);
      await tester.tap(button);
      await settle(tester);
      expect(tester.widget<IconButton>(button).isSelected, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed out, the bell says to sign in', (tester) async {
      await pump(tester, const WatchMatchScreen(matchId: 'm1'), signedIn: null);
      await tester.tap(find.descendant(of: bell, matching: find.byType(IconButton)));
      await settle(tester);
      expect(find.text('Sign in from Settings to follow matches.'), findsOneWidget);
      expect(device.prompts, 0);
    });

    testWidgets('the scorer sees no bell on their own match', (tester) async {
      await pump(tester, const WatchMatchScreen(matchId: 'm1'), signedIn: _asha);
      expect(find.descendant(of: bell, matching: find.byType(IconButton)), findsNothing);
    });

    testWidgets('tapping a match update opens the match live', (tester) async {
      await pump(tester, const HomeScreen());
      push.tapInBackground(const PushNotice(title: 'WICKET!', body: '', data: {'open': 'match:m1'}));
      await settle(tester);
      expect(find.byType(WatchMatchScreen), findsOneWidget);
    });
  });
}
