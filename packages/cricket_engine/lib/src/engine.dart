/// Folds an event log into [MatchState], enforcing the laws (and the
/// configured house rules) as it goes.
library;

import 'events.dart';
import 'models.dart';
import 'state.dart';

/// Thrown when an event is not legal in the current match state. The
/// [message] is written for scorers and is safe to show in the UI.
class ScoringException implements Exception {
  const ScoringException(this.message);

  final String message;

  @override
  String toString() => 'ScoringException: $message';
}

abstract final class ScoringEngine {
  /// Rebuilds the match from scratch. Cheap: a full T20 is ~300 events.
  static MatchState replay(MatchSetup setup, List<MatchEvent> events) {
    final match = _MatchBuilder(setup);
    for (final event in events) {
      match.apply(event);
    }
    return match.snapshot(events.length);
  }

  /// Validates [next] against [events]; throws [ScoringException] if illegal.
  static MatchState apply(
    MatchSetup setup,
    List<MatchEvent> events,
    MatchEvent next,
  ) =>
      replay(setup, [...events, next]);
}

class _MatchBuilder {
  _MatchBuilder(this.setup) {
    final batting = setup.teamById(setup.firstBattingTeamId);
    innings.add(_InningsBuilder(
      number: 1,
      battingTeam: batting,
      bowlingTeam: setup.opponentOf(batting.id),
      rules: setup.rules,
    ));
  }

  final MatchSetup setup;
  final innings = <_InningsBuilder>[];
  MatchResult? result;

  _InningsBuilder get current => innings.last;

  MatchPhase get phase {
    if (result != null) return MatchPhase.completed;
    final c = current;
    if (c.complete) {
      return innings.length == 1 ? MatchPhase.inningsBreak : MatchPhase.completed;
    }
    return c.phase;
  }

  void apply(MatchEvent event) {
    final p = phase;
    if (p == MatchPhase.completed) {
      throw const ScoringException('The match is over.');
    }
    switch (event) {
      case final OpenersSelected e:
        if (p == MatchPhase.inningsBreak) {
          final first = innings.first;
          innings.add(_InningsBuilder(
            number: 2,
            battingTeam: first.bowlingTeam,
            bowlingTeam: first.battingTeam,
            rules: setup.rules,
            target: first.runs + 1,
          ));
        } else if (p != MatchPhase.awaitingOpeners) {
          throw const ScoringException('The openers are already set.');
        }
        current.selectOpeners(e);
      case final BowlerChanged e:
        _requireLive(p);
        current.changeBowler(e);
      case final BallBowled e:
        if (p != MatchPhase.inPlay) throw ScoringException(_phaseMessage(p));
        current.ball(e);
      case final NewBatter e:
        if (p != MatchPhase.awaitingBatter) {
          throw const ScoringException('No new batter is needed right now.');
        }
        current.newBatter(e);
      case final BatterRetired e:
        _requireLive(p);
        current.retire(e);
      case StrikeSwapped():
        _requireLive(p);
        current.swapStrike();
      case final InningsClosed e:
        _requireLive(p);
        current.close(e.reason);
      case MatchAbandoned():
        result = const MatchResult(kind: ResultKind.noResult);
    }
    if (innings.length == 2 && current.complete) result = _computeResult();
  }

  void _requireLive(MatchPhase p) {
    if (p == MatchPhase.awaitingBowler ||
        p == MatchPhase.awaitingBatter ||
        p == MatchPhase.inPlay) {
      return;
    }
    throw ScoringException(_phaseMessage(p));
  }

  MatchResult _computeResult() {
    final first = innings[0];
    final second = innings[1];
    final target = second.target!;
    if (second.runs >= target) {
      return MatchResult(
        kind: ResultKind.wickets,
        winnerTeamId: second.battingTeam.id,
        margin: second.maxWickets - second.wickets,
        ballsRemaining: setup.rules.ballsPerInnings - second.legalBalls,
      );
    }
    if (second.runs == target - 1) {
      return const MatchResult(kind: ResultKind.tie);
    }
    return MatchResult(
      kind: ResultKind.runs,
      winnerTeamId: first.battingTeam.id,
      margin: target - 1 - second.runs,
    );
  }

