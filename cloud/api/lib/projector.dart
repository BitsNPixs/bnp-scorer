import 'projection.dart';
import 'store.dart';

/// What happened to a match's copies.
enum Outcome {
  /// Replayed and stored.
  stored,

  /// The stored copy already comes from a newer save: left alone.
  alreadyNewer,

  /// The match is gone, so its copies were removed.
  removed,

  /// The match could not be read; its last good copies stay.
  unreadable,
}

/// Keeps each match's stored copies in step with the match.
class Projector {
  Projector(this._store, {DateTime Function()? now, void Function(Map<String, Object?>)? log})
      : _now = now ?? DateTime.now,
        _log = log ?? ((_) {});

  final MatchStore _store;
  final DateTime Function() _now;
  final void Function(Map<String, Object?>) _log;

  /// Writers that kept replacing the copy this many times in a row are left
  /// to it: one of them stored the newest save.
  static const _attempts = 4;

  /// Brings the copies of match [id] up to date with what is saved now.
  ///
  /// Called for every write, which may arrive twice or out of order, so it
  /// never trusts the caller's idea of the match: it reads the match as it
  /// is, and replaces a copy only with one made from a newer save.
  Future<Outcome> project(String id) async {
    for (var attempt = 1;; attempt++) {
      final match = await _store.readMatch(id);
      if (match == null) {
        await _store.deleteCopies(id);
        _log({'message': 'removed', 'matchId': id});
        return Outcome.removed;
      }
      try {
        return await _replace(match);
      } on CopyChanged {
        if (attempt == _attempts) rethrow;
      }
    }
  }

  /// Stores copies of a match already read, as [project] does. A rebuild
  /// uses it for each match of a page.
  Future<Outcome> projectRead(SourceMatch match) async {
    try {
      return await _replace(match);
    } on CopyChanged {
      // A live write got there first; do it properly from the top.
      return project(match.id);
    }
  }

  Future<Outcome> _replace(SourceMatch match) async {
    final MatchCopies copies;
    final watch = Stopwatch()..start();
    try {
      copies = copiesOf(match.data, sourceUpdateTime: match.updateTime, now: _now());
    } on Object catch (e) {
      _log({'severity': 'ERROR', 'message': 'unreadable', 'matchId': match.id, 'error': '$e'});
      return Outcome.unreadable;
    }
    final replayMs = watch.elapsedMilliseconds;
    final seen = await _store.readCopy(match.id);
    final from = seen?.sourceUpdateTime;
    if (from != null && DateTime.parse(from).isAfter(DateTime.parse(match.updateTime))) {
      _log({'message': 'already newer', 'matchId': match.id});
      return Outcome.alreadyNewer;
    }
    await _store.writeCopies(match.id, card: copies.card, view: copies.view, seen: seen);
    _log({
      'message': 'stored',
      'matchId': match.id,
      'seq': copies.card['seq'],
      'replayMs': replayMs,
      'totalMs': watch.elapsedMilliseconds,
    });
    return Outcome.stored;
  }
}
