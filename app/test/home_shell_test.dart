
import 'package:bnp_scorer/app.dart';
import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/app_info.dart';
import 'package:bnp_scorer/data/app_settings.dart';
import 'package:bnp_scorer/data/error_log.dart';
import 'package:bnp_scorer/screens/backup_screen.dart';
import 'package:bnp_scorer/screens/new_match_screen.dart';
import 'package:bnp_scorer/screens/stats_screen.dart';
import 'package:bnp_scorer/screens/teams_screen.dart';
import 'package:bnp_scorer/screens/tournaments_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/app_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  late SharedPreferences prefs;
  late InMemoryMatchRepository matches;
  late TextShares shares;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  /// The whole app at 360 dp, as main() builds it.
  Future<void> pumpApp(WidgetTester tester, {Map<String, Object> stored = const {}, Accounts? accounts}) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    matches = InMemoryMatchRepository();
    shares = TextShares();
    await matches.save(sampleRecord());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(AppSettings(prefs)),
        errorLogProvider.overrideWithValue(ErrorLog(prefs)),
        deviceFilesProvider.overrideWithValue(shares),
        if (accounts != null) accountsProvider.overrideWithValue(accounts),
        matchRepositoryProvider.overrideWithValue(matches),
        teamRepositoryProvider.overrideWithValue(InMemoryTeamRepository()),
        tournamentRepositoryProvider.overrideWithValue(InMemoryTournamentRepository()),
      ],
      child: const BnpScorerApp(),
    ));
    await tester.pump(_settle);
  }

  Brightness brightnessOnScreen(WidgetTester tester) =>
      Theme.of(tester.element(find.text('BNP SCORER'))).brightness;

  group('bottom bar', () {
    testWidgets('fits at 360 dp with four tabs and a round create button', (tester) async {
      await pumpApp(tester);

      final bar = tester.getSize(find.descendant(of: find.byType(AppBottomBar), matching: find.byType(Material)).first);
      expect(bar.width, 360 - 24, reason: 'a 12 dp gutter each side');
      expect(bar.height, AppBottomBar.barHeight);

      final create = find.byTooltip('New match');
      final createBox = tester.getSize(find.descendant(of: create, matching: find.byType(Container)).first);
      expect(createBox, const Size.square(AppBottomBar.createSize));
      expect(tester.getCenter(create).dx, closeTo(180, 0.5), reason: 'centred');
      expect(
        tester.getTopLeft(create).dy,
        lessThan(tester.getTopLeft(find.byTooltip('Stats')).dy),
        reason: 'raised above the bar',
      );

      for (final label in ['Matches', 'Tournaments', 'Stats', 'Teams']) {
        expect(find.byTooltip(label), findsOneWidget, reason: label);
      }

      // Labels keep the app font: a bare style once fell back to a serif face.
      final labelElement = tester.element(find.descendant(of: find.byType(AppBottomBar), matching: find.text('Stats')));
      final themeFont = Theme.of(labelElement).textTheme.labelSmall!.fontFamily;
      expect(themeFont, isNotNull);
      expect(DefaultTextStyle.of(labelElement).style.fontFamily, themeFont);
      expect(tester.takeException(), isNull);
    });

    testWidgets('each tab opens, and tabs are built only when first visited', (tester) async {
      await pumpApp(tester);
      expect(find.byType(StatsScreen, skipOffstage: false), findsNothing);

      await tester.tap(find.byTooltip('Tournaments'));
      await settle(tester);
      expect(find.byType(TournamentsScreen), findsOneWidget);
      expect(find.text('New tournament'), findsOneWidget);

      await tester.tap(find.byTooltip('Teams'));
      await settle(tester);
      expect(find.byType(TeamsScreen), findsOneWidget);
      expect(find.text('New team'), findsOneWidget);

      await tester.tap(find.byTooltip('Stats'));
      await settle(tester);
      expect(find.byType(StatsScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Matches'));
      await settle(tester);
      expect(find.text('Ammapet Kings'), findsOneWidget);
      expect(find.byType(StatsScreen), findsNothing, reason: 'off screen now');
      expect(find.byType(StatsScreen, skipOffstage: false), findsOneWidget, reason: 'kept, not rebuilt');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the selected tab is marked for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester);
      SemanticsNode tab(String label) =>
          tester.getSemantics(find.descendant(of: find.byTooltip(label), matching: find.byType(InkResponse)));
      await tester.tap(find.byTooltip('Stats'));
      await settle(tester);
      expect(tab('Stats'), isSemantics(isSelected: true, isButton: true));
      expect(tab('Matches'), isSemantics(isSelected: false));
      semantics.dispose();
    });

    testWidgets('back on another tab returns to Matches instead of leaving', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Teams'));
      await settle(tester);

      final handled = await tester.binding.handlePopRoute();
      await settle(tester);
      expect(handled, isTrue, reason: 'the app stays open');
      expect(find.text('Ammapet Kings'), findsOneWidget);
      expect(find.text('New team'), findsNothing);
    });

    testWidgets('+ opens a new match from any tab and comes back to Matches', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Stats'));
      await settle(tester);

      await tester.tap(find.byTooltip('New match'));
      await settle(tester);
      expect(find.byType(NewMatchScreen), findsOneWidget);

      await tester.pageBack();
      await settle(tester);
      expect(find.byType(NewMatchScreen), findsNothing);
      expect(find.text('Ammapet Kings'), findsOneWidget, reason: 'back on Matches');
    });

    testWidgets("the hero's New match button opens setup too", (tester) async {
      await pumpApp(tester);
      await tester.tap(find.widgetWithText(InkWell, 'New match'));
      await settle(tester);
      expect(find.byType(NewMatchScreen), findsOneWidget);
    });
  });

  group('theme', () {
    testWidgets('follows the phone until the scorer chooses', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(tester);
      expect(brightnessOnScreen(tester), Brightness.dark);
    });

    testWidgets('Settings switches to dark and light at once, and remembers', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester);
      expect(brightnessOnScreen(tester), Brightness.light);

      await tester.tap(find.byTooltip('Settings'));
      await settle(tester);
      expect(find.text('Appearance'.toUpperCase()), findsOneWidget);

      await tester.tap(find.text('Dark'));
      await settle(tester);
      expect(brightnessOnScreen(tester), Brightness.dark);
      expect(prefs.getString(AppSettings.themeModeKey), 'dark');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Dark')),
        isSemantics(isSelected: true),
      );

      await tester.tap(find.text('Light'));
      await settle(tester);
      expect(brightnessOnScreen(tester), Brightness.light);
      expect(prefs.getString(AppSettings.themeModeKey), 'light');
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('a saved choice is used at launch', (tester) async {
      await pumpApp(tester, stored: {AppSettings.themeModeKey: 'dark'});
      expect(brightnessOnScreen(tester), Brightness.dark);
    });

    testWidgets('the three choices share the width at 360 dp', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Settings'));
      await settle(tester);

      final widths = [
        for (final label in ['System', 'Light', 'Dark'])
          tester.getSize(find.ancestor(of: find.text(label), matching: find.byType(AnimatedContainer)).first).width,
      ];
      expect(widths.toSet(), hasLength(1), reason: 'equal widths: $widths');
      expect(widths.first, greaterThan(80));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Settings leads to Backup', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Settings'));
      await settle(tester);
      await tester.tap(find.text('Backup and restore'));
      await settle(tester);
      expect(find.byType(BackupScreen), findsOneWidget);
    });
  });

  testWidgets('Settings lists the open-source licences', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await tester.ensureVisible(find.text('Open-source licences'));
    await tester.tap(find.text('Open-source licences'));
    await settle(tester);
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('BNP Scorer'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('Settings › About', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await settle(tester);
    }

    testWidgets('shows the version and the privacy promise without another tap', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);

      final version = find.text('Version $appVersionLabel · By Bits N Pixs');
      await tester.ensureVisible(version);
      expect(version, findsOneWidget);
      final privacy = find.textContaining('Your matches stay on this phone');
      expect(privacy, findsOneWidget);
      final rect = tester.getRect(privacy);
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.height, greaterThan(40), reason: 'the promise wraps rather than clipping');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Report a problem shares the version and recent errors', (tester) async {
      await pumpApp(tester);
      ErrorLog(prefs).record(StateError('scorecard failed'), StackTrace.fromString('#0 build'));
      await openSettings(tester);

      await tester.ensureVisible(find.text('Report a problem'));
      await tester.tap(find.text('Report a problem'));
      await settle(tester);

      expect(shares.subject, 'BNP Scorer problem report');
      expect(shares.text, contains('Version $appVersionLabel on '));
      expect(shares.text, contains('Bad state: scorecard failed\n#0 build'));
      expect(find.text('Appearance'.toUpperCase()), findsNothing, reason: 'the sheet closes');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a report with no errors still goes, and a failed share is explained', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      await tester.ensureVisible(find.text('Report a problem'));
      await tester.tap(find.text('Report a problem'));
      await settle(tester);
      expect(shares.text, contains('No errors were recorded on this phone.'));

      shares.fail = true;
      await openSettings(tester);
      await tester.ensureVisible(find.text('Report a problem'));
      await tester.tap(find.text('Report a problem'));
      await settle(tester);
      expect(find.textContaining('Could not open sharing'), findsOneWidget);
    });
  });

  group('Settings › Account', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await settle(tester);
    }

    Future<void> tapSignIn(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Sign in with Google'));
      await tester.tap(find.text('Sign in with Google'));
      await settle(tester);
    }

    testWidgets('a cloud build says when matches become public, with a link to the policy', (tester) async {
      await pumpApp(tester, accounts: FakeAccounts());
      await openSettings(tester);
      final promise = find.textContaining('unless you sign in');
      await tester.ensureVisible(promise);
      expect(promise, findsOneWidget);
      expect(find.textContaining('No account, no internet'), findsNothing);
      expect(find.textContaining('bitsnpixs.github.io/bnp-scorer/privacy.html'), findsOneWidget);
      expect(tester.getRect(promise).right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a build without the cloud offers no sign-in', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      expect(find.text('ACCOUNT'), findsNothing);
      expect(find.text('Sign in with Google'), findsNothing);
    });

    testWidgets('signing in first says matches become public, then shows the scorer', (tester) async {
      final accounts = FakeAccounts();
      await pumpApp(tester, accounts: accounts);
      await openSettings(tester);
      await tapSignIn(tester);

      expect(find.text('Publish your matches?'), findsOneWidget);
      expect(find.textContaining('including the player names'), findsOneWidget);
      expect(find.textContaining('Your email and who has paid entry fees are never shared'), findsOneWidget);
      expect(find.textContaining('tournament and scheduled match'), findsOneWidget);
      expect(accounts.signInCalls, 0, reason: 'nothing happens before the scorer agrees');

      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);
      expect(accounts.signInCalls, 1);
      expect(find.text('Signed in as Asha Scorer'), findsOneWidget);
      expect(find.text('Asha Scorer'), findsOneWidget);
      expect(find.text('New matches and tournaments you create are public'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Not now" and a cancelled Google sign-in leave the scorer signed out', (tester) async {
      final accounts = FakeAccounts()..nextSignIn = null;
      await pumpApp(tester, accounts: accounts);
      await openSettings(tester);

      await tapSignIn(tester);
      await tester.tap(find.text('Not now'));
      await settle(tester);
      expect(accounts.signInCalls, 0);

      await tapSignIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);
      expect(accounts.signInCalls, 1);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.textContaining('Signed in as'), findsNothing);
    });

    testWidgets('a failed sign-in is explained', (tester) async {
      final accounts = FakeAccounts()..failWith = 'Could not sign in with Google (network).';
      await pumpApp(tester, accounts: accounts);
      await openSettings(tester);
      await tapSignIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);
      expect(find.text('Could not sign in with Google (network).'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
    });

    testWidgets('signing out goes back to private matches', (tester) async {
      final accounts = FakeAccounts(signedIn: const Scorer(uid: 'u1', name: 'Asha Scorer'));
      await pumpApp(tester, accounts: accounts);
      await openSettings(tester);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      expect(accounts.current, isNull);
      expect(find.text('Signed out. New matches stay on this phone.'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
    });
  });

  group('AppSettings', () {
    test('defaults to the system theme', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(await SharedPreferences.getInstance());
      expect(settings.themeMode, ThemeMode.system);
    });

    test('stores the mode by name and reads it back', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = AppSettings(prefs);
      for (final mode in ThemeMode.values) {
        await settings.setThemeMode(mode);
        expect(prefs.getString(AppSettings.themeModeKey), mode.name);
        expect(AppSettings(prefs).themeMode, mode);
      }
    });

    test('an unknown stored value falls back to the system theme', () async {
      SharedPreferences.setMockInitialValues({AppSettings.themeModeKey: 'neon'});
      final settings = AppSettings(await SharedPreferences.getInstance());
      expect(settings.themeMode, ThemeMode.system);
    });
  });
}