  MatchState snapshot(int eventCount) => MatchState(
        setup: setup,
        phase: phase,
        innings: List.unmodifiable([for (final i in innings) i.snapshot()]),
        result: result,
        eventCount: eventCount,
      );
}

String _phaseMessage(MatchPhase p) => switch (p) {
      MatchPhase.awaitingOpeners => 'Select the opening batters first.',
      MatchPhase.awaitingBowler => 'Select a bowler first.',
      MatchPhase.awaitingBatter => 'Select the next batter first.',
      MatchPhase.inningsBreak => 'Start the next innings first.',
      MatchPhase.completed => 'The match is over.',
      MatchPhase.inPlay => 'That is not allowed right now.',
    };

class _BatterBuilder {
  _BatterBuilder(this.playerId);

  final String playerId;
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  Dismissal? dismissal;

  BatterScore snapshot() => BatterScore(
        playerId: playerId,
        runs: runs,
        balls: balls,
        fours: fours,
        sixes: sixes,
        dismissal: dismissal,
      );
}

class _BowlerBuilder {
  _BowlerBuilder(this.playerId);

  final String playerId;
  int legalBalls = 0;
  int runs = 0;
  int wickets = 0;
  int maidens = 0;
  int wides = 0;
  int noBalls = 0;
  int dots = 0;

  BowlerFigures snapshot() => BowlerFigures(
        playerId: playerId,
        legalBalls: legalBalls,
        runs: runs,
        wickets: wickets,
        maidens: maidens,
        wides: wides,
        noBalls: noBalls,
        dots: dots,
      );
}

const _restrictedDismissals = {
  DismissalType.runOut,
  DismissalType.obstructingTheField,
};

const _wideDismissals = {
  DismissalType.stumped,
  DismissalType.hitWicket,
  DismissalType.runOut,
  DismissalType.obstructingTheField,
};

final _onFieldDismissals = {
  for (final t in DismissalType.values)
    if (!t.isRetirement) t,
};

/// Dismissals that are possible on a delivery of type [extra]. UIs use this
/// to offer only valid choices; the engine uses it to validate.
Set<DismissalType> allowedDismissals(ExtraType extra, {required bool freeHit}) {
  if (freeHit) return _restrictedDismissals;
  return switch (extra) {
    ExtraType.none => _onFieldDismissals,
    ExtraType.wide => _wideDismissals,
    ExtraType.noBall || ExtraType.bye || ExtraType.legBye => _restrictedDismissals,
  };
}

class _InningsBuilder {
  _InningsBuilder({
    required this.number,
    required this.battingTeam,
    required this.bowlingTeam,
    required this.rules,
    this.target,
  });

  final int number;
  final Team battingTeam;
  final Team bowlingTeam;
  final MatchRules rules;
  final int? target;

  int runs = 0;
  int wickets = 0;
  int legalBalls = 0;
  int wides = 0;
  int noBalls = 0;
  int byes = 0;
  int legByes = 0;

  final batters = <_BatterBuilder>[];
  final bowlers = <_BowlerBuilder>[];
  String? strikerId;
  String? nonStrikerId;
  String? bowlerId;
  String? lastOverBowlerId;
  bool openersSet = false;

  final completedOvers = <List<BallSummary>>[];
  var currentOver = <BallSummary>[];
  int _overBowlerRuns = 0;
  bool _overSingleBowler = true;

  /// Everyone who bowled a ball of the current / previous over. Law 17.8: no
  /// one may bowl parts of two consecutive overs.
  var _currentOverBowlerIds = <String>{};
  var _previousOverBowlerIds = <String>{};

  final fallOfWickets = <FallOfWicket>[];
  int partnershipRuns = 0;
  int partnershipBalls = 0;
  bool freeHit = false;
  bool complete = false;
  String? closeReason;

  int get maxWickets => rules.maxWicketsFor(battingTeam.players.length);

