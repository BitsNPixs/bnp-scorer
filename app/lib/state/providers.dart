import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/match_record.dart';
import '../data/match_repository.dart';
import '../data/team_repository.dart';

/// Overridden in `main()` with the real implementation.
final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => throw UnimplementedError('matchRepositoryProvider must be overridden'),
);

/// Overridden in `main()` with the real implementation.
final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => throw UnimplementedError('teamRepositoryProvider must be overridden'),
);

final savedTeamsProvider = FutureProvider.autoDispose<List<Team>>(
  (ref) => ref.watch(teamRepositoryProvider).loadAll(),
);

/// A stored match with its replayed state, for lists.
typedef MatchSummary = ({MatchRecord record, MatchState state});

/// Career numbers from every finished match. Derived, never stored.
final statsProvider = FutureProvider.autoDispose<StatsBook>((ref) async {
  final matches = await ref.watch(matchListProvider.future);
  final oldestFirst = [...matches]
    ..sort((a, b) => a.record.createdAt.compareTo(b.record.createdAt));
  return computeStats(oldestFirst.map((m) => m.state));
});

final matchListProvider = FutureProvider.autoDispose<List<MatchSummary>>((ref) async {
  final records = await ref.watch(matchRepositoryProvider).loadAll();
  final summaries = <MatchSummary>[];
  for (final record in records) {
    try {
      summaries.add((
        record: record,
        state: ScoringEngine.replay(record.setup, record.events),
      ));
    } on ScoringException catch (e) {
      debugPrint('Skipping match ${record.id} with an invalid log: $e');
    }
  }
  return summaries;
});
