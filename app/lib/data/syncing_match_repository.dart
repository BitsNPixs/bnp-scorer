import 'dart:async';

import 'package:flutter/foundation.dart';

import 'accounts.dart';
import 'cloud_matches.dart';
import 'match_record.dart';
import 'match_repository.dart';

/// Keeps every match on the phone, and also sends the scorer's published
/// matches to the cloud so everyone can follow them.
///
/// The phone stays the source of truth: a save is done once it is stored
/// locally. The cloud write is not awaited, because offline Firestore holds it
/// and sends it when the phone is back online. Every save sends the whole
/// match, so a missed write is made good by the next one.
class SyncingMatchRepository implements MatchRepository {
  SyncingMatchRepository(this._local, this._cloud, this._accounts);

  final MatchRepository _local;
  final CloudMatches _cloud;
  final Accounts _accounts;

  @override
  Future<List<MatchRecord>> loadAll() => _local.loadAll();

  @override
  Future<MatchRecord?> load(String id) => _local.load(id);

  @override
  Future<void> save(MatchRecord record) async {
    await _local.save(record);
    final owner = publisherOf(_accounts, record.publishedBy);
    if (owner != null) sendInBackground(_cloud.publish(record, owner), 'Publishing match ${record.id}');
  }

  @override
  Future<void> delete(String id) async {
    final record = await _local.load(id);
    await _local.delete(id);
    if (record != null && publisherOf(_accounts, record.publishedBy) != null) {
      sendInBackground(_cloud.unpublish(id), 'Unpublishing match $id');
    }
  }
}

/// The signed-in scorer, if they published what is marked [publishedBy].
/// Nothing is ever sent by someone else's account, or while signed out.
Scorer? publisherOf(Accounts accounts, String? publishedBy) {
  final scorer = accounts.current;
  return scorer != null && publishedBy == scorer.uid ? scorer : null;
}

/// Starts a cloud write without waiting: offline, Firestore keeps it and sends
/// it later, and every save sends the whole document again.
void sendInBackground(Future<void> write, String what) {
  unawaited(write.catchError((Object error) => debugPrint('$what failed: $error')));
}