  MatchPhase get phase {
    if (!openersSet) return MatchPhase.awaitingOpeners;
    if (needsBatter) return MatchPhase.awaitingBatter;
    if (bowlerId == null) return MatchPhase.awaitingBowler;
    return MatchPhase.inPlay;
  }

  // ---- lookups -----------------------------------------------------------

  String _name(String playerId) =>
      battingTeam.playerById(playerId)?.name ??
      bowlingTeam.playerById(playerId)?.name ??
      playerId;

  _BatterBuilder? _batter(String playerId) {
    for (final b in batters) {
      if (b.playerId == playerId) return b;
    }
    return null;
  }

  _BowlerBuilder? _bowlerOrNull(String playerId) {
    for (final b in bowlers) {
      if (b.playerId == playerId) return b;
    }
    return null;
  }

  _BowlerBuilder _bowler(String playerId) {
    final existing = _bowlerOrNull(playerId);
    if (existing != null) return existing;
    final created = _BowlerBuilder(playerId);
    bowlers.add(created);
    return created;
  }

  bool _atCrease(String playerId) =>
      playerId == strikerId || playerId == nonStrikerId;

  List<String> get availableBatterIds => [
        for (final p in battingTeam.players)
          if (!_atCrease(p.id) && _canBat(p.id)) p.id,
      ];

  bool _canBat(String playerId) {
    final b = _batter(playerId);
    return b == null || b.dismissal?.type == DismissalType.retiredHurt;
  }

  bool get needsBatter =>
      openersSet &&
      !complete &&
      (strikerId == null || nonStrikerId == null) &&
      availableBatterIds.isNotEmpty;

  List<String> get eligibleBowlerIds {
    if (!openersSet || complete) return const [];
    return [
      for (final p in bowlingTeam.players)
        if (_bowlerIneligibleReason(p.id) == null) p.id,
    ];
  }

  String? _bowlerIneligibleReason(String playerId) {
    if (!bowlingTeam.hasPlayer(playerId)) {
      return '${_name(playerId)} is not in the bowling side.';
    }
    if (_previousOverBowlerIds.contains(playerId)) {
      return '${_name(playerId)} bowled in the previous over.';
    }
    if (playerId == bowlerId && currentOver.isNotEmpty) {
      return '${_name(playerId)} is already bowling this over.';
    }
    final max = rules.maxOversPerBowler;
    final figures = _bowlerOrNull(playerId);
    if (max != null && figures != null) {
      final limit = max * rules.ballsPerOver;
      // A part over counts as a whole over against the limit, so a full new
      // over must still fit within it.
      final needed = currentOver.isEmpty ? rules.ballsPerOver : 1;
      if (figures.legalBalls + needed > limit) {
        return '${_name(playerId)} has bowled the maximum $max overs.';
      }
    }
    return null;
  }

  // ---- events -------------------------------------------------------------

  void selectOpeners(OpenersSelected e) {
    for (final id in [e.strikerId, e.nonStrikerId]) {
      if (!battingTeam.hasPlayer(id)) {
        throw ScoringException('${_name(id)} is not in ${battingTeam.name}.');
      }
    }
    if (e.strikerId == e.nonStrikerId) {
      throw const ScoringException('Pick two different batters.');
    }
    batters
      ..add(_BatterBuilder(e.strikerId))
      ..add(_BatterBuilder(e.nonStrikerId));
    strikerId = e.strikerId;
    nonStrikerId = e.nonStrikerId;
    openersSet = true;
  }

  void changeBowler(BowlerChanged e) {
    if (needsBatter) {
      throw const ScoringException('Select the next batter first.');
    }
    final reason = _bowlerIneligibleReason(e.bowlerId);
    if (reason != null) throw ScoringException(reason);
    if (bowlerId != null && currentOver.isNotEmpty) _overSingleBowler = false;
    // Figures are created on the first ball, so a bowler replaced before
    // bowling does not appear on the scorecard.
    bowlerId = e.bowlerId;
  }

