import 'package:cricket_engine/cricket_engine.dart';

import '../data/cloud_matches.dart';
import '../data/match_record.dart';
import '../state/upcoming.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "6 Nov".
String shortDate(DateTime date) => '${date.day} ${_months[date.month - 1]}';

/// "Sat 5 Dec, 9:00 AM", in the device's time zone.
String fixtureDate(DateTime date) {
  final local = date.toLocal();
  return '${_days[local.weekday - 1]} ${shortDate(local)}, ${clockTime(local)}';
}

/// "9:00 AM", in the device's time zone.
String clockTime(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// "Today, 6:00 PM", "Tomorrow, 9:00 AM", or the full date further off.
String upcomingWhen(DateTime date, DateTime now) {
  final local = date.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  return switch (day.difference(today).inDays) {
    0 => 'Today, ${clockTime(local)}',
    1 => 'Tomorrow, ${clockTime(local)}',
    _ => fixtureDate(local),
  };
}

/// A message inviting players and followers to a match, for WhatsApp.
String inviteText(UpcomingMatch match) {
  final when = match.startsAt;
  return [
    '\u{1F3CF} ${match.homeName} v ${match.awayName}',
    match.title,
    if (when != null) fixtureDate(when),
    ?match.venue,
    '${plural(match.overs, 'over')} a side. Follow it ball by ball on BNP Scorer.',
  ].join('\n');
}

/// "2026-03-09", which sorts by date in a file list.
String isoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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

/// Whole rupees with Indian grouping: "₹2,500", "₹1,00,000".
String rupees(int amount) {
  final digits = amount.abs().toString();
  final split = digits.length > 3 ? digits.length - 3 : 0;
  final groups = [digits.substring(split)];
  for (var end = split; end > 0; end -= 2) {
    groups.insert(0, digits.substring(end < 2 ? 0 : end - 2, end));
  }
  return '${amount < 0 ? '-' : ''}₹${groups.join(',')}';
}

/// "48*" for a not-out score.
String highScoreText(HighScore? high) =>
    high == null ? '—' : '${high.runs}${high.notOut ? '*' : ''}';

/// Wickets then runs, e.g. "3/16".
String bestBowlingText(BestBowling? best) =>
    best == null ? '—' : '${best.wickets}/${best.runs}';

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

/// The message that goes with a shared scorecard.
String shareText(MatchState state) {
  final setup = state.setup;
  final best = playerOfTheMatch(state);
  return [
    ?setup.venue,
    for (final innings in state.innings)
      '${setup.teamById(innings.battingTeamId).name} ${scoreLine(innings)} (${innings.oversText} ov)',
    matchStatus(state),
    if (best != null) 'Player of the Match: ${playerName(setup, best)}',
    'Scored with BNP Scorer',
  ].join('\n');
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

/// What a match's followers are told about [moment], as a push's title and
/// body. [state] is the match just after it.
({String title, String body}) momentText(MatchMoment moment, MatchState state) {
  final setup = state.setup;
  final inn = state.current;
  final score = scoreVersus(setup, inn);
  final name = playerName(setup, moment.playerId);
  final batter = inn.batters.where((b) => b.playerId == moment.playerId).firstOrNull;
  final innings = batter == null ? '' : '${batter.runs}${batter.isOut ? '' : '*'} (${batter.balls})';
  switch (moment.kind) {
    case MomentKind.started:
      return (
        title: '${setup.teamA.name} v ${setup.teamB.name} is underway',
        body: '${setup.teamById(inn.battingTeamId).name} batting first',
      );
    case MomentKind.wicket:
      return (
        title: 'WICKET! $name ${batter == null ? '' : dismissalText(setup, batter)} $innings'.trim(),
        body: score,
      );
    case MomentKind.fifty:
      return (title: 'FIFTY! $name $innings', body: score);
    case MomentKind.hundred:
      return (title: 'HUNDRED! $name $innings', body: score);
    case MomentKind.fiveWickets:
      final f = inn.bowlers.where((b) => b.playerId == moment.playerId).firstOrNull;
      return (title: 'FIVE-FOR! $name ${f == null ? '' : '${f.wickets}/${f.runs}'}'.trim(), body: score);
    case MomentKind.inningsBreak:
      return (
        title: 'Innings break: ${setup.teamById(inn.battingTeamId).name} ${scoreLine(inn)} (${inn.oversText} ov)',
        body: '${setup.teamById(inn.bowlingTeamId).name} need ${inn.runs + 1} to win',
      );
    case MomentKind.result:
      return (
        title: matchStatus(state),
        body: [
          for (final i in state.innings.take(2))
            '${setup.teamById(i.battingTeamId).name} ${scoreLine(i)} (${i.oversText} ov)',
        ].join(' · '),
      );
  }
}

/// The longest highlight text firestore.rules accepts; longer would refuse
/// the whole match write, so it is clipped first.
const highlightTitleMax = 120;
const highlightBodyMax = 200;

/// [text] cut to [max] characters, ending in an ellipsis when cut.
String clip(String text, int max) => text.length <= max ? text : '${text.substring(0, max - 1)}…';

/// The highlight [record]'s last event made, for its followers, or null for
/// an ordinary ball. A log that cannot be replayed makes none.
MatchHighlight? matchHighlight(MatchRecord record) {
  final events = record.events;
  if (events.isEmpty) return null;
  try {
    final before = ScoringEngine.replay(record.setup, events.sublist(0, events.length - 1));
    final after = ScoringEngine.replay(record.setup, events);
    final moment = momentOf(before, after);
    if (moment == null) return null;
    final text = momentText(moment, after);
    return MatchHighlight(
      seq: events.length,
      kind: moment.kind.name,
      title: clip(text.title, highlightTitleMax),
      body: clip(text.body, highlightBodyMax),
    );
  } on Object {
    return null;
  }
}

/// The web page that explains a join code to someone without the app.
const joinPageAddress = 'https://bitsnpixs.github.io/bnp-scorer/join.html';

/// The join page for [code]: what an invite links to and a team's QR opens.
String joinPageLink(String code) => '$joinPageAddress?code=$code';

/// A WhatsApp invite to ask to join [teamName] with its [code].
String teamInviteText(String teamName, String code) => [
      'Join $teamName on BNP Scorer, so the matches we play count on your profile.',
      'In the app: Teams, then Join a team, and type the code $code',
      'Or open: ${joinPageLink(code)}',
    ].join('\n');

/// A player's career in a line or two, to share.
String profileShareText(String name, PlayerStats? stats) {
  if (stats == null) return '$name on BNP Scorer: no finished matches yet.';
  final b = stats.batting;
  final w = stats.bowling;
  return [
    '$name on BNP Scorer: ${plural(stats.matches, 'match')}.',
    'Batting: ${b.runs} runs, best ${highScoreText(b.high)}, strike rate ${decimal(b.strikeRate, 1)}.',
    if (w.innings > 0) 'Bowling: ${plural(w.wickets, 'wicket')}, best ${bestBowlingText(w.best)}, economy ${decimal(w.economy)}.',
  ].join('\n');
}
