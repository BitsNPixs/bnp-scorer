import 'package:bnp_scorer/app.dart';
import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/app_settings.dart';
import 'package:bnp_scorer/data/error_log.dart';
import 'package:bnp_scorer/screens/player_profile_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

// A made-up number: never put a real player's number in a test.
const _number = '+919876543210';
const _asha = Scorer(uid: 'u1', name: 'Asha Scorer');

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  late FakeAccounts accounts;
  late FakePlayerDirectory directory;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  /// The whole app at 360 dp, with the player directory.
  Future<void> pumpApp(WidgetTester tester, {bool withDirectory = true}) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(AppSettings(prefs)),
        errorLogProvider.overrideWithValue(ErrorLog(prefs)),
        accountsProvider.overrideWithValue(accounts),
        if (withDirectory) playerDirectoryProvider.overrideWithValue(directory),
        matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
        teamRepositoryProvider.overrideWithValue(InMemoryTeamRepository()),
        tournamentRepositoryProvider.overrideWithValue(InMemoryTournamentRepository()),
        scheduleRepositoryProvider.overrideWithValue(InMemoryScheduleRepository()),
      ],
      child: const BnpScorerApp(),
    ));
    await tester.pump(_settle);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
  }

  Future<void> tapTile(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await settle(tester);
  }

  Future<void> sendCode(WidgetTester tester, String number) async {
    await tester.enterText(find.byKey(const ValueKey('phone-number')), number);
    await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
    await settle(tester);
  }

  setUp(() {
    accounts = FakeAccounts(signedIn: _asha);
    directory = FakePlayerDirectory();
  });

  testWidgets('a scorer adds their number with the SMS code and gets a profile', (tester) async {
    await pumpApp(tester);
    await tapTile(tester, 'Add your mobile number');
    expect(find.text('Your mobile number'), findsOneWidget);
    expect(find.textContaining('It is never shown to anyone'), findsOneWidget);

    await sendCode(tester, '98765 43210');
    expect(accounts.codesSentTo, [_number]);
    expect(find.text('Sent by SMS to $_number.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('sms-code')), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await settle(tester);

    expect(accounts.current!.phone, _number);
    expect(find.text('Type the code'), findsNothing);
    expect(find.text('My profile'), findsOneWidget);
    expect(find.text('Verified · +91 •••• 3210'), findsOneWidget);
    expect(directory.players.values.single.ownerUid, 'u1');
    expect(directory.players.values.single.name, 'Asha Scorer');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a number a captain already added keeps that player', (tester) async {
    final invited = directory.seed('Asha R', _number);
    accounts = FakeAccounts(signedIn: const Scorer(uid: 'u1', name: 'Asha Scorer', phone: _number));
    await pumpApp(tester);
    expect(find.text('Verified · +91 •••• 3210'), findsOneWidget);
    expect(directory.players[invited.id]!.ownerUid, 'u1');

    await tapTile(tester, 'My profile');
    expect(find.byType(PlayerProfileScreen), findsOneWidget);
    expect(find.text('Asha R'), findsWidgets);
  });

  testWidgets('a wrong or short code is explained in the sheet', (tester) async {
    await pumpApp(tester);
    await tapTile(tester, 'Add your mobile number');
    await sendCode(tester, '9876543210');

    await tester.enterText(find.byKey(const ValueKey('sms-code')), '12');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await settle(tester);
    expect(find.text('Type the 6-digit code from the SMS.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('sms-code')), '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await settle(tester);
    expect(find.text('That code is not right. Check the SMS and try again.'), findsOneWidget);
    expect(accounts.current!.phone, isNull);

    await tester.tap(find.text('Send again'));
    await settle(tester);
    expect(accounts.codesSentTo, [_number, _number]);
  });

  testWidgets('a number that cannot be one is refused before any SMS', (tester) async {
    await pumpApp(tester);
    await tapTile(tester, 'Add your mobile number');
    await sendCode(tester, '12345');
    expect(find.text('Type a 10-digit mobile number, or one with its + code.'), findsOneWidget);
    expect(accounts.codesSentTo, isEmpty);
  });

  testWidgets('a failed send is explained, and Change number goes back', (tester) async {
    accounts.phoneFailWith = 'Too many tries. Wait a while before trying again.';
    await pumpApp(tester);
    await tapTile(tester, 'Add your mobile number');
    await sendCode(tester, '9876543210');
    expect(find.text('Too many tries. Wait a while before trying again.'), findsOneWidget);

    accounts.phoneFailWith = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
    await settle(tester);
    await tester.tap(find.text('Change number'));
    await settle(tester);
    expect(find.byKey(const ValueKey('phone-number')), findsOneWidget);
  });

  testWidgets('a phone that reads the SMS itself needs no code', (tester) async {
    accounts.autoVerify = true;
    await pumpApp(tester);
    await tapTile(tester, 'Add your mobile number');
    await sendCode(tester, '9876543210');
    expect(find.byKey(const ValueKey('sms-code')), findsNothing);
    expect(find.text('My profile'), findsOneWidget);
  });

  testWidgets('offline, the profile waits and can be tried again', (tester) async {
    directory.offline = true;
    accounts = FakeAccounts(signedIn: const Scorer(uid: 'u1', name: 'Asha Scorer', phone: _number));
    await pumpApp(tester);
    expect(find.text('Could not reach the cloud. Tap to try again.'), findsOneWidget);

    directory.offline = false;
    await tapTile(tester, 'My profile');
    expect(find.text('Verified · +91 •••• 3210'), findsOneWidget);
  });

  group('signed out', () {
    Future<void> agreeAndSend(WidgetTester tester) async {
      await tapTile(tester, 'Sign in with mobile number');
      expect(find.text('Publish your matches?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);
      expect(find.text('Sign in with your number'), findsOneWidget);
      await sendCode(tester, '98765 43210');
      await tester.enterText(find.byKey(const ValueKey('sms-code')), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await settle(tester);
    }

    testWidgets('a new number signs in, asks for a name once, and claims the profile', (tester) async {
      accounts = FakeAccounts();
      await pumpApp(tester);
      await agreeAndSend(tester);

      expect(find.text('Your name'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      expect(find.text('Type the name players know you by.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('scorer-name')), 'Ravi Kumar');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);

      expect(accounts.current!.name, 'Ravi Kumar');
      expect(accounts.current!.phone, _number);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('Verified · +91 •••• 3210'), findsOneWidget);
      expect(find.text('Link a Google account'), findsOneWidget);
      expect(directory.players.values.single.name, 'Ravi Kumar');
      expect(tester.takeException(), isNull);
    });

    testWidgets('closing the name step leaves an Add your name row that finishes it', (tester) async {
      accounts = FakeAccounts(signedIn: const Scorer(uid: 'p', name: unnamedScorer, phone: _number, hasGoogle: false));
      await pumpApp(tester);
      expect(find.text('My profile'), findsNothing);
      expect(directory.players, isEmpty, reason: 'no profile is made without a name');
      await tapTile(tester, 'Add your name');
      await tester.enterText(find.byKey(const ValueKey('scorer-name')), 'Ravi');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      expect(find.text('Verified · +91 •••• 3210'), findsOneWidget);
      expect(directory.players.values.single.name, 'Ravi');
    });

    testWidgets('a number already on an account signs in to it, with no name step', (tester) async {
      accounts = FakeAccounts()
        ..accountsByPhone[_number] = const Scorer(uid: 'u1', name: 'Asha Scorer', phone: _number);
      await pumpApp(tester);
      await agreeAndSend(tester);
      expect(find.byKey(const ValueKey('scorer-name')), findsNothing);
      expect(accounts.current!.uid, 'u1');
      expect(find.text('Signed in with your number.'), findsOneWidget);
      expect(find.text('Link a Google account'), findsNothing, reason: 'that account has Google already');
    });

    testWidgets('linking Google is offered to a number account, and failures are explained', (tester) async {
      accounts = FakeAccounts(signedIn: const Scorer(uid: 'p', name: 'Ravi', phone: _number, hasGoogle: false))
        ..linkGoogleFailsWith = 'That Google account already has its own BNP Scorer account.';
      await pumpApp(tester);
      await tapTile(tester, 'Link a Google account');
      expect(find.text('That Google account already has its own BNP Scorer account.'), findsOneWidget);

      accounts.linkGoogleFailsWith = null;
      await tapTile(tester, 'Link a Google account');
      expect(find.text('Google account linked.'), findsOneWidget);
      expect(find.text('Link a Google account'), findsNothing);
    });
  });

  testWidgets('without the player directory nothing about numbers shows', (tester) async {
    await pumpApp(tester, withDirectory: false);
    expect(find.text('Asha Scorer'), findsOneWidget);
    expect(find.text('Add your mobile number'), findsNothing);
    await accounts.signOut();
    await settle(tester);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Sign in with mobile number'), findsNothing);
  });
}
