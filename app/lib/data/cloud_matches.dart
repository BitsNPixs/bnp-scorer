import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/foundation.dart';

import 'accounts.dart';
import 'match_record.dart';

/// A match someone published, and who scores it.
class PublishedMatch {
  const PublishedMatch({required this.record, required this.ownerUid, required this.ownerName});

  final MatchRecord record;
  final String ownerUid;
  final String ownerName;
}

/// The latest moment worth telling a match's followers (a wicket, a
/// milestone, the result), published with the ball that made it. The Cloud
/// Function sends it once, when [seq] first appears. Field names are a
/// storage format the Function reads: never rename them.
class MatchHighlight {
  const MatchHighlight({required this.seq, required this.kind, required this.title, required this.body});

  /// The number of events when it happened, so a resent write is not news.
  final int seq;

  /// [MomentKind.name].
  final String kind;
  final String title;
  final String body;

  Map<String, Object?> toJson() => {'seq': seq, 'kind': kind, 'title': title, 'body': body};
}

/// Published matches, readable by everyone. Each match is one document, the
/// same shape as [MatchRecord.toJson], plus its owner. Writes are allowed only
/// to the owner by the security rules in `firestore.rules`.
abstract interface class CloudMatches {
  /// Creates or replaces the match, with the [highlight] this save made, if
  /// any. Completes once the cloud has it; while offline, Firestore keeps the
  /// write and sends it later.
  Future<void> publish(MatchRecord record, Scorer owner, {MatchHighlight? highlight});

  Future<void> unpublish(String matchId);

  /// The latest published matches, most recently saved first, updated live.
  /// A match this app cannot read (a newer format, damaged data) is left out.
  Stream<List<PublishedMatch>> recent({int limit = 30});

  /// One match as it is scored. Null once it is no longer published; an error
  /// when it cannot be read.
  Stream<PublishedMatch?> watch(String matchId);

  /// Published matches [playerId] was picked in, up to [limit], in no order.
  /// Matches published before `playerIds` existed are not found.
  Future<List<PublishedMatch>> byPlayer(String playerId, {int limit = 100});
}

/// Everyone picked in the match, both sides: the `playerIds` field of a
/// published match, which finds a player's matches for their profile.
List<String> matchPlayerIds(MatchSetup setup) => [
      for (final team in [setup.teamA, setup.teamB])
        for (final player in team.players) player.id,
    ];

class FirestoreCloudMatches implements CloudMatches {
  FirestoreCloudMatches(this._db);

  final FirebaseFirestore _db;

  /// Bump only for a change older app versions cannot read.
  static const schema = 1;

  CollectionReference<Map<String, Object?>> get _matches => _db.collection('matches');

  @override
  Future<void> publish(MatchRecord record, Scorer owner, {MatchHighlight? highlight}) =>
      _matches.doc(record.id).set({
        ...record.toJson(),
        'playerIds': matchPlayerIds(record.setup),
        'highlight': ?highlight?.toJson(),
        'ownerUid': owner.uid,
        'ownerName': owner.name,
        'schema': schema,
        'savedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> unpublish(String matchId) => _matches.doc(matchId).delete();

  @override
  Stream<List<PublishedMatch>> recent({int limit = 30}) => _matches
      .orderBy('savedAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((query) => [
            for (final doc in query.docs) ?_tryParse(doc.id, doc.data()),
          ]);

  @override
  Stream<PublishedMatch?> watch(String matchId) => _matches.doc(matchId).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : parsePublishedMatch(data);
      });

  @override
  Future<List<PublishedMatch>> byPlayer(String playerId, {int limit = 100}) async {
    // No orderBy, so the query needs no composite index; callers sort.
    final query = await _matches.where('playerIds', arrayContains: playerId).limit(limit).get();
    return [for (final doc in query.docs) ?_tryParse(doc.id, doc.data())];
  }

  static PublishedMatch? _tryParse(String id, Map<String, Object?> data) {
    try {
      return parsePublishedMatch(data);
    } on Object catch (e) {
      debugPrint('Skipping published match $id that cannot be read: $e');
      return null;
    }
  }
}

/// Reads a published match document. Throws on one this app cannot read,
/// including a newer [FirestoreCloudMatches.schema].
PublishedMatch parsePublishedMatch(Map<String, Object?> data) {
  final schema = data['schema'];
  if (schema is int && schema > FirestoreCloudMatches.schema) {
    throw const FormatException('This match was saved by a newer version of BNP Scorer.');
  }
  return PublishedMatch(
    record: MatchRecord.fromJson(data),
    ownerUid: data['ownerUid']! as String,
    ownerName: data['ownerName'] as String? ?? 'A scorer',
  );
}
