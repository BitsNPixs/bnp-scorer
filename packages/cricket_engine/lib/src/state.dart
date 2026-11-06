/// Immutable snapshots produced by the engine. Never edit these directly;
/// record an event and replay instead.
library;

import 'models.dart';

enum MatchPhase {
  /// Choose striker and non-striker (start of either innings).
  awaitingOpeners,

  /// Choose the bowler for the next over.
  awaitingBowler,

  /// A crease slot is empty after a wicket or retirement.
  awaitingBatter,

  /// Ready for the next delivery.
  inPlay,

  /// First innings done; waiting for the second innings openers.
  inningsBreak,

  completed,
}

class Dismissal {
  const Dismissal({required this.type, this.bowlerId, this.fielderId});

  final DismissalType type;

  /// Set only when the bowler is credited with the wicket.
  final String? bowlerId;
  final String? fielderId;
}

class BatterScore {
  const BatterScore({
    required this.playerId,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    this.dismissal,
  });

  final String playerId;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;

  /// Null while not out. Retired hurt is a dismissal record but not out.
  final Dismissal? dismissal;

  bool get isOut => dismissal != null && dismissal!.type.countsAsWicket;
  bool get isRetiredHurt => dismissal?.type == DismissalType.retiredHurt;
  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
}

class BowlerFigures {
  const BowlerFigures({
    required this.playerId,
    required this.legalBalls,
    required this.runs,
    required this.wickets,
    required this.maidens,
    required this.wides,
    required this.noBalls,
    required this.dots,
  });

  final String playerId;
  final int legalBalls;
  final int runs;
  final int wickets;
  final int maidens;
  final int wides;
  final int noBalls;
  final int dots;

  String overs(int ballsPerOver) =>
      formatOvers(legalBalls, ballsPerOver);

  double economy(int ballsPerOver) =>
      legalBalls == 0 ? 0 : runs * ballsPerOver / legalBalls;
}

enum BallKind { dot, runs, four, six, extra, wicket }

/// Compact description of a delivery for the "this over" strip.
class BallSummary {
  const BallSummary({required this.label, required this.kind, required this.isLegal});

  final String label;
  final BallKind kind;
  final bool isLegal;
}

class FallOfWicket {
  const FallOfWicket({
    required this.wicketNumber,
    required this.runs,
    required this.batterId,
    required this.legalBalls,
  });

  final int wicketNumber;
  final int runs;
  final String batterId;
  final int legalBalls;
}

class Extras {
  const Extras({this.wides = 0, this.noBalls = 0, this.byes = 0, this.legByes = 0});

  final int wides;
  final int noBalls;
  final int byes;
  final int legByes;

  int get total => wides + noBalls + byes + legByes;
}

class InningsState {
  const InningsState({
    required this.number,
    required this.battingTeamId,
    required this.bowlingTeamId,
    required this.ballsPerOver,
    required this.maxBalls,
    required this.runs,
    required this.wickets,
    required this.legalBalls,
    required this.extras,
    required this.batters,
    required this.bowlers,
    required this.strikerId,
    required this.nonStrikerId,
    required this.bowlerId,
    required this.lastOverBowlerId,
    required this.completedOvers,
    required this.currentOver,
    required this.fallOfWickets,
    required this.partnershipRuns,
    required this.partnershipBalls,
    required this.isFreeHit,
    required this.target,
    required this.isComplete,
    required this.closeReason,
    required this.availableBatterIds,
    required this.eligibleBowlerIds,
  });

  /// 1 or 2.
  final int number;
  final String battingTeamId;
  final String bowlingTeamId;
  final int ballsPerOver;
  final int maxBalls;
  final int runs;
  final int wickets;
  final int legalBalls;
  final Extras extras;

  /// In batting order.
  final List<BatterScore> batters;

  /// In order of first appearance.
  final List<BowlerFigures> bowlers;
  final String? strikerId;
  final String? nonStrikerId;

  /// Null between overs.
  final String? bowlerId;

  /// Bowler of the most recently completed over (cannot bowl the next one).
  final String? lastOverBowlerId;
  final List<List<BallSummary>> completedOvers;
  final List<BallSummary> currentOver;
  final List<FallOfWicket> fallOfWickets;
  final int partnershipRuns;
  final int partnershipBalls;
  final bool isFreeHit;

  /// Runs needed to win (second innings only).
  final int? target;
  final bool isComplete;
  final String? closeReason;

  /// Batting-side players who can walk in now (includes retired hurt).
  final List<String> availableBatterIds;

  /// Bowling-side players allowed to bowl right now.
  final List<String> eligibleBowlerIds;

  String get oversText => formatOvers(legalBalls, ballsPerOver);
  String get maxOversText => formatOvers(maxBalls, ballsPerOver);
  int get ballsRemaining => maxBalls - legalBalls;
  double get runRate => legalBalls == 0 ? 0 : runs * ballsPerOver / legalBalls;

  int? get runsNeeded {
    final t = target;
    if (t == null) return null;
    final need = t - runs;
    return need < 0 ? 0 : need;
  }

  double? get requiredRunRate {
    final need = runsNeeded;
    if (need == null) return null;
    if (ballsRemaining <= 0) return null;
    return need * ballsPerOver / ballsRemaining;
  }

  BatterScore? batter(String? playerId) {
    if (playerId == null) return null;
    for (final b in batters) {
      if (b.playerId == playerId) return b;
    }
    return null;
  }

  BowlerFigures? bowler(String? playerId) {
    if (playerId == null) return null;
    for (final b in bowlers) {
      if (b.playerId == playerId) return b;
    }
    return null;
  }
}

enum ResultKind { runs, wickets, tie, noResult }

class MatchResult {
  const MatchResult({
    required this.kind,
    this.winnerTeamId,
    this.margin = 0,
    this.ballsRemaining,
  });

  final ResultKind kind;

  /// Null for a tie or no result.
  final String? winnerTeamId;
  final int margin;

  /// Set for chases won (balls to spare).
  final int? ballsRemaining;
}

class MatchState {
  const MatchState({
    required this.setup,
    required this.phase,
    required this.innings,
    required this.result,
    required this.eventCount,
  });

  final MatchSetup setup;
  final MatchPhase phase;

  /// Started innings, in order. Never empty.
  final List<InningsState> innings;
  final MatchResult? result;
  final int eventCount;

  InningsState get current => innings.last;
  bool get isCompleted => phase == MatchPhase.completed;
}

/// "12.3" style overs from a ball count.
String formatOvers(int legalBalls, int ballsPerOver) {
  final overs = legalBalls ~/ ballsPerOver;
  final balls = legalBalls % ballsPerOver;
  return balls == 0 ? '$overs' : '$overs.$balls';
}
