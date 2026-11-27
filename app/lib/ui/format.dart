import 'package:cricket_engine/cricket_engine.dart';
import 'package:match_view/match_view.dart';

import '../data/cloud_matches.dart';
import '../data/match_record.dart';
import '../state/upcoming.dart';

// The words for scores, dismissals and results are shared with the server
// and the website (packages/match_view); screens still import them from here.
export 'package:match_view/match_view.dart'
    show
        dismissalText,
        figures,
        inningsHighlights,
        inningsLabel,
        matchStatus,
        overHeadline,
        playerName,
        plural,
        scoreLine,
        scoreVersus,
        taggedPlayerName;

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

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
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
