import 'package:cloud_firestore/cloud_firestore.dart';
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

/// Published matches, readable by everyone. Each match is one document, the
/// same shape as [MatchRecord.toJson], plus its owner. Writes are allowed only
/// to the owner by the security rules in `firestore.rules`.
abstract interface class CloudMatches {
  /// Creates or replaces the match. Completes once the cloud has it; while
  /// offline, Firestore keeps the write and sends it later.
  Future<void> publish(MatchRecord record, Scorer owner);

  Future<void> unpublish(String matchId);

  /// The latest published matches, most recently saved first, updated live.
  /// A match this app cannot read (a newer format, damaged data) is left out.
  Stream<List<PublishedMatch>> recent({int limit = 30});

  /// One match as it is scored. Null once it is no longer published; an error
  /// when it cannot be read.
  Stream<PublishedMatch?> watch(String matchId);
}

class FirestoreCloudMatches implements CloudMatches {
  FirestoreCloudMatches(this._db);

  final FirebaseFirestore _db;

  /// Bump only for a change older app versions cannot read.
  static const schema = 1;

  CollectionReference<Map<String, Object?>> get _matches => _db.collection('matches');

  @override
  Future<void> publish(MatchRecord record, Scorer owner) => _matches.doc(record.id).set({
        ...record.toJson(),
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
