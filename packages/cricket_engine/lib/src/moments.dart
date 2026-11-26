/// The moments of a match worth telling its followers about, found by
/// comparing the state before and after one event. Pure: the app words them
/// and publishes them, and a Cloud Function sends them on.
library;

import 'state.dart';

enum MomentKind {
  /// The first ball of the match.
  started,
  wicket,

  /// A batter reached 50 (or 100: [hundred]).
  fifty,
  hundred,

  /// A bowler took a fifth wicket in the innings.
  fiveWickets,

  /// The first innings is over; the chase is next.
  inningsBreak,
  result,
}

class MatchMoment {
  const MatchMoment(this.kind, {this.playerId});

  final MomentKind kind;

  /// The batter out or on a milestone, or the bowler with five.
  final String? playerId;

  @override
  bool operator ==(Object other) => other is MatchMoment && other.kind == kind && other.playerId == playerId;

  @override
  int get hashCode => Object.hash(kind, playerId);

  @override
  String toString() => 'MatchMoment($kind, $playerId)';
}

int _balls(InningsState innings) =>
    innings.completedOvers.fold(innings.currentOver.length, (n, over) => n + over.length);

/// The moment [after] adds to [before], when it is one event further on, or
/// null for an ordinary ball, an undo or a correction. When one event makes
/// several (the last wicket ends the innings), the biggest is told: result,
/// innings break, five wickets, hundred, fifty, wicket, then the start.
MatchMoment? momentOf(MatchState before, MatchState after) {
  if (after.eventCount != before.eventCount + 1) return null;
  if (after.isCompleted && !before.isCompleted) return const MatchMoment(MomentKind.result);

  // The innings this event happened in: the last one before it, which an
  // innings-ending event leaves complete.
  final number = before.innings.length;
  final was = before.innings[number - 1];
  final now = after.innings[number - 1];

  if (now.isComplete && !was.isComplete && number == 1) return const MatchMoment(MomentKind.inningsBreak);

  for (final bowler in now.bowlers) {
    final had = was.bowlers.where((b) => b.playerId == bowler.playerId).firstOrNull?.wickets ?? 0;
    if (had < 5 && bowler.wickets >= 5) return MatchMoment(MomentKind.fiveWickets, playerId: bowler.playerId);
  }
  for (final (mark, kind) in [(100, MomentKind.hundred), (50, MomentKind.fifty)]) {
    for (final batter in now.batters) {
      final had = was.batters.where((b) => b.playerId == batter.playerId).firstOrNull?.runs ?? 0;
      if (had < mark && batter.runs >= mark) return MatchMoment(kind, playerId: batter.playerId);
    }
  }
  if (now.fallOfWickets.length > was.fallOfWickets.length) {
    return MatchMoment(MomentKind.wicket, playerId: now.fallOfWickets.last.batterId);
  }
  if (number == 1 && _balls(was) == 0 && _balls(now) > 0) return const MatchMoment(MomentKind.started);
  return null;
}
