import 'package:cricket_engine/cricket_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_documents.dart';

/// Marks a `_copy` argument that was left out, so null can still clear a field.
const _keep = Object();

/// A friendly set for later: who plays, how many overs, where and when. It is
/// not a match yet. The toss is set when it starts, through New match filled
/// in from it, and then the schedule is removed.
class ScheduledMatch {
  const ScheduledMatch({
    required this.id,
    required this.teamA,
    required this.teamB,
    required this.oversPerInnings,
    required this.startsAt,
    required this.createdAt,
    this.venue,
    this.publishedBy,
  });

  final String id;

  /// Squads as they were when it was scheduled. Starting it uses the latest
  /// saved squads with the same ids, when there are any.
  final Team teamA;
  final Team teamB;
  final int oversPerInnings;
  final DateTime startsAt;
  final DateTime createdAt;
  final String? venue;

  /// The signed-in scorer who published it for everyone, like
  /// `MatchRecord.publishedBy`. Null for one that stays on this phone.
  final String? publishedBy;

  ScheduledMatch withStart(DateTime startsAt) => _copy(startsAt: startsAt);

  /// A blank ground clears it.
  ScheduledMatch withVenue(String? venue) {
    final ground = venue?.trim() ?? '';
    return _copy(venue: ground.isEmpty ? null : ground);
  }

  ScheduledMatch _copy({DateTime? startsAt, Object? venue = _keep}) => ScheduledMatch(
        id: id,
        teamA: teamA,
        teamB: teamB,
        oversPerInnings: oversPerInnings,
        startsAt: startsAt ?? this.startsAt,
        createdAt: createdAt,
        venue: identical(venue, _keep) ? this.venue : venue as String?,
        publishedBy: publishedBy,
      );

  Json toJson() => {
        'id': id,
        'teamA': teamA.toJson(),
        'teamB': teamB.toJson(),
        'oversPerInnings': oversPerInnings,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'venue': ?venue,
        'publishedBy': ?publishedBy,
      };

  factory ScheduledMatch.fromJson(Json json) => ScheduledMatch(
        id: json['id']! as String,
        teamA: Team.fromJson(json['teamA']! as Json),
        teamB: Team.fromJson(json['teamB']! as Json),
        oversPerInnings: json['oversPerInnings']! as int,
        startsAt: DateTime.parse(json['startsAt']! as String),
        createdAt: DateTime.parse(json['createdAt']! as String),
        venue: json['venue'] as String?,
        publishedBy: json['publishedBy'] as String?,
      );
}

/// Storage boundary for scheduled friendlies.
abstract interface class ScheduleRepository {
  /// Soonest first. Unreadable records are skipped.
  Future<List<ScheduledMatch>> loadAll();

  Future<void> save(ScheduledMatch match);

  Future<void> delete(String id);
}

class LocalScheduleRepository implements ScheduleRepository {
  LocalScheduleRepository(SharedPreferences prefs)
      : _documents = LocalDocuments(
          prefs: prefs,
          indexKey: 'bnp_scorer.scheduleIds',
          keyPrefix: 'bnp_scorer.schedule.',
          fromJson: ScheduledMatch.fromJson,
          toJson: (match) => match.toJson(),
        );

  final LocalDocuments<ScheduledMatch> _documents;

  @override
  Future<List<ScheduledMatch>> loadAll() async =>
      _documents.readAll()..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  @override
  Future<void> save(ScheduledMatch match) => _documents.save(match.id, match);

  @override
  Future<void> delete(String id) => _documents.delete(id);
}
