import 'package:bnp_scorer/app.dart';
import 'package:bnp_scorer/data/app_settings.dart';
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  /// The whole app at 360 dp, as main() builds it.
  Future<void> pumpApp(WidgetTester tester, {Map<String, Object> stored = const {}}) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    matches = InMemoryMatchRepository();
    await matches.save(sampleRecord());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(AppSettings(prefs)),
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
