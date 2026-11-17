import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accounts.dart';
import '../data/app_settings.dart';
import '../data/cloud_matches.dart';
import '../data/device_files.dart';
import '../data/error_log.dart';
import '../data/match_record.dart';
import '../data/match_repository.dart';
import '../data/team_repository.dart';
import '../data/tournament_repository.dart';

/// Overridden in `main()` with the real implementation.
final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => throw UnimplementedError('matchRepositoryProvider must be overridden'),
);

/// Overridden in `main()` with the real implementation.
final appSettingsProvider = Provider<AppSettings>(
  (ref) => throw UnimplementedError('appSettingsProvider must be overridden'),
);

/// System, light or dark, as the scorer chose in Settings.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(appSettingsProvider).themeMode;

  /// Switches at once and saves in the background. A failed save only means
  /// the choice is forgotten at the next launch.
  Future<void> select(ThemeMode mode) async {
    state = mode;
    try {
      await ref.read(appSettingsProvider).setThemeMode(mode);
    } on Object catch (e) {
      debugPrint('Could not save the theme: $e');
    }
  }
}

/// Google sign-in. `main()` overrides it when the cloud is set up; tests and
/// builds without `google-services.json` get no sign-in.
final accountsProvider = Provider<Accounts>((ref) => const LocalOnlyAccounts());

/// The signed-in scorer, or null.
final scorerProvider = StreamProvider<Scorer?>((ref) {
  final accounts = ref.watch(accountsProvider);
  return accounts.changes;
});

/// Published matches. `main()` overrides it when the cloud is set up; null in
/// tests and builds without `google-services.json`.
final cloudMatchesProvider = Provider<CloudMatches?>((ref) => null);

/// A published match and its state, for the "Everyone" list.
typedef PublishedSummary = ({PublishedMatch match, MatchState state});

/// The latest published matches, live. Empty without the cloud. A match whose
/// log does not replay is left out, like a broken match on the phone.
///
/// No automatic retry: Firestore reconnects by itself, and its errors (such
/// as a refused read) do not mend on their own, while each retry costs reads.
final publicMatchesProvider = StreamProvider.autoDispose<List<PublishedSummary>>(
  (ref) {
    final cloud = ref.watch(cloudMatchesProvider);
    if (cloud == null) return Stream.value(const []);
    return cloud.recent().map((matches) => [
          for (final match in matches) ?_summaryOf(match),
        ]);
  },
  retry: _noRetry,
);

Duration? _noRetry(int retryCount, Object error) => null;

PublishedSummary? _summaryOf(PublishedMatch match) {
  try {
    return (match: match, state: ScoringEngine.replay(match.record.setup, match.record.events));
  } on Object catch (e) {
    debugPrint('Leaving out published match ${match.record.id}: $e');
    return null;
  }
}

/// One published match as it is scored. Null once it is unpublished. A match
/// this app cannot read stays an error: retrying would not help.
final publishedMatchProvider = StreamProvider.autoDispose.family<PublishedMatch?, String>(
  (ref, matchId) {
    final cloud = ref.watch(cloudMatchesProvider);
    if (cloud == null) return Stream.value(null);
    return cloud.watch(matchId);
  },
  retry: _noRetry,
);

/// Overridden in `main()` with the log the error handlers write to.
final errorLogProvider = Provider<ErrorLog>(
  (ref) => throw UnimplementedError('errorLogProvider must be overridden'),
);

/// The share sheet and file picker. Tests override this.
final deviceFilesProvider = Provider<DeviceFiles>((ref) => const PlatformDeviceFiles());

/// Overridden in `main()` with the real implementation.
final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => throw UnimplementedError('teamRepositoryProvider must be overridden'),
);

final savedTeamsProvider = FutureProvider.autoDispose<List<Team>>(
  (ref) => ref.watch(teamRepositoryProvider).loadAll(),
);

/// Overridden in `main()` with the real implementation.
final tournamentRepositoryProvider = Provider<TournamentRepository>(
  (ref) => throw UnimplementedError('tournamentRepositoryProvider must be overridden'),
);

/// Every tournament with its derived table, stats and champion.
final tournamentsProvider = FutureProvider.autoDispose<List<TournamentProgress>>((ref) async {
  final tournaments = await ref.watch(tournamentRepositoryProvider).loadAll();
  final matches = await ref.watch(matchListProvider.future);
  final byId = {for (final m in matches) m.record.id: m.state};
  return [for (final t in tournaments) progressOf(t, byId)];
});

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
