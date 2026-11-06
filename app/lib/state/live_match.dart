import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ids.dart';
import '../data/match_record.dart';
import 'providers.dart';

class LiveMatch {
  const LiveMatch({required this.record, required this.state, this.saveFailed = false});

  final MatchRecord record;
  final MatchState state;

  /// The latest record could not be written to storage. Every save writes
  /// the whole log, so the next successful save recovers it.
  final bool saveFailed;

  MatchSetup get setup => record.setup;
  bool get canUndo => record.events.isNotEmpty;
}

final liveMatchProvider =
    AsyncNotifierProvider.autoDispose.family<LiveMatchNotifier, LiveMatch, String>(
  LiveMatchNotifier.new,
);

/// Records scoring actions for one match. Every action returns `null` on
/// success or a scorer-friendly error message.
class LiveMatchNotifier extends AsyncNotifier<LiveMatch> {
  LiveMatchNotifier(this.matchId);

  final String matchId;

  @override
  Future<LiveMatch> build() async {
    final record = await ref.read(matchRepositoryProvider).load(matchId);
    if (record == null) throw StateError('Match $matchId was not found.');
    return LiveMatch(
      record: record,
      state: ScoringEngine.replay(record.setup, record.events),
    );
  }

  String? openers(String strikerId, String nonStrikerId) => _add(OpenersSelected(
        id: newId(),
        at: DateTime.now(),
        strikerId: strikerId,
        nonStrikerId: nonStrikerId,
      ));

  String? bowler(String bowlerId) =>
      _add(BowlerChanged(id: newId(), at: DateTime.now(), bowlerId: bowlerId));

  String? ball({
    int runsOffBat = 0,
    ExtraType extra = ExtraType.none,
    int extraRuns = 0,
    bool boundary = false,
    Wicket? wicket,
  }) =>
      _add(BallBowled(
        id: newId(),
        at: DateTime.now(),
        runsOffBat: runsOffBat,
        extra: extra,
        extraRuns: extraRuns,
        boundary: boundary,
        wicket: wicket,
      ));

  String? newBatter(String batterId) =>
      _add(NewBatter(id: newId(), at: DateTime.now(), batterId: batterId));

  String? retire(String batterId, {required bool hurt}) => _add(BatterRetired(
        id: newId(),
        at: DateTime.now(),
        batterId: batterId,
        hurt: hurt,
      ));

  String? swapStrike() => _add(StrikeSwapped(id: newId(), at: DateTime.now()));

  String? closeInnings(String reason) =>
      _add(InningsClosed(id: newId(), at: DateTime.now(), reason: reason));

  /// Removes the last event. Returns false when there is nothing to undo.
  bool undo() {
    final current = state.value;
    if (current == null || !current.canUndo) return false;
    final events = current.record.events.sublist(0, current.record.events.length - 1);
    _commit(current.record.withEvents(events));
    return true;
  }

  String? _add(MatchEvent event) {
    final current = state.value;
    if (current == null) return 'The match is still loading.';
    final MatchState next;
    try {
      // Validate first: an illegal event never reaches the log.
      next = ScoringEngine.apply(current.setup, current.record.events, event);
    } on ScoringException catch (e) {
      return e.message;
    }
    _commit(current.record.withEvents([...current.record.events, event]), next);
    return null;
  }

  void _commit(MatchRecord record, [MatchState? replayed]) {
    state = AsyncData(LiveMatch(
      record: record,
      state: replayed ?? ScoringEngine.replay(record.setup, record.events),
    ));
    _persist(record);
  }

  Future<void> _persist(MatchRecord record) async {
    final repository = ref.read(matchRepositoryProvider);
    var failed = false;
    try {
      await repository.save(record);
    } catch (error) {
      failed = true;
      debugPrint('Saving match ${record.id} failed: $error');
    }
    if (!ref.mounted) return;
    final current = state.value;
    // Only flag the record on screen; a stale save of an older record is
    // superseded by the newer one.
    if (current != null && identical(current.record, record) && current.saveFailed != failed) {
      state = AsyncData(LiveMatch(record: record, state: current.state, saveFailed: failed));
    }
    if (!failed) ref.invalidate(matchListProvider);
  }
}
