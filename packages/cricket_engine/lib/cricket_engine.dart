/// Event-sourced cricket scoring.
///
/// A match is a [MatchSetup] plus an ordered list of [MatchEvent]s.
/// [ScoringEngine.replay] folds the events into an immutable [MatchState].
/// Undo is simply replaying without the last event.
library;

export 'src/engine.dart';
export 'src/events.dart';
export 'src/models.dart';
export 'src/state.dart';
export 'src/stats.dart';
