import 'package:cloud_firestore/cloud_firestore.dart';

import 'accounts.dart';
import 'match_record.dart';

/// Published matches, readable by everyone. Each match is one document, the
/// same shape as [MatchRecord.toJson], plus its owner. Writes are allowed only
/// to the owner by the security rules in `firestore.rules`.
abstract interface class CloudMatches {
  /// Creates or replaces the match. Completes once the cloud has it; while
  /// offline, Firestore keeps the write and sends it later.
  Future<void> publish(MatchRecord record, Scorer owner);

  Future<void> unpublish(String matchId);
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
}
