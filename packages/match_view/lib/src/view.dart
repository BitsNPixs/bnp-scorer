import 'package:cricket_engine/cricket_engine.dart';

import 'wording.dart';

/// The format of [matchCard] and [matchView]. Stored copies and API
/// responses carry it as `v`. Add fields freely; bump it only for a change
/// that would break a reader of the old shape, and never rename a field.
const matchViewVersion = 1;

/// Where a match stands, for lists and filters. Stored by name.
enum MatchStage {
  /// Published, no ball bowled yet.
  starting,
  live,

  /// Between the innings.
  inningsBreak,
  finished,
}

MatchStage stageOf(MatchState state) => switch (state.phase) {
      MatchPhase.completed => MatchStage.finished,
      MatchPhase.inningsBreak => MatchStage.inningsBreak,
      _ when state.innings.length == 1 && state.current.legalBalls == 0 && state.current.runs == 0 =>
        MatchStage.starting,
      _ => MatchStage.live,
    };

/// A match in a few lines, for a list: who is playing, the score of each
/// innings and where it stands.
Json matchCard(MatchState state) {
  final setup = state.setup;
  final result = state.result;
  return {
    'v': matchViewVersion,
    'id': setup.id,
    'teams': [
      for (final team in [setup.teamA, setup.teamB])
        {'id': team.id, 'name': team.name, 'logoUrl': team.logoUrl},
    ],
    'venue': setup.venue,
    'oversPerInnings': setup.rules.oversPerInnings,
    'ballsPerOver': setup.rules.ballsPerOver,
    'superOver': setup.rules.superOver,
    'stage': stageOf(state).name,
    'status': matchStatus(state),
    'innings': [for (final innings in state.innings) _inningsLine(setup, innings)],
    'result': result == null
        ? null
        : {
            'kind': result.kind.name,
            'winnerTeamId': result.winnerTeamId,
            'margin': result.margin,
            'ballsRemaining': result.ballsRemaining,
          },
  };
}

/// Everything a match page shows: the card, the toss, the player of the
/// match, and each innings' batting, bowling, fall of wickets and overs.
Json matchView(MatchState state) {
  final setup = state.setup;
  final best = playerOfTheMatch(state);
  return {
    ...matchCard(state),
    'toss': {'winnerTeamId': setup.tossWinnerId, 'decision': setup.tossDecision.name},
    'playerOfTheMatch': best == null ? null : {'id': best, 'name': playerName(setup, best)},
    'innings': [
      for (final innings in state.innings)
        {
          ..._inningsLine(setup, innings),
          ..._inningsDetail(setup, innings, live: !state.isCompleted && !innings.isComplete),
        },
    ],
  };
}

Json _inningsLine(MatchSetup setup, InningsState innings) => {
      'number': innings.number,
      'battingTeamId': innings.battingTeamId,
      'team': setup.teamById(innings.battingTeamId).name,
      'runs': innings.runs,
      'wickets': innings.wickets,
      'overs': innings.oversText,
      'score': scoreLine(innings),
    };

Json _inningsDetail(MatchSetup setup, InningsState innings, {required bool live}) {
  final perOver = innings.ballsPerOver;
  final batted = {for (final b in innings.batters) b.playerId};
  final extras = innings.extras;
  final overs = innings.overs;
  return {
    'label': inningsLabel(innings.number),
    'bowlingTeamId': innings.bowlingTeamId,
    'maxOvers': innings.maxOversText,
    'complete': innings.isComplete,
    'runRate': _twoPlaces(innings.runRate),
    'target': innings.target,
    'runsNeeded': innings.runsNeeded,
    'ballsRemaining': innings.ballsRemaining,
    'requiredRunRate': _twoPlaces(innings.requiredRunRate),
    'highlights': inningsHighlights(setup, innings),
    'batters': [
      for (final b in innings.batters)
        {
          'id': b.playerId,
          'name': taggedPlayerName(setup, b.playerId),
          'runs': b.runs,
          'balls': b.balls,
          'fours': b.fours,
          'sixes': b.sixes,
          'strikeRate': _twoPlaces(b.strikeRate),
          'out': b.isOut,
          'howOut': dismissalText(setup, b),
        },
    ],
    'yetToBat': [
      for (final p in setup.teamById(innings.battingTeamId).players)
        if (!batted.contains(p.id)) {'id': p.id, 'name': taggedPlayerName(setup, p.id)},
    ],
    'extras': {
      'wides': extras.wides,
      'noBalls': extras.noBalls,
      'byes': extras.byes,
      'legByes': extras.legByes,
      'total': extras.total,
    },
    'bowlers': [
      for (final f in innings.bowlers)
        {
          'id': f.playerId,
          'name': taggedPlayerName(setup, f.playerId),
          'overs': f.overs(perOver),
          'maidens': f.maidens,
          'runs': f.runs,
          'wickets': f.wickets,
          'economy': _twoPlaces(f.economy(perOver)),
          'wides': f.wides,
          'noBalls': f.noBalls,
          'dots': f.dots,
        },
    ],
    'fallOfWickets': [
      for (final w in innings.fallOfWickets)
        {
          'wicket': w.wicketNumber,
          'runs': w.runs,
          'score': '${w.runs}-${w.wicketNumber}',
          'batterId': w.batterId,
          'name': playerName(setup, w.batterId),
          'over': formatOvers(w.legalBalls, perOver),
        },
    ],
    'overByOver': [
      for (final (index, over) in overs.indexed)
        {
          'number': index + 1,
          'runs': over.runs,
          'wickets': over.wickets,
          'headline': overHeadline(setup, over),
          'score': '${over.scoreAfter}/${over.wicketsAfter}',
          'balls': [
            for (final ball in over.balls)
              {
                'label': ball.label,
                'kind': ball.kind.name,
                'legal': ball.isLegal,
                'runs': ball.runs,
                'zone': ball.shotZone?.name,
              },
          ],
        },
    ],
    // Who is in the middle, only while this innings is being played.
    'atCrease': !live
        ? null
        : {
            'strikerId': innings.strikerId,
            'nonStrikerId': innings.nonStrikerId,
            'bowlerId': innings.bowlerId,
            'partnershipRuns': innings.partnershipRuns,
            'partnershipBalls': innings.partnershipBalls,
            'freeHit': innings.isFreeHit,
          },
  };
}

/// Rates as the scorecard prints them: 7.5, 133.33. Null stays null.
double? _twoPlaces(double? value) => value == null ? null : (value * 100).round() / 100;
