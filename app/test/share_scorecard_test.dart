import 'dart:typed_data';

import 'package:bnp_scorer/data/device_files.dart';
import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/screens/scoring_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/format.dart';
import 'package:bnp_scorer/widgets/share_scorecard_sheet.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

class _RecordingFiles implements DeviceFiles {
  Uint8List? image;
  String? caption;
  bool fail = false;

  @override
  Future<void> shareImage(Uint8List png, {required String caption}) async {
    if (fail) throw StateError('No apps to share with');
    image = png;
    this.caption = caption;
  }

  @override
  Future<void> shareTextFile(String name, String contents) async {}

  @override
  Future<void> shareText(String text, {required String subject}) async {}

  @override
  Future<String?> pickTextFile() async => null;
}

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  final matches = demoMatches(DateTime.utc(2026, 11, 6));
  final finished = matches.firstWhere((m) => m.id == 'demo-match-1');
  final live = matches.firstWhere((m) => m.id == 'demo-live');
  MatchState stateOf(String id) {
    final m = matches.firstWhere((r) => r.id == id);
    return ScoringEngine.replay(m.setup, m.events);
  }

  Future<_RecordingFiles> pump(WidgetTester tester, String matchId) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = InMemoryMatchRepository();
    await repo.save(matches.firstWhere((m) => m.id == matchId));
    final files = _RecordingFiles();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(repo),
        deviceFilesProvider.overrideWithValue(files),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: ScoringScreen(matchId: matchId)),
    ));
    await tester.pump(_settle);
    return files;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  testWidgets('the scorecard shares an image with a caption', (tester) async {
    final files = await pump(tester, finished.id);
    await tester.tap(find.byTooltip('Share'));
    await settle(tester);
    expect(find.text('Share scorecard'), findsOneWidget);
    expect(find.byType(ScorecardCard), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await tester.tap(find.text('Share'));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump(_settle);

    expect(files.image, isNotEmpty);
    expect(files.caption, shareText(stateOf(finished.id)));
  });

  testWidgets('a failed share explains itself and can be retried', (tester) async {
    final files = await pump(tester, finished.id);
    files.fail = true;
    await tester.tap(find.byTooltip('Share'));
    await settle(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('Share'));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump(_settle);

    expect(find.textContaining('Could not share'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });

  testWidgets('a match still in progress can be shared too', (tester) async {
    await pump(tester, live.id);
    await tester.tap(find.byTooltip('Share'));
    await settle(tester);
    expect(find.byType(ScorecardCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the caption reads like a message', () {
    final text = shareText(stateOf(finished.id));
    final lines = text.split('\n');
    expect(lines.first, finished.setup.venue);
    expect(text, contains('Team A'));
    expect(text, contains('won by'));
    expect(text, contains('Player of the Match:'));
    expect(lines.last, 'Scored with BNP Scorer');
  });

  test('highlights name the top scorer and the best bowler', () {
    final state = stateOf(finished.id);
    final line = inningsHighlights(state.setup, state.innings.first);
    expect(line, contains('('));
    expect(line, contains(' · '));
  });

  test('an innings with no balls has no highlights', () {
    final state = ScoringEngine.replay(finished.setup, const []);
    expect(inningsHighlights(state.setup, state.innings.first), isEmpty);
  });
}
