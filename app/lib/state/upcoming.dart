import 'package:cricket_engine/cricket_engine.dart';

import '../data/scheduled_match.dart';

/// A match still to be played: a tournament fixture not started yet, or a
/// scheduled friendly. Exactly one of [fixture] (with its [tournament]) and
/// [schedule] is set.
class UpcomingMatch {
  UpcomingMatch.fixture(Tournament this.tournament, Fixture this.fixture) : schedule = null;

  UpcomingMatch.friendly(ScheduledMatch this.schedule)
      : tournament = null,
        fixture = null;

  final Tournament? tournament;
  final Fixture? fixture;
  final ScheduledMatch? schedule;

  String get id => schedule?.id ?? '${tournament!.id}/${fixture!.id}';

  /// Null for a fixture nobody has dated yet.
  DateTime? get startsAt => schedule?.startsAt ?? fixture!.scheduledAt;

  String get homeName => schedule?.teamA.name ?? tournament!.teamById(fixture!.teamAId).name;

  String get awayName => schedule?.teamB.name ?? tournament!.teamById(fixture!.teamBId).name;

  /// "Diwali Cup · Quarter-final 2", or "Friendly".
  String get title => schedule != null ? 'Friendly' : '${tournament!.name} · ${fixture!.label}';

  String? get venue => schedule != null ? schedule!.venue : (fixture!.venue ?? tournament!.venue);

  int get overs {
    if (schedule case final s?) return s.oversPerInnings;
    return fixture!.isDecider ? 1 : tournament!.oversPerInnings;
  }
}

/// How long a match stays on the Upcoming list after its start time, so one
/// due this morning is still there to start this afternoon.
const upcomingGrace = Duration(hours: 12);

/// Dated fixtures not started yet and scheduled friendlies, soonest first,
/// leaving out those more than [upcomingGrace] past their start.
List<UpcomingMatch> upcomingMatches(
  Iterable<Tournament> tournaments,
  Iterable<ScheduledMatch> schedules,
  DateTime now,
) {
  final from = now.subtract(upcomingGrace);
  final list = [
    for (final t in tournaments)
      for (final f in t.fixtures)
        if (f.matchId == null && f.scheduledAt != null && !f.scheduledAt!.isBefore(from))
          UpcomingMatch.fixture(t, f),
    for (final s in schedules)
      if (!s.startsAt.isBefore(from)) UpcomingMatch.friendly(s),
  ];
  return list..sort((a, b) => a.startsAt!.compareTo(b.startsAt!));
}