  void ball(BallBowled e) {
    _validateBall(e);
    final extra = e.extra;
    final penalty = _penalty(extra);
    final legal = extra != ExtraType.wide && extra != ExtraType.noBall;
    final total = e.runsOffBat + e.extraRuns + penalty;

    runs += total;
    switch (extra) {
      case ExtraType.wide:
        wides += penalty + e.extraRuns;
      case ExtraType.noBall:
        noBalls += penalty;
        byes += e.extraRuns;
      case ExtraType.bye:
        byes += e.extraRuns;
      case ExtraType.legBye:
        legByes += e.extraRuns;
      case ExtraType.none:
        break;
    }

    final striker = _batter(strikerId!)!;
    if (extra != ExtraType.wide) {
      striker.balls++;
      striker.runs += e.runsOffBat;
      if (e.boundary && e.runsOffBat == 4) striker.fours++;
      if (e.boundary && e.runsOffBat == 6) striker.sixes++;
    }

    final bowler = _bowler(bowlerId!);
    _currentOverBowlerIds.add(bowler.playerId);
    final bowlerRuns = switch (extra) {
      ExtraType.wide => penalty + e.extraRuns,
      ExtraType.noBall => penalty + e.runsOffBat,
      ExtraType.none => e.runsOffBat,
      ExtraType.bye || ExtraType.legBye => 0,
    };
    bowler.runs += bowlerRuns;
    if (legal) bowler.legalBalls++;
    if (extra == ExtraType.wide) bowler.wides++;
    if (extra == ExtraType.noBall) bowler.noBalls++;
    if (legal && bowlerRuns == 0) bowler.dots++;
    _overBowlerRuns += bowlerRuns;

    partnershipRuns += total;
    if (extra != ExtraType.wide) partnershipBalls++; // balls faced
    if (legal) legalBalls++;
    currentOver.add(_summarise(e, total));
    freeHit = (extra == ExtraType.noBall && rules.freeHitOnNoBall) ||
        (freeHit && !legal);

    final wicket = e.wicket;
    if (wicket != null) {
      final out = _batter(wicket.batterOutId)!;
      final credited = wicket.type.creditedToBowler;
      out.dismissal = Dismissal(
        type: wicket.type,
        bowlerId: credited ? bowler.playerId : null,
        fielderId: wicket.fielderId,
      );
      if (credited) bowler.wickets++;
      _recordWicket(out.playerId);
    }

    final completedRuns = switch (extra) {
      ExtraType.wide => e.extraRuns,
      ExtraType.noBall => e.runsOffBat + e.extraRuns,
      ExtraType.bye || ExtraType.legBye => e.extraRuns,
      ExtraType.none => e.runsOffBat,
    };
    if (completedRuns.isOdd) _swap();
    if (wicket != null) _vacate(wicket.batterOutId);

    if (legal && legalBalls % rules.ballsPerOver == 0) _endOver();
    _checkComplete();
    _normaliseLoneBatter();
  }

  int _penalty(ExtraType extra) => switch (extra) {
        ExtraType.wide => rules.wideRuns,
        ExtraType.noBall => rules.noBallRuns,
        _ => 0,
      };

