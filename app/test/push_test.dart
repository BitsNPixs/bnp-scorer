import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/app_settings.dart';
import 'package:bnp_scorer/data/push_messages.dart';
import 'package:bnp_scorer/data/push_registration.dart';
import 'package:bnp_scorer/screens/home_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/push_settings.dart';
import 'package:bnp_scorer/widgets/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);
const _asha = Scorer(uid: 'asha', name: 'Asha');
const _bala = Scorer(uid: 'bala', name: 'Bala');

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  group('PushDevice', () {
    test('writes the fields the Functions read, every kind named', () {
      const device = PushDevice(
        id: 'd1',
        ownerUid: 'asha',
        token: 't',
        platform: 'android',
        kinds: {PushKind.team},
      );
      expect(device.toJson(), {
        'ownerUid': 'asha',
        'token': 't',
        'platform': 'android',
        'kinds': {'follow': false, 'team': true, 'cup': false},
      });
    });
  });

  group('PushRegistration', () {
    late AppSettings settings;
    late FakePushMessages push;
    late FakePushDevices devices;
    late PushRegistration registration;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = AppSettings(await SharedPreferences.getInstance());
      push = FakePushMessages();
      devices = FakePushDevices();
      registration = PushRegistration(push: push, devices: devices, settings: settings, platform: 'android');
    });

    test('registers a signed-in scorer who wants an update, under this install', () async {
      await registration.sync(_asha, {PushKind.follow, PushKind.cup});
      final saved = devices.saved[settings.deviceId]!;
      expect((saved.ownerUid, saved.token, saved.platform), ('asha', 'token-1', 'android'));
      expect(saved.kinds, {PushKind.follow, PushKind.cup});
      expect(settings.pushRegistered, isTrue);
      expect(settings.deviceId, settings.deviceId, reason: 'the same id every time');
    });

    test('makes no token and no registration until a kind is on', () async {
      await registration.sync(_asha, {});
      await registration.sync(null, {PushKind.follow});
      expect(push.enabled, isFalse, reason: 'never registered with Google for push');
      expect(devices.saved, isEmpty);
    });

    test('turning every kind off removes the registration and the token', () async {
      await registration.sync(_asha, {PushKind.team});
      await registration.sync(_asha, {});
      expect(devices.saved, isEmpty);
      expect(push.enabled, isFalse);
      expect(settings.pushRegistered, isFalse);
    });

    test('a rotated token replaces the old one on the same registration', () async {
      await registration.sync(_asha, {PushKind.team});
      push.refresh('token-2');
      await registration.sync(_asha, {PushKind.team});
      expect(devices.saved.values.single.token, 'token-2');
    });

    test('forgetting before sign-out removes it, so the next person gets nothing of it', () async {
      await registration.sync(_asha, {PushKind.team});
      await registration.forget();
      expect(devices.saved, isEmpty);
      expect(push.enabled, isFalse);
    });

    test('if removing fails, the token still goes, so nothing can reach it', () async {
      await registration.sync(_asha, {PushKind.team});
      devices.failDelete = true;
      await registration.forget();
      expect(push.enabled, isFalse);
      expect(settings.pushRegistered, isTrue, reason: 'tried again next time');
    });

    test('a registration left by the last account is not taken over: a new one is made', () async {
      await registration.sync(_asha, {PushKind.team});
      final old = settings.deviceId;
      // Asha's removal failed at sign-out; Bala signs in on the same phone.
      await registration.sync(_bala, {PushKind.follow});
      expect(settings.deviceId, isNot(old));
      expect(devices.saved[old]!.ownerUid, 'asha');
      expect(devices.saved[settings.deviceId]!.ownerUid, 'bala');
    });

    test('a test asks for this install', () async {
      await registration.sync(_asha, {PushKind.team});
      await registration.requestTest();
      expect(devices.tests, [settings.deviceId]);
    });

    test('does nothing at all where push is not available', () async {
      final none = PushRegistration(push: const NoPushMessages(), devices: devices, settings: settings);
      expect(none.available, isFalse);
      await none.sync(_asha, {PushKind.team});
      expect(devices.saved, isEmpty);
    });
  });

  group('choosing updates', () {
    late ProviderContainer container;
    late FakeDeviceNotifications device;
    late FakeAccounts accounts;
    late FakePushDevices devices;

    Future<void> start({Scorer? signedIn = _asha, bool grant = true}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      device = FakeDeviceNotifications(grant: grant);
      accounts = FakeAccounts(signedIn: signedIn);
      devices = FakePushDevices();
      container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings(prefs)),
          deviceNotificationsProvider.overrideWithValue(device),
          accountsProvider.overrideWithValue(accounts),
          pushMessagesProvider.overrideWithValue(FakePushMessages()),
          pushDevicesProvider.overrideWithValue(devices),
        ],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
    }

    PushKindsNotifier kinds() => container.read(pushKindsProvider.notifier);

    test('turning one on asks for permission, then the phone is registered', () async {
      await start();
      container.listen(scorerProvider, (_, _) {});
      container.listen(pushSyncProvider, (_, _) {});
      await container.read(scorerProvider.future);
      expect(await kinds().set(PushKind.follow, true), isNull);
      expect(device.prompts, 1);
      await container.read(pushSyncProvider.future);
      expect(devices.saved.values.single.kinds, {PushKind.follow});
      expect(container.read(appSettingsProvider).pushKinds, {PushKind.follow});
    });

    test('signed out, it says to sign in and asks nothing', () async {
      await start(signedIn: null);
      expect(await kinds().set(PushKind.team, true), 'Sign in first, so updates know who they are for.');
      expect(device.prompts, 0);
      expect(container.read(pushKindsProvider), isEmpty);
    });

    test('a refusal leaves it off and says how to turn notifications on', () async {
      await start(grant: false);
      expect(await kinds().set(PushKind.cup, true), notificationsOffMessage);
      expect(container.read(pushKindsProvider), isEmpty);
    });

    test('turning one off needs nothing', () async {
      await start();
      await kinds().set(PushKind.cup, true);
      expect(await kinds().set(PushKind.cup, false), isNull);
      expect(container.read(pushKindsProvider), isEmpty);
    });
  });

  group('on screen', () {
    late FakeDeviceNotifications device;
    late FakePushMessages push;
    late FakePushDevices devices;
    late FakeAccounts accounts;

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(_settle);
      }
    }

    Future<void> pump(WidgetTester tester, Widget home, {Scorer? signedIn = _asha}) async {
      tester.view
        ..physicalSize = const Size(1080, 6000)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      device = FakeDeviceNotifications(allowedNow: true);
      push = FakePushMessages();
      devices = FakePushDevices();
      accounts = FakeAccounts(signedIn: signedIn);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings(prefs)),
          deviceNotificationsProvider.overrideWithValue(device),
          accountsProvider.overrideWithValue(accounts),
          pushMessagesProvider.overrideWithValue(push),
          pushDevicesProvider.overrideWithValue(devices),
          matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
          teamRepositoryProvider.overrideWithValue(InMemoryTeamRepository()),
          tournamentRepositoryProvider.overrideWithValue(InMemoryTournamentRepository()),
          scheduleRepositoryProvider.overrideWithValue(InMemoryScheduleRepository()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ));
      await settle(tester);
    }

    const panel = Scaffold(body: SingleChildScrollView(child: PushSettingsPanel()));

    testWidgets('signed out, Settings says what signing in gets you', (tester) async {
      await pump(tester, panel, signedIn: null);
      expect(find.text('Live updates'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('a switch per kind, and a test button once one is on', (tester) async {
      await pump(tester, panel);
      for (final kind in PushKind.values) {
        expect(find.widgetWithText(SwitchListTile, kind.title), findsOneWidget);
      }
      expect(find.text('Send me a test notification'), findsNothing);
      await tester.tap(find.text('Team activity'));
      await settle(tester);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Team activity')).value, isTrue);
      await tester.tap(find.text('Send me a test notification'));
      await settle(tester);
      expect(devices.tests, hasLength(1));
      expect(find.text('Sent. It should arrive in a few seconds.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signing out removes this phone from updates first', (tester) async {
      await pump(tester, const HomeScreen());
      await tester.runAsync(() async {
        final context = tester.element(find.byType(HomeScreen));
        final container = ProviderScope.containerOf(context);
        await container.read(pushKindsProvider.notifier).set(PushKind.team, true);
        await container.read(pushSyncProvider.future);
      });
      expect(devices.saved, hasLength(1));
      showSettingsSheet(tester.element(find.byType(HomeScreen)));
      await settle(tester);
      final signOut = find.text('Sign out');
      await tester.ensureVisible(signOut);
      await tester.tap(signOut);
      await settle(tester);
      expect(devices.saved, isEmpty);
      expect(accounts.current, isNull);
    });

    testWidgets('a push that arrives while the app is open is shown', (tester) async {
      await pump(tester, const HomeScreen());
      push.arrive(const PushNotice(title: 'Lions v Tigers', body: 'Wicket!'));
      await settle(tester);
      expect(device.shown.single.title, 'Lions v Tigers');
    });
  });
}
