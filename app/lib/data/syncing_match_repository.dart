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
    final owner = _ownerOf(record);
    if (owner != null) _inBackground(_cloud.publish(record, owner), 'Publishing match ${record.id}');
  }

  @override
  Future<void> delete(String id) async {
    final record = await _local.load(id);
    await _local.delete(id);
    if (record != null && _ownerOf(record) != null) {
      _inBackground(_cloud.unpublish(id), 'Unpublishing match $id');
    }
  }

  /// The signed-in scorer, if this is their published match. A match is never
  /// sent by someone else's account, or while signed out.
  Scorer? _ownerOf(MatchRecord record) {
    final scorer = _accounts.current;
    if (scorer == null || record.publishedBy != scorer.uid) return null;
    return scorer;
  }

  static void _inBackground(Future<void> write, String what) {
    unawaited(write.catchError((Object error) => debugPrint('$what failed: $error')));
  }
}