  void _validateBall(BallBowled e) {
    if (e.runsOffBat < 0 || e.runsOffBat > 7) {
      throw const ScoringException('Runs off the bat must be between 0 and 7.');
    }
    if (e.extraRuns < 0 || e.extraRuns > 7) {
      throw const ScoringException('Extra runs must be between 0 and 7.');
    }
    switch (e.extra) {
      case ExtraType.wide:
        if (e.runsOffBat != 0) {
          throw const ScoringException('A wide cannot have runs off the bat.');
        }
      case ExtraType.bye || ExtraType.legBye:
        if (e.runsOffBat != 0) {
          throw const ScoringException('Byes cannot have runs off the bat.');
        }
        if (e.extraRuns < 1) {
          throw const ScoringException('Byes need at least 1 run.');
        }
      case ExtraType.none || ExtraType.noBall:
        break;
    }
    if (e.boundary && e.runsOffBat != 4 && e.runsOffBat != 6) {
      throw const ScoringException('A boundary must be a 4 or a 6.');
    }
    if (e.shotZone != null && e.runsOffBat == 0) {
      throw const ScoringException('Only runs off the bat have a direction.');
    }

    final w = e.wicket;
    if (w == null) return;
    if (w.type.isRetirement) {
      throw const ScoringException('Use "retire" for retirements.');
    }
    if (!allowedDismissals(e.extra, freeHit: freeHit).contains(w.type)) {
      final on = freeHit ? 'a free hit' : _extraName(e.extra);
      throw ScoringException('${w.type.label} is not possible on $on.');
    }
    if (!_atCrease(w.batterOutId)) {
      throw ScoringException('${_name(w.batterOutId)} is not batting.');
    }
    if (!w.type.canDismissNonStriker && w.batterOutId != strikerId) {
      throw ScoringException(
          'Only the striker can be out ${w.type.label.toLowerCase()}.');
    }
    if (!_restrictedDismissals.contains(w.type) &&
        (e.runsOffBat != 0 || e.extraRuns != 0)) {
      throw ScoringException(
          'No runs can be scored with ${w.type.label.toLowerCase()}.');
    }
    final fielder = w.fielderId;
    if (fielder != null && !bowlingTeam.hasPlayer(fielder)) {
      throw ScoringException('${_name(fielder)} is not fielding.');
    }
    // The match ends the moment the target is reached (Law 16.6), so a
    // wicket after the winning runs never happened.
    final t = target;
    final ballRuns = e.runsOffBat + e.extraRuns + _penalty(e.extra);
    if (t != null && runs + ballRuns >= t) {
      throw const ScoringException(
          'The winning runs came first. Record the runs without the wicket.');
    }
  }

  void newBatter(NewBatter e) {
    if (!availableBatterIds.contains(e.batterId)) {
      throw ScoringException('${_name(e.batterId)} cannot bat now.');
    }
    final returning = _batter(e.batterId);
    if (returning != null) {
      returning.dismissal = null; // back from retired hurt
    } else {
      batters.add(_BatterBuilder(e.batterId));
    }
    if (strikerId == null) {
      strikerId = e.batterId;
    } else {
      nonStrikerId = e.batterId;
    }
  }

  void retire(BatterRetired e) {
    if (!_atCrease(e.batterId)) {
      throw ScoringException('${_name(e.batterId)} is not batting.');
    }
    _batter(e.batterId)!.dismissal = Dismissal(
      type: e.hurt ? DismissalType.retiredHurt : DismissalType.retiredOut,
    );
    if (e.hurt) {
      partnershipRuns = 0;
      partnershipBalls = 0;
    } else {
      _recordWicket(e.batterId);
    }
    _vacate(e.batterId);
    _checkComplete();
    _normaliseLoneBatter();
  }

  void swapStrike() {
    _swap();
    _normaliseLoneBatter();
  }

  void close(String reason) => _close(reason);

  // ---- helpers -------------------------------------------------------------

  void _recordWicket(String batterId) {
    wickets++;
    fallOfWickets.add(FallOfWicket(
      wicketNumber: wickets,
      runs: runs,
      batterId: batterId,
      legalBalls: legalBalls,
    ));
    partnershipRuns = 0;
    partnershipBalls = 0;
  }

  void _swap() {
    final s = strikerId;
    strikerId = nonStrikerId;
    nonStrikerId = s;
  }

  void _vacate(String batterId) {
    if (strikerId == batterId) {
      strikerId = null;
    } else if (nonStrikerId == batterId) {
      nonStrikerId = null;
    }
  }

  void _endOver() {
    final bowler = _bowler(bowlerId!);
    if (_overSingleBowler && _overBowlerRuns == 0) bowler.maidens++;
    completedOvers.add(List.unmodifiable(currentOver));
    currentOver = <BallSummary>[];
    _overBowlerRuns = 0;
    _overSingleBowler = true;
    lastOverBowlerId = bowlerId;
    _previousOverBowlerIds = _currentOverBowlerIds;
    _currentOverBowlerIds = <String>{};
    bowlerId = null;
    _swap();
  }

