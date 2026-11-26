import 'package:cricket_engine/cricket_engine.dart';

import 'upcoming.dart';
import '../ui/format.dart';

/// How long before a match its reminder comes. Stored by name.
enum ReminderLead {
  min15(Duration(minutes: 15), '15 min'),
  min30(Duration(minutes: 30), '30 min'),
  hour1(Duration(hours: 1), '1 hour'),
  hour2(Duration(hours: 2), '2 hours'),
  day1(Duration(days: 1), '1 day');

  const ReminderLead(this.before, this.label);

  final Duration before;

  /// "1 hour", as in "1 hour before".
  final String label;

  static const fallback = ReminderLead.hour1;

  static ReminderLead byName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => fallback);
}

/// Someone else's upcoming match this phone asked to be reminded of, kept on
/// the phone as last seen so the reminder holds offline. Refreshed whenever
/// Everyone shows the match again.
class WatchedReminder {
  const WatchedReminder({
    required this.id,
    required this.homeName,
    required this.awayName,
    required this.title,
    required this.startsAt,
    this.venue,
    this.tournamentId,
  });

  WatchedReminder.of(UpcomingMatch match)
      : id = match.id,
        homeName = match.homeName,
        awayName = match.awayName,
        title = match.title,
        startsAt = match.startsAt!,
        venue = match.venue,
        tournamentId = match.tournament?.id;

  factory WatchedReminder.fromJson(Json json) => WatchedReminder(
        id: json['id'] as String,
        homeName: json['homeName'] as String,
        awayName: json['awayName'] as String,
        title: json['title'] as String,
        startsAt: DateTime.parse(json['startsAt'] as String),
        venue: json['venue'] as String?,
        tournamentId: json['tournamentId'] as String?,
      );

  /// The [UpcomingMatch.id] it follows.
  final String id;
  final String homeName;
  final String awayName;
  final String title;
  final DateTime startsAt;
  final String? venue;

  /// Set for a cup fixture, so tapping the reminder can open the cup.
  final String? tournamentId;

  Json toJson() => {
        'id': id,
        'homeName': homeName,
        'awayName': awayName,
        'title': title,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'venue': ?venue,
        'tournamentId': ?tournamentId,
      };
}

/// One reminder to show at [at]. [payload] says what a tap opens.
class Reminder {
  const Reminder({required this.payload, required this.at, required this.title, required this.body});

  final String payload;
  final DateTime at;
  final String title;
  final String body;

  /// The id the phone files it under: stable for the same match, so a
  /// changed time replaces the old reminder instead of adding one.
  int get id => notificationIdOf(payload);

  @override
  String toString() => 'Reminder($payload at $at: $title / $body)';
}

/// Payloads start with these, so a tap knows where to go and a reschedule
/// knows which pending notifications are reminders.
const ownReminderPrefix = 'upcoming:';
const watchedReminderPrefix = 'watched:';

bool isReminderPayload(String? payload) =>
    payload != null && (payload.startsWith(ownReminderPrefix) || payload.startsWith(watchedReminderPrefix));

/// A stable, positive 31-bit id for [key] (FNV-1a), the same on every run.
int notificationIdOf(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// iOS keeps only 64 pending notifications per app; stay well under it so
/// pushes and later kinds have room.
const maxReminders = 40;

/// The reminders this phone should have: every dated [own] match when
/// [ownOn], and each [watched] match, [lead] before its start. Reminders
/// whose time has passed are left out, soonest first, at most [maxReminders].
List<Reminder> planReminders({
  required Iterable<UpcomingMatch> own,
  required Iterable<WatchedReminder> watched,
  required bool ownOn,
  required ReminderLead lead,
  required DateTime now,
}) {
  Reminder? make(String payload, String home, String away, DateTime startsAt, List<String?> details) {
    final at = startsAt.subtract(lead.before);
    if (!at.isAfter(now)) return null;
    return Reminder(
      payload: payload,
      at: at,
      title: '$home v $away in ${lead.label}',
      body: [...details.nonNulls, clockTime(startsAt)].join(' · '),
    );
  }

  final reminders = <Reminder>[
    if (ownOn)
      for (final m in own)
        if (m.startsAt case final startsAt?)
          ?make('$ownReminderPrefix${m.id}', m.homeName, m.awayName, startsAt, [m.title, m.venue]),
    for (final w in watched)
      ?make('$watchedReminderPrefix${w.id}', w.homeName, w.awayName, w.startsAt, [w.title, w.venue]),
  ]..sort((a, b) => a.at.compareTo(b.at));
  return reminders.take(maxReminders).toList();
}

/// [watched] without matches that started more than [upcomingGrace] ago:
/// nothing more will come of them.
List<WatchedReminder> liveWatched(Iterable<WatchedReminder> watched, DateTime now) => [
      for (final w in watched)
        if (!w.startsAt.isBefore(now.subtract(upcomingGrace))) w,
    ];
