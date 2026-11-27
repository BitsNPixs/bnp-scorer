import 'package:cricket_engine/cricket_engine.dart';

String plural(int count, String word) {
  final ending = word.endsWith('ch') ? 'es' : 's';
  return '$count $word${count == 1 ? '' : ending}';
}

String playerName(MatchSetup setup, String? playerId) {
  if (playerId == null) return '—';
  return setup.playerById(playerId)?.name ?? 'Unknown';
}

/// The name with its scorecard marks: "Asha (c)", "Kiran (wk)", "Asha (c & wk)".
String taggedPlayerName(MatchSetup setup, String playerId) {
  final name = playerName(setup, playerId);
  final team = setup.teamA.hasPlayer(playerId) ? setup.teamA : setup.teamB;
  final tags = [
    if (team.captainId == playerId) 'c',
    if (team.keeperId == playerId) 'wk',
  ];
  return tags.isEmpty ? name : '$name (${tags.join(' & ')})';
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

/// "Asha to Bilal & Chitra", with both bowlers after a change mid-over.
String overHeadline(MatchSetup setup, OverSummary over) {
  String names(List<String> ids) => ids.map((id) => playerName(setup, id)).join(' & ');
  return '${names(over.bowlerIds)} to ${names(over.batterIds)}';
}

/// The top scorer and best bowler of an innings, or empty before a ball.
/// "Livin D 34 (19) · Subash Ambrose 3/16".
String inningsHighlights(MatchSetup setup, InningsState innings) {
  if (innings.batters.isEmpty || innings.legalBalls == 0) return '';
  final top = innings.batters.reduce((a, b) => b.runs > a.runs ? b : a);
  final parts = ['${playerName(setup, top.playerId)} ${top.runs} (${top.balls})'];
  if (innings.bowlers.isNotEmpty) {
    final best = innings.bowlers.reduce((a, b) {
      final better = b.wickets > a.wickets || (b.wickets == a.wickets && b.runs < a.runs);
      return better ? b : a;
    });
    parts.add('${playerName(setup, best.playerId)} ${best.wickets}/${best.runs}');
  }
  return parts.join(' · ');
}

String inningsLabel(int number) => number == 1 ? '1st innings' : '2nd innings';

/// One-line status for lists and the result card.
String matchStatus(MatchState state) {
  final setup = state.setup;
  final result = state.result;
  if (result != null) {
    switch (result.kind) {
      case ResultKind.tie:
        return 'Match tied';
      case ResultKind.noResult:
        return 'No result';
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

/// "Lions 87/4 (11.2 ov) v Tigers": the batting side's score and who they play.
String scoreVersus(MatchSetup setup, InningsState innings) =>
    '${setup.teamById(innings.battingTeamId).name} ${scoreLine(innings)} (${innings.oversText} ov) '
    'v ${setup.teamById(innings.bowlingTeamId).name}';
