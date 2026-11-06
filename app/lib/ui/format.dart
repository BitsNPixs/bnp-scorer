import 'package:cricket_engine/cricket_engine.dart';

String plural(int count, String word) {
  final ending = word.endsWith('ch') ? 'es' : 's';
  return '$count $word${count == 1 ? '' : ending}';
}

String playerName(MatchSetup setup, String? playerId) {
  if (playerId == null) return '—';
  return setup.playerById(playerId)?.name ?? 'Unknown';
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

String scoreLine(InningsState innings) => '${innings.runs}/${innings.wickets}';

/// Bowler figures as "O-M-R-W", e.g. "3.2-0-21-2".
String figures(BowlerFigures f, int ballsPerOver) =>
    '${f.overs(ballsPerOver)}-${f.maidens}-${f.runs}-${f.wickets}';

/// Scorecard dismissal text, e.g. "c Ravi b Arun".
String dismissalText(MatchSetup setup, BatterScore batter) {
  final d = batter.dismissal;
  if (d == null) return 'not out';
  final bowler = playerName(setup, d.bowlerId);
  final fielderId = d.fielderId;
  final fielder = fielderId == null ? null : playerName(setup, fielderId);
  return switch (d.type) {
    DismissalType.bowled => 'b $bowler',
    DismissalType.caught when fielderId != null && fielderId == d.bowlerId =>
      'c & b $bowler',
    DismissalType.caught => fielder == null ? 'caught b $bowler' : 'c $fielder b $bowler',
    DismissalType.lbw => 'lbw b $bowler',
    DismissalType.stumped => fielder == null ? 'st b $bowler' : 'st $fielder b $bowler',
    DismissalType.hitWicket => 'hit wicket b $bowler',
    DismissalType.runOut => fielder == null ? 'run out' : 'run out ($fielder)',
    DismissalType.obstructingTheField => 'obstructing the field',
    DismissalType.retiredOut => 'retired out',
    DismissalType.retiredHurt => 'retired hurt',
  };
}

/// [value] to [digits] places, or a dash when it has no value yet.
String decimal(double? value, [int digits = 2]) => value?.toStringAsFixed(digits) ?? '—';

/// Net run rate style, always with a sign: "+1.25".
String signedDecimal(double? value) {
  if (value == null) return '—';
  return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}';
}

/// "48*" for a not-out score.
String highScoreText(HighScore? high) =>
    high == null ? '—' : '${high.runs}${high.notOut ? '*' : ''}';

/// Wickets then runs, e.g. "3/16".
String bestBowlingText(BestBowling? best) =>
    best == null ? '—' : '${best.wickets}/${best.runs}';

String inningsLabel(int number) => number == 1 ? '1st innings' : '2nd innings';

/// One-line status for lists and the result card.
String matchStatus(MatchState state) {
  final setup = state.setup;
  final result = state.result;
  if (result != null) {
    switch (result.kind) {
      case ResultKind.tie:
        return 'Match tied';
      case ResultKind.runs:
        return '${setup.teamById(result.winnerTeamId!).name} won by '
            '${plural(result.margin, 'run')}';
      case ResultKind.wickets:
        final balls = result.ballsRemaining ?? 0;
        final spare = balls > 0 ? ' (${plural(balls, 'ball')} left)' : '';
        return '${setup.teamById(result.winnerTeamId!).name} won by '
            '${plural(result.margin, 'wicket')}$spare';
    }
  }
  final inn = state.current;
  final batting = setup.teamById(inn.battingTeamId).name;
  return switch (state.phase) {
    MatchPhase.awaitingOpeners when inn.number == 1 && inn.legalBalls == 0 =>
      '${setup.teamById(setup.tossWinnerId).name} won the toss and chose to '
          '${setup.tossDecision == TossDecision.bat ? 'bat' : 'bowl'}',
    MatchPhase.inningsBreak =>
      'Innings break · ${setup.opponentOf(inn.battingTeamId).name} need ${inn.runs + 1}',
    _ when inn.target != null =>
      '$batting need ${plural(inn.runsNeeded!, 'run')} from ${plural(inn.ballsRemaining, 'ball')}',
    _ => '$batting ${scoreLine(inn)} (${inn.oversText} ov)',
  };
}
