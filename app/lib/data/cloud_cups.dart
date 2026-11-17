import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/foundation.dart';

import 'accounts.dart';
import 'scheduled_match.dart';

/// A tournament someone published, and who organises it. It never carries who
/// has paid the entry fee ([Tournament.toPublicJson]).
class PublishedTournament {
  const PublishedTournament({required this.tournament, required this.ownerUid, required this.ownerName});

  final Tournament tournament;
  final String ownerUid;
  final String ownerName;
}

/// A scheduled friendly someone published.
class PublishedSchedule {
  const PublishedSchedule({required this.schedule, required this.ownerUid, required this.ownerName});

  final ScheduledMatch schedule;
  final String ownerUid;
  final String ownerName;
}

/// Published tournaments and scheduled friendlies, readable by everyone and
/// written only by their owner (`firestore.rules`). Like `CloudMatches`, one
/// document each, plus the owner.
abstract interface class CloudCups {
  Future<void> publishTournament(Tournament tournament, Scorer owner);

  Future<void> unpublishTournament(String id);

  /// The latest published tournaments, most recently saved first, live.
  Stream<List<PublishedTournament>> recentTournaments({int limit = 20});

  /// One tournament as it changes. Null once unpublished; an error when it
  /// cannot be read.
  Stream<PublishedTournament?> watchTournament(String id);

  Future<void> publishSchedule(ScheduledMatch schedule, Scorer owner);

  Future<void> unpublishSchedule(String id);

  /// Published friendlies starting at [from] or later, soonest first, live.
  Stream<List<PublishedSchedule>> upcomingSchedules({required DateTime from, int limit = 30});
}

class FirestoreCloudCups implements CloudCups {
  FirestoreCloudCups(this._db);

  final FirebaseFirestore _db;

  /// Bump only for a change older app versions cannot read.
  static const schema = 1;

  CollectionReference<Map<String, Object?>> get _tournaments => _db.collection('tournaments');
  CollectionReference<Map<String, Object?>> get _schedules => _db.collection('schedules');

  Map<String, Object?> _owned(Json json, Scorer owner) => {
        ...json,
        'ownerUid': owner.uid,
        'ownerName': owner.name,
        'schema': schema,
        'savedAt': FieldValue.serverTimestamp(),
      };

  @override
  Future<void> publishTournament(Tournament tournament, Scorer owner) =>
      _tournaments.doc(tournament.id).set(_owned(tournament.toPublicJson(), owner));

  @override
  Future<void> unpublishTournament(String id) => _tournaments.doc(id).delete();

  @override
  Stream<List<PublishedTournament>> recentTournaments({int limit = 20}) => _tournaments
      .orderBy('savedAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((query) => [
            for (final doc in query.docs) ?_tryParse(doc.id, doc.data(), parsePublishedTournament),
          ]);

  @override
  Stream<PublishedTournament?> watchTournament(String id) => _tournaments.doc(id).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : parsePublishedTournament(data);
      });

  @override
  Future<void> publishSchedule(ScheduledMatch schedule, Scorer owner) {
    // Who scheduled it is the owner field; the phone's marker stays local.
    final json = schedule.toJson()..remove('publishedBy');
    return _schedules.doc(schedule.id).set(_owned(json, owner));
  }

  @override
  Future<void> unpublishSchedule(String id) => _schedules.doc(id).delete();

  @override
  Stream<List<PublishedSchedule>> upcomingSchedules({required DateTime from, int limit = 30}) => _schedules
      // ISO dates in UTC sort as text, so the range needs no extra index.
      .where('startsAt', isGreaterThanOrEqualTo: from.toUtc().toIso8601String())
      .orderBy('startsAt')
      .limit(limit)
      .snapshots()
      .map((query) => [
            for (final doc in query.docs) ?_tryParse(doc.id, doc.data(), parsePublishedSchedule),
          ]);

  static T? _tryParse<T>(String id, Map<String, Object?> data, T Function(Map<String, Object?>) parse) {
    try {
      return parse(data);
    } on Object catch (e) {
      debugPrint('Skipping published document $id that cannot be read: $e');
      return null;
    }
  }
}

void _checkSchema(Map<String, Object?> data) {
  final schema = data['schema'];
  if (schema is int && schema > FirestoreCloudCups.schema) {
    throw const FormatException('This was saved by a newer version of BNP Scorer.');
  }
}

/// Reads a published tournament. Throws on one this app cannot read.
PublishedTournament parsePublishedTournament(Map<String, Object?> data) {
  _checkSchema(data);
  return PublishedTournament(
    tournament: Tournament.fromJson({...data}..remove('paid')),
    ownerUid: data['ownerUid']! as String,
    ownerName: data['ownerName'] as String? ?? 'An organiser',
  );
}

/// Reads a published friendly. Throws on one this app cannot read.
PublishedSchedule parsePublishedSchedule(Map<String, Object?> data) {
  _checkSchema(data);
  return PublishedSchedule(
    schedule: ScheduledMatch.fromJson(data),
    ownerUid: data['ownerUid']! as String,
    ownerName: data['ownerName'] as String? ?? 'A scorer',
  );
}
