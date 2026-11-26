import 'package:bnp_scorer/app.dart';
import 'package:bnp_scorer/data/app_settings.dart';
import 'package:bnp_scorer/data/scheduled_match.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/state/reminders.dart';
import 'package:bnp_scorer/state/upcoming.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/reminders.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

Team _squad(String id, String name) => Team(
      id: id,
      name: name,
      players: [for (var i = 1; i <= 3; i++) Player(id: '$id-$i', name: '$name P$i')],
    );

final _alpha = _squad('a', 'Alpha');
final _bravo = _squad('b', 'Bravo');
final _charlie = _squad('c', 'Charlie');

Tournament _cup() => Tournament(
      id: 't',
      name: 'Cup',
      oversPerInnings: 6,
      hasFinal: false,
      venue: 'Oval',
      teams: [_alpha, _bravo, _charlie],
      fixtures: roundRobinFixtures([_alpha, _bravo, _charlie]),
      createdAt: DateTime.utc(2026),
    );

ScheduledMatch _friendly(DateTime startsAt, {String id = 's1', String? venue}) => ScheduledMatch(
      id: id,
      teamA: _alpha,
      teamB: _bravo,
      oversPerInnings: 8,
      startsAt: startsAt,
      createdAt: DateTime.utc(2026),
      venue: venue,
    );

