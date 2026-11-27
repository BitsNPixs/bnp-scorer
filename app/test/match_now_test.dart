import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/summary_tiles.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:match_view/match_view.dart';

import 'fakes.dart';

final _at = DateTime.utc(2026, 11, 5);

/// A match on this phone, last saved [savedAgo] ago: one ball bowled, or
/// abandoned when [finished].
MatchSummary _summary(String id, Duration savedAgo, {bool finished = false}) {
  final record = sampleRecord(
    id: id,
    updatedAt: DateTime.now().subtract(savedAgo),
    events: [
      OpenersSelected(id: 'o', at: _at, strikerId: 'a1', nonStrikerId: 'a2'),
      BowlerChanged(id: 'b', at: _at, bowlerId: 'b1'),
      BallBowled(id: 'r', at: _at, runsOffBat: 1),
      if (finished) MatchAbandoned(id: 'x', at: _at, reason: 'Rain'),
    ],
  );
  return (record: record, state: ScoringEngine.replay(record.setup, record.events));
}

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  test('a match on this phone follows the six-hour rule by when it was last saved', () {
    final now = DateTime.now();
    expect(nowOf(_summary('a', const Duration(minutes: 10)), now), MatchNow.live);
    expect(nowOf(_summary('b', const Duration(hours: 7)), now), MatchNow.stopped);
    expect(nowOf(_summary('c', const Duration(days: 9), finished: true), now), MatchNow.finished);
    final saved = _summary('d', Duration.zero);
    expect(nowOf(saved, saved.record.updatedAt.add(stoppedAfter)), MatchNow.stopped, reason: 'to the minute');
  });

  testWidgets('the Live tile counts only matches being played now', (tester) async {
    final matches = [
      _summary('a', const Duration(minutes: 10)),
      _summary('b', const Duration(hours: 7)),
      _summary('c', const Duration(days: 2)),
      _summary('d', const Duration(days: 9), finished: true),
    ];
    Future<void> pumpAt(DateTime Function() clock) async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [clockProvider.overrideWithValue(clock)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: SummaryTiles(tournamentCount: 0, matches: matches)),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
    }

    await pumpAt(DateTime.now);
    String valueAbove(String label) {
      final tile = find.ancestor(of: find.text(label), matching: find.byType(Column)).first;
      return tester.widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text))).first.data!;
    }

    expect(valueAbove('Live'), '1', reason: 'two were left unfinished long ago');
    expect(valueAbove('Played'), '1');

    // The same matches, seen on the day the oldest unfinished one was saved.
    await pumpAt(() => DateTime.now().subtract(const Duration(days: 2)));
    expect(valueAbove('Live'), '3', reason: 'the clock decides, not the match');
    expect(tester.takeException(), isNull);
  });
}
