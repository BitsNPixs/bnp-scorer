import 'dart:convert';

import 'package:cricket_engine/cricket_engine.dart' show Json;
import 'package:match_view/match_view.dart' show MatchStage;
import 'package:shelf/shelf.dart';

import 'reads.dart';

/// How long an answer may be reused, in seconds. A match in play changes
/// with every ball; a finished one almost never does.
const liveSeconds = 5;
const finishedSeconds = 300;

/// A match that is not finished and has not been saved for this long is
/// "stopped", not "live": its scorer went home without ending it. One more
/// ball makes it live again.
const stoppedAfter = Duration(hours: 6);

/// What a match is doing now, which its stored `stage` alone cannot say,
/// because a copy does not change as time passes. Sent as `state`.
enum MatchNow { live, stopped, finished }

MatchNow matchNow(Json copy, DateTime now) {
  if (copy['stage'] == MatchStage.finished.name) return MatchNow.finished;
  final saved = DateTime.tryParse(copy['sourceUpdateTime'] as String? ?? '');
  if (saved != null && now.difference(saved) >= stoppedAfter) return MatchNow.stopped;
  return MatchNow.live;
}

/// The most cards one request may ask for.
const maxLimit = 50;
const defaultLimit = 20;

/// Kept on the copies for the server's own use, not part of the API.
const _private = {'ownerUid'};

final _matchId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

const _cors = {
  // Public, read-only data: any site may show it.
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, OPTIONS',
  'access-control-max-age': '86400',
};

Json _public(Json copy, DateTime now) => {
      for (final MapEntry(:key, :value) in copy.entries)
        if (!_private.contains(key)) key: value,
      'state': matchNow(copy, now).name,
    };

/// The stages a match that is not finished can be at.
final _openStages = [
  for (final stage in MatchStage.values)
    if (stage != MatchStage.finished) stage.name,
];

class _Answer {
  const _Answer(this.status, this.body, this.maxAge, this.madeAt);

  final int status;
  final String body;
  final int maxAge;
  final DateTime madeAt;

  Response toResponse(DateTime now) {
    final left = maxAge - now.difference(madeAt).inSeconds;
    return Response(status, body: body, headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'public, max-age=${left < 0 ? 0 : left}',
      ..._cors,
    });
  }
}

/// The public API (version 1), read-only, served from the stored copies.
///
/// - `GET /v1/matches?state=live|stopped|finished&limit=20&before=<cursor>`:
///   `{"matches": [card…], "next": cursor or null}`, newest save first.
/// - `GET /v1/matches/{id}`: the match's full view, or 404.
///
/// Every card and view carries `state` ([MatchNow]), worked out as it is
/// sent: a match nobody has scored for [stoppedAfter] is "stopped".
///
/// Shapes are `matchCard` and `matchView` (packages/match_view) plus what
/// the server adds. Paths and field names are a contract with the website
/// and anyone else: add, never rename; a breaking change is `/v2`.
///
/// Each answer is kept for a few seconds and reused, so a crowd watching one
/// match costs one Firestore read per [liveSeconds], not one per person.
Handler apiHandler(MatchReads reads, {DateTime Function()? now, void Function(Map<String, Object?>)? log}) {
  final clock = now ?? DateTime.now;
  final kept = <String, _Answer>{};
  const keptMost = 500;

  Future<_Answer> answer(Uri url) async {
    final path = url.pathSegments;
    final made = clock();
    _Answer json(Object? body, int maxAge, [int status = 200]) => _Answer(status, jsonEncode(body), maxAge, made);
    _Answer refuse(int status, String message) => json({'error': message}, liveSeconds, status);

    if (path.length == 2 && path[0] == 'v1' && path[1] == 'matches') {
      final query = url.queryParameters;
      final limit = int.tryParse(query['limit'] ?? '$defaultLimit');
      if (limit == null || limit < 1 || limit > maxLimit) return refuse(400, 'limit must be 1 to $maxLimit');
      final state = query['state'];
      if (state != null && !MatchNow.values.any((s) => s.name == state)) {
        return refuse(400, 'state must be live, stopped or finished');
      }
      final before = query['before'];
      if (before != null && (before.isEmpty || before.length > 40)) return refuse(400, 'before is not a cursor');
      final cutoff = made.subtract(stoppedAfter);
      final cards = await reads.cards(
        limit: limit,
        stages: switch (state) {
          null => null,
          'finished' => [MatchStage.finished.name],
          _ => _openStages,
        },
        savedSince: state == 'live' ? cutoff : null,
        savedBefore: state == 'stopped' ? cutoff : null,
        before: before,
      );
      return json({
        'matches': [for (final card in cards) _public(card, made)],
        // A full page may have more behind it.
        'next': cards.length < limit ? null : cards.last['sourceUpdateTime'],
      }, liveSeconds);
    }
    if (path.length == 3 && path[0] == 'v1' && path[1] == 'matches' && _matchId.hasMatch(path[2])) {
      final view = await reads.view(path[2]);
      if (view == null) return refuse(404, 'no such match');
      return json(_public(view, made), view['stage'] == MatchStage.finished.name ? finishedSeconds : liveSeconds);
    }
    return refuse(404, 'not found');
  }

  return (Request request) async {
    if (request.method == 'OPTIONS') return Response(204, headers: _cors);
    if (request.method != 'GET') {
      return Response(405, body: jsonEncode({'error': 'read-only'}), headers: {
        'content-type': 'application/json; charset=utf-8',
        'allow': 'GET, OPTIONS',
        ..._cors,
      });
    }
    final url = request.requestedUri;
    // Only what changes the answer, so a made-up parameter cannot dodge
    // the kept answers and reach Firestore every time.
    final asked = url.queryParameters;
    final key = url.path == '/v1/matches'
        ? '${url.path}?${asked['state']}&${asked['limit']}&${asked['before']}'
        : url.path;
    final at = clock();
    final held = kept[key];
    if (held != null && at.difference(held.madeAt).inSeconds < held.maxAge) return held.toResponse(at);
    try {
      final fresh = await answer(url);
      if (kept.length >= keptMost) kept.clear();
      kept[key] = fresh;
      return fresh.toResponse(at);
    } on Object catch (e, stack) {
      log?.call({'severity': 'ERROR', 'message': 'failed', 'path': url.path, 'error': '$e', 'stack': '$stack'});
      return Response(500, body: jsonEncode({'error': 'failed'}), headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        ..._cors,
      });
    }
  };
}