WatchedReminder _watched(DateTime startsAt, {String id = 'other/f1', String? tournamentId}) => WatchedReminder(
      id: id,
      homeName: 'Lions',
      awayName: 'Tigers',
      title: 'Diwali Cup · Final',
      startsAt: startsAt,
      venue: 'Ground 2',
      tournamentId: tournamentId,
    );

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  group('planReminders', () {
    final now = DateTime(2026, 11, 20, 12);

    test('reminds before each own match, worded with the teams, ground and time', () {
      final plan = planReminders(
        own: [UpcomingMatch.friendly(_friendly(DateTime(2026, 11, 20, 18), venue: 'Maidan'))],
        watched: const [],
        ownOn: true,
        lead: ReminderLead.hour1,
        now: now,
      );
      final r = plan.single;
      expect(r.at, DateTime(2026, 11, 20, 17));
      expect(r.title, 'Alpha v Bravo in 1 hour');
      expect(r.body, 'Friendly · Maidan · 6:00 PM');
      expect(r.payload, 'upcoming:s1');
    });

    test('leaves own matches out while reminders are off, but keeps followed ones', () {
      final plan = planReminders(
        own: [UpcomingMatch.friendly(_friendly(DateTime(2026, 11, 20, 18)))],
        watched: [_watched(DateTime(2026, 11, 21, 9))],
        ownOn: false,
        lead: ReminderLead.min30,
        now: now,
      );
      expect([for (final r in plan) r.payload], ['watched:other/f1']);
      expect(plan.single.title, 'Lions v Tigers in 30 min');
      expect(plan.single.body, 'Diwali Cup · Final · Ground 2 · 9:00 AM');
    });

    test('skips a reminder whose time has passed, and undated fixtures', () {
      final cup = _cup().withFixtureDate('f1', DateTime(2026, 11, 20, 12, 30));
      final plan = planReminders(
        own: [
          UpcomingMatch.fixture(cup, cup.fixtures[0]), // starts in 30 min: an hour's notice is gone
          UpcomingMatch.fixture(cup, cup.fixtures[1]), // no date
        ],
        watched: const [],
        ownOn: true,
        lead: ReminderLead.hour1,
        now: now,
      );
      expect(plan, isEmpty);
    });

    test('comes soonest first and stops at the cap, leaving room in the phone', () {
      final friendlies = [
        for (var i = maxReminders + 5; i > 0; i--)
          UpcomingMatch.friendly(_friendly(now.add(Duration(days: i)), id: 'f$i')),
      ];
      final plan = planReminders(
        own: friendlies,
        watched: const [],
        ownOn: true,
        lead: ReminderLead.min15,
        now: now,
      );
      expect(plan, hasLength(maxReminders));
      expect(plan.first.payload, 'upcoming:f1');
      expect(plan.last.payload, 'upcoming:f$maxReminders');
    });
  });

  group('notification ids', () {
    test('are stable, positive and differ between matches', () {
      expect(notificationIdOf('upcoming:s1'), notificationIdOf('upcoming:s1'));
      expect(notificationIdOf('upcoming:s1'), isNot(notificationIdOf('upcoming:s2')));
      for (final key in ['', 'upcoming:s1', 'watched:${'x' * 200}']) {
        expect(notificationIdOf(key), inInclusiveRange(0, 0x7fffffff), reason: key);
      }
    });

    test('a reminder payload is told apart from anything else', () {
      expect(isReminderPayload('upcoming:s1'), isTrue);
      expect(isReminderPayload('watched:t/f1'), isTrue);
      expect(isReminderPayload('match:m1'), isFalse);
      expect(isReminderPayload(null), isFalse);
    });
  });

  group('settings on the phone', () {
    late AppSettings settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = AppSettings(await SharedPreferences.getInstance());
    });

    test('reminders are undecided until set, and an hour before by default', () async {
      expect(settings.remindersOn, isNull);
      expect(settings.reminderLead, ReminderLead.hour1);
      await settings.setRemindersOn(false);
      expect(settings.remindersOn, isFalse);
      await settings.setRemindersOn(true);
      await settings.setReminderLead(ReminderLead.min15);
      expect((settings.remindersOn, settings.reminderLead), (true, ReminderLead.min15));
    });

    test('an unknown lead falls back to an hour', () {
      expect(ReminderLead.byName('fortnight'), ReminderLead.hour1);
      expect(ReminderLead.byName(null), ReminderLead.hour1);
    });

    test('followed matches survive a round trip, and a corrupt one is dropped', () async {
      final kept = _watched(DateTime.utc(2026, 11, 21, 3, 30), tournamentId: 'other');
      await settings.setWatchedReminders([kept]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(AppSettings.watchedRemindersKey, [
        ...prefs.getStringList(AppSettings.watchedRemindersKey)!,
        '{not json',
      ]);
      expect([for (final w in settings.watchedReminders) w.toJson()], [kept.toJson()]);
    });

    test('a followed match drops off 12 hours after it started', () {
      final now = DateTime(2026, 11, 20, 12);
      final list = liveWatched([
        _watched(now.subtract(const Duration(hours: 11)), id: 'this-morning'),
        _watched(now.subtract(const Duration(hours: 13)), id: 'last-night'),
      ], now);
      expect([for (final w in list) w.id], ['this-morning']);
    });
  });

  group('turning reminders on', () {
    late ProviderContainer container;
    late FakeDeviceNotifications device;
    late InMemoryScheduleRepository schedules;

    Future<void> start({bool allowed = false, bool grant = true}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      device = FakeDeviceNotifications(allowedNow: allowed, grant: grant);
      schedules = InMemoryScheduleRepository();
      container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings(prefs)),
          deviceNotificationsProvider.overrideWithValue(device),
          scheduleRepositoryProvider.overrideWithValue(schedules),
          tournamentRepositoryProvider.overrideWithValue(InMemoryTournamentRepository()),
          matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
        ],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
    }

    ReminderSettingsNotifier notifier() => container.read(reminderSettingsProvider.notifier);

    test('asks for permission, then saves the choice', () async {
      await start();
      expect(await notifier().setOwn(true), isNull);
      expect(device.prompts, 1);
      expect(container.read(reminderSettingsProvider).ownOn, isTrue);
      expect(container.read(appSettingsProvider).remindersOn, isTrue);
    });

    test('does not ask again when the phone already allows it', () async {
      await start(allowed: true);
      expect(await notifier().setOwn(true), isNull);
      expect(device.prompts, 0);
    });

    test('a refusal leaves reminders off and says how to turn them on', () async {
      await start(grant: false);
      expect(await notifier().setOwn(true), notificationsOffMessage);
      expect(container.read(reminderSettingsProvider).ownOn, isNull, reason: 'still offered');
    });

    test('turning off needs no permission', () async {
      await start(grant: false);
      expect(await notifier().setOwn(false), isNull);
      expect(device.prompts, 0);
      expect(container.read(reminderSettingsProvider).ownOn, isFalse);
    });

    test('follows and unfollows someone else\'s match, keeping it as last seen', () async {
      await start(allowed: true);
      final match = UpcomingMatch.friendly(_friendly(DateTime.now().add(const Duration(days: 1)), id: 'theirs'));
      expect(await notifier().toggleWatched(match), isNull);
      expect(notifier().isWatched('theirs'), isTrue);
      expect(container.read(appSettingsProvider).watchedReminders.single.homeName, 'Alpha');
      expect(await notifier().toggleWatched(match), isNull);
      expect(notifier().isWatched('theirs'), isFalse);
    });

    test('a followed match moved by its organiser moves its reminder', () async {
      await start(allowed: true);
      final at = DateTime.now().add(const Duration(days: 1));
      await notifier().toggleWatched(UpcomingMatch.friendly(_friendly(at, id: 'theirs')));
      final moved = at.add(const Duration(hours: 2));
      await notifier().refreshWatched([UpcomingMatch.friendly(_friendly(moved, id: 'theirs', venue: 'Park'))]);
      final w = container.read(reminderSettingsProvider).watched.single;
      expect((w.startsAt, w.venue), (moved, 'Park'));
    });

    test('the phone gets every reminder the plan makes, and none once turned off', () async {
      await start(allowed: true);
      final at = DateTime.now().add(const Duration(days: 1));
      await schedules.save(_friendly(at));
      container.listen(reminderSyncProvider, (_, _) {});
      await notifier().setOwn(true);
      await container.read(reminderSyncProvider.future);
      expect([for (final r in device.scheduled) r.payload], ['upcoming:s1']);
      expect(device.scheduled.single.at, at.subtract(const Duration(hours: 1)));

      await notifier().setLead(ReminderLead.min15);
      await container.read(reminderSyncProvider.future);
      expect(device.scheduled.single.at, at.subtract(const Duration(minutes: 15)));

      await notifier().setOwn(false);
      await container.read(reminderSyncProvider.future);
      expect(device.scheduled, isEmpty);
    });
  });

  group('on screen', () {
    late FakeDeviceNotifications device;
    late InMemoryScheduleRepository schedules;
    late InMemoryTournamentRepository tournaments;

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(_settle);
      }
    }

    DateTime tomorrowAt(int hour) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day + 1, hour);
    }

    Future<void> pump(WidgetTester tester, {Widget? home, bool allowed = false, bool grant = true}) async {
      tester.view
        ..physicalSize = const Size(1080, 6000)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      device.allowedNow = allowed;
      device.grant = grant;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings(prefs)),
          matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
          teamRepositoryProvider.overrideWithValue(InMemoryTeamRepository()),
          tournamentRepositoryProvider.overrideWithValue(tournaments),
          scheduleRepositoryProvider.overrideWithValue(schedules),
          deviceNotificationsProvider.overrideWithValue(device),
        ],
        child: home == null ? const BnpScorerApp() : MaterialApp(theme: AppTheme.light(), home: home),
      ));
      await settle(tester);
    }

    setUp(() {
      device = FakeDeviceNotifications();
      schedules = InMemoryScheduleRepository();
      tournaments = InMemoryTournamentRepository();
    });

    testWidgets('a match coming up offers reminders; Turn on asks, then shows the bell', (tester) async {
      await schedules.save(_friendly(tomorrowAt(18), venue: 'Maidan'));
      await pump(tester);

      expect(find.text('Get a reminder before each match'), findsOneWidget);
      expect(find.byKey(const Key('reminder-bell')), findsNothing);
      expect(device.scheduled, isEmpty);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Turn on'));
      await settle(tester);
      expect(device.prompts, 1);
      expect(find.text('Get a reminder before each match'), findsNothing);
      expect(find.text('Reminders on'), findsOneWidget);
      final bell = find.byKey(const Key('reminder-bell'));
      expect(bell, findsOneWidget);
      expect(tester.getSize(bell), const Size(16, 16), reason: 'a small mark, not a stretched one');
      expect(device.scheduled.single.title, 'Alpha v Bravo in 1 hour');
    });

    testWidgets('Not now hides the offer and sets nothing', (tester) async {
      await schedules.save(_friendly(tomorrowAt(18)));
      await pump(tester);
      await tester.tap(find.text('Not now'));
      await settle(tester);
      expect(find.text('Get a reminder before each match'), findsNothing);
      expect(device.prompts, 0);
      expect(device.scheduled, isEmpty);
    });

    testWidgets('a refusal says how to turn notifications on, and keeps offering', (tester) async {
      await schedules.save(_friendly(tomorrowAt(18)));
      await pump(tester, grant: false);
      await tester.tap(find.text('Turn on'));
      await settle(tester);
      expect(find.text(notificationsOffMessage), findsOneWidget);
      expect(find.text('Get a reminder before each match'), findsOneWidget);
    });

    testWidgets('the match sheet has the Remind me switch', (tester) async {
      await schedules.save(_friendly(tomorrowAt(18), venue: 'Maidan'));
      await pump(tester, allowed: true);
      await tester.tap(find.text('Friendly · Maidan'));
      await settle(tester);
      final remind = find.widgetWithText(SwitchListTile, 'Remind me');
      expect(remind, findsOneWidget);
      expect(find.text('1 hour before each of your matches'), findsOneWidget);
      await tester.tap(remind);
      await settle(tester);
      expect(tester.widget<SwitchListTile>(remind).value, isTrue);
      expect(device.scheduled, hasLength(1));
    });

    testWidgets('a followed match from Everyone gets its own switch', (tester) async {
      final match = UpcomingMatch.friendly(_friendly(tomorrowAt(18), id: 'theirs'));
      await pump(
        tester,
        allowed: true,
        home: Scaffold(body: ReminderSwitch(match: match, watching: true)),
      );
      expect(find.text('1 hour before it starts'), findsOneWidget);
      await tester.tap(find.text('Remind me'));
      await settle(tester);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
      final saved = AppSettings(await SharedPreferences.getInstance()).watchedReminders;
      expect([for (final w in saved) w.id], ['theirs']);
    });

    testWidgets('Settings turns reminders on and picks how long before', (tester) async {
      await schedules.save(_friendly(tomorrowAt(18)));
      await pump(tester, allowed: true, home: const Scaffold(body: SingleChildScrollView(child: ReminderSettingsPanel())));
      expect(find.text('How long before'), findsNothing, reason: 'only once something will be reminded');
      await tester.tap(find.text('Match reminders'));
      await settle(tester);
      expect(find.text('How long before'), findsOneWidget);
      await tester.tap(find.text('2 hours'));
      await settle(tester);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '2 hours')).selected, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Settings warns when the phone has turned notifications off', (tester) async {
      SharedPreferences.setMockInitialValues({AppSettings.remindersKey: 'on'});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings(prefs)),
          deviceNotificationsProvider.overrideWithValue(device), // allowedNow false
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SingleChildScrollView(child: ReminderSettingsPanel())),
        ),
      ));
      await settle(tester);
      expect(find.text(notificationsOffMessage), findsOneWidget);
    });

    testWidgets('tapping a reminder opens its match, ready to start', (tester) async {
      await schedules.save(_friendly(tomorrowAt(18), venue: 'Maidan'));
      await pump(tester, allowed: true);
      device.tap('upcoming:s1');
      await settle(tester);
      expect(find.text('Start match'), findsOneWidget);
      expect(find.text('Alpha v Bravo'), findsWidgets);
    });

    testWidgets('a reminder for a match since started or cancelled says so', (tester) async {
      await pump(tester, allowed: true);
      device.tap('upcoming:gone');
      await settle(tester);
      expect(find.text('That match has started or was cancelled.'), findsOneWidget);
    });

    testWidgets('a phone without notifications shows no offer or switch', (tester) async {
      await schedules.save(_friendly(tomorrowAt(18), venue: 'Maidan'));
      tester.view
        ..physicalSize = const Size(1080, 6000)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings(prefs)),
          matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
          teamRepositoryProvider.overrideWithValue(InMemoryTeamRepository()),
          tournamentRepositoryProvider.overrideWithValue(tournaments),
          scheduleRepositoryProvider.overrideWithValue(schedules),
        ],
        child: const BnpScorerApp(),
      ));
      await settle(tester);
      expect(find.text('Get a reminder before each match'), findsNothing);
      await tester.tap(find.text('Friendly · Maidan'));
      await settle(tester);
      expect(find.text('Remind me'), findsNothing);
    });
  });
}
