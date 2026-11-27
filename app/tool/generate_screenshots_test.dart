// Renders real screens of the app, filled with the demo data and drawn in the
// bundled fonts, and writes them as PNGs to build/screenshots/ (gitignored),
// for the website and, later, the Play Store listing. Not part of the test
// suite (it lives outside test/). Regenerate after a visible change with:
//
//   cd app && flutter test tool/generate_screenshots_test.dart
//   python tool/build_site_assets.py
//
// The second step makes the small WebP copies, web fonts and link preview the
// website uses (site/img/, site/fonts/).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bnp_scorer/app.dart';
import 'package:bnp_scorer/data/app_settings.dart';
import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/data/error_log.dart';
import 'package:bnp_scorer/screens/scoring_screen.dart';
import 'package:bnp_scorer/screens/tournament_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/fakes.dart';

const _out = 'build/screenshots';

/// A common phone: 390 x 844 dp, saved at 2x.
const _size = Size(390, 844);
const _pixelRatio = 2.0;

final _now = DateTime(2026, 11, 16, 17);
final _key = GlobalKey();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryMatchRepository matches;
  late InMemoryTeamRepository teams;
  late InMemoryTournamentRepository tournaments;
  late SharedPreferences prefs;

  setUpAll(() async {
    AppFonts.useGoogleFonts = true;
    AppFonts.useBundledFonts();
    // flutter_test draws icons as boxes unless the real icon font is loaded.
    final root = Platform.environment['FLUTTER_ROOT']!;
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(
          File('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf').readAsBytesSync())));
    await icons.load();
    Directory(_out).createSync(recursive: true);
  });

  setUp(() async {
    // A test runner script, like the files in test/, so the test-only helper is
    // the right tool here.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({AppSettings.themeModeKey: 'dark'});
    prefs = await SharedPreferences.getInstance();
    matches = InMemoryMatchRepository();
    teams = InMemoryTeamRepository();
    tournaments = InMemoryTournamentRepository();
    await seedDemoMatches(matches, now: _now);
    await seedDemoTeams(teams);
    await seedDemoTournaments(tournaments, now: _now);
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view
      ..physicalSize = _size * _pixelRatio
      ..devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);
    final overrides = [
      appSettingsProvider.overrideWithValue(AppSettings(prefs)),
      errorLogProvider.overrideWithValue(ErrorLog(prefs)),
      matchRepositoryProvider.overrideWithValue(matches),
      teamRepositoryProvider.overrideWithValue(teams),
      tournamentRepositoryProvider.overrideWithValue(tournaments),
      scheduleRepositoryProvider.overrideWithValue(InMemoryScheduleRepository()),
      // The demo's match in progress is live on the day the demo is set on.
      clockProvider.overrideWithValue(() => _now),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: RepaintBoundary(
        key: _key,
        child: home is BnpScorerApp
            ? home
            : MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.dark(), home: home),
      ),
    ));
    await settle(tester);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
    await tester.runAsync(() async {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _pixelRatio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    final tab = find.descendant(of: find.byType(TabBar), matching: find.text(label)).first;
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await settle(tester);
  }

  testWidgets('home', (tester) async {
    await pump(tester, const BnpScorerApp());
    await shoot(tester, 'home');
  });

  testWidgets('saved teams', (tester) async {
    await pump(tester, const BnpScorerApp());
    await tester.tap(find.text('Teams').last);
    await settle(tester);
    await tester.tap(find.text('Team A'));
    await settle(tester);
    await shoot(tester, 'team');
  });

  testWidgets('live scoring', (tester) async {
    await pump(tester, const ScoringScreen(matchId: 'demo-live'));
    await shoot(tester, 'scoring');
  });

  testWidgets('result, scorecard and charts of the cup final', (tester) async {
    final finalId = (await matches.loadAll()).firstWhere((m) => m.id == 'demo-match-5').id;
    await pump(tester, ScoringScreen(matchId: finalId));
    await shoot(tester, 'result');
    final firstInnings = find.descendant(of: find.byType(TabBar), matching: find.byType(Tab)).at(1);
    await tester.tap(firstInnings);
    await settle(tester);
    await shoot(tester, 'scorecard');
    await tapTab(tester, 'Charts');
    await shoot(tester, 'charts');
  });

  testWidgets('tournament table', (tester) async {
    final cup = (await tournaments.loadAll()).firstWhere((t) => t.name == 'BNP Cup');
    await pump(tester, TournamentScreen(tournamentId: cup.id));
    await tapTab(tester, 'Table');
    await shoot(tester, 'table');
  });
}

/// Lets entrance animations finish and real-time work (fonts, images) land.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump(const Duration(milliseconds: 400));
}