  void _checkComplete() {
    if (complete) return;
    final t = target;
    if (wickets >= maxWickets) {
      _close('All out');
    } else if (t != null && runs >= t) {
      _close('Target reached');
    } else if (legalBalls >= rules.ballsPerInnings) {
      _close('Overs completed');
    }
  }

  void _close(String reason) {
    complete = true;
    closeReason = reason;
    freeHit = false;
  }

  /// With last man stands, the lone batter is always on strike.
  void _normaliseLoneBatter() {
    if (complete) return;
    if (strikerId == null && nonStrikerId != null && availableBatterIds.isEmpty) {
      strikerId = nonStrikerId;
      nonStrikerId = null;
    }
  }

  BallSummary _summarise(BallBowled e, int total) {
    final base = switch (e.extra) {
      ExtraType.none => '${e.runsOffBat}',
      ExtraType.wide => e.extraRuns == 0 ? 'Wd' : 'Wd+${e.extraRuns}',
      ExtraType.noBall => e.runsOffBat + e.extraRuns == 0
          ? 'Nb'
          : 'Nb+${e.runsOffBat + e.extraRuns}',
      ExtraType.bye => '${e.extraRuns}B',
      ExtraType.legBye => '${e.extraRuns}Lb',
    };
    final label = e.wicket == null ? base : (base == '0' ? 'W' : '$base+W');
    final BallKind kind;
    if (e.wicket != null) {
      kind = BallKind.wicket;
    } else if (e.boundary && e.runsOffBat == 6) {
      kind = BallKind.six;
    } else if (e.boundary && e.runsOffBat == 4) {
      kind = BallKind.four;
    } else if (e.extra != ExtraType.none) {
      kind = BallKind.extra;
    } else if (total == 0) {
      kind = BallKind.dot;
    } else {
      kind = BallKind.runs;
    }
    return BallSummary(
      label: label,
      kind: kind,
      isLegal: e.extra != ExtraType.wide && e.extra != ExtraType.noBall,
      runs: total,
      runsOffBat: e.runsOffBat,
      batterId: strikerId,
      bowlerId: bowlerId,
      shotZone: e.shotZone,
      scoreAfter: runs,
      // The wicket on this ball is recorded just after this summary is made.
      wicketsAfter: wickets + (e.wicket?.type.countsAsWicket ?? false ? 1 : 0),
    );
  }

  InningsState snapshot() => InningsState(
        number: number,
        battingTeamId: battingTeam.id,
        bowlingTeamId: bowlingTeam.id,
        ballsPerOver: rules.ballsPerOver,
        maxBalls: rules.ballsPerInnings,
        runs: runs,
        wickets: wickets,
        legalBalls: legalBalls,
        extras: Extras(wides: wides, noBalls: noBalls, byes: byes, legByes: legByes),
        batters: List.unmodifiable([for (final b in batters) b.snapshot()]),
        bowlers: List.unmodifiable([for (final b in bowlers) b.snapshot()]),
        strikerId: strikerId,
        nonStrikerId: nonStrikerId,
        bowlerId: bowlerId,
        lastOverBowlerId: lastOverBowlerId,
        completedOvers: List.unmodifiable(completedOvers),
        currentOver: List.unmodifiable(currentOver),
        fallOfWickets: List.unmodifiable(fallOfWickets),
        partnershipRuns: partnershipRuns,
        partnershipBalls: partnershipBalls,
        isFreeHit: freeHit,
        target: target,
        isComplete: complete,
        closeReason: closeReason,
        availableBatterIds: List.unmodifiable(availableBatterIds),
        eligibleBowlerIds: List.unmodifiable(eligibleBowlerIds),
      );
}

String _extraName(ExtraType extra) => switch (extra) {
      ExtraType.none => 'a legal ball',
      ExtraType.wide => 'a wide',
      ExtraType.noBall => 'a no-ball',
      ExtraType.bye => 'a bye',
      ExtraType.legBye => 'a leg bye',
    };
