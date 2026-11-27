import 'dart:convert';

import 'package:bnp_api/api.dart';
import 'package:bnp_api/reads.dart';
import 'package:cricket_engine/cricket_engine.dart' show Json;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Stored copies in memory, newest first as given.
class FakeReads implements MatchReads {
  final views = <String, Json>{};
  var cardList = <Json>[];
  var reads = 0;
  Object? failure;
  ({int limit, List<String>? stages, String? before})? lastQuery;

  @override
  Future<Json?> view(String id) async {
    reads++;
    if (failure != null) throw failure!;
    return views[id];
  }

  @override
  Future<List<Json>> cards({required int limit, List<String>? stages, String? before}) async {
    reads++;
    lastQuery = (limit: limit, stages: stages, before: before);
    final from = before == null ? 0 : cardList.indexWhere((c) => c['sourceUpdateTime'] == before) + 1;
    return cardList
        .skip(from)
        .where((c) => stages == null || stages.contains(c['stage']))
        .take(limit)
        .toList();
  }
}

Json card(int n, {String stage = 'live'}) => {
      'id': 'm$n',
      'stage': stage,
      'status': 'Lions $n/0',
      'ownerUid': 'secret-uid',
      'ownerName': 'Aswin',
      'sourceUpdateTime': '2026-11-27T10:00:${(59 - n).toString().padLeft(2, '0')}Z',
    };

void main() {
  late FakeReads reads;
  late Handler handler;
  late DateTime now;

  Future<Response> get(String path, {String method = 'GET'}) async =>
      handler(Request(method, Uri.parse('https://api.example$path')));
  Future<Json> body(Response response) async => jsonDecode(await response.readAsString()) as Json;

  setUp(() {
    reads = FakeReads();
    now = DateTime.utc(2026, 11, 27, 12);
    handler = apiHandler(reads, now: () => now);
  });

  group('one match', () {
    test('is its stored view, without the server-only fields', () async {
      reads.views['m1'] = {...card(1), 'innings': <Object?>[]};
      final response = await get('/v1/matches/m1');
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'application/json; charset=utf-8');
      final json = await body(response);
      expect(json['status'], 'Lions 1/0');
      expect(json['ownerName'], 'Aswin');
      expect(json.containsKey('ownerUid'), isFalse);
    });

    test('in play may be reused for seconds; finished for minutes', () async {
      reads.views['live'] = card(1);
      reads.views['done'] = card(2, stage: 'finished');
      expect((await get('/v1/matches/live')).headers['cache-control'], 'public, max-age=$liveSeconds');
      expect((await get('/v1/matches/done')).headers['cache-control'], 'public, max-age=$finishedSeconds');
    });

    test('that does not exist is a 404, and so is an id that could not be one', () async {
      final missing = await get('/v1/matches/nope');
      expect(missing.statusCode, 404);
      expect(await body(missing), {'error': 'no such match'});
      final before = reads.reads;
      for (final bad in ['/v1/matches/a.b', '/v1/matches/${'x' * 65}', '/v1/matches/', '/v1/matches/a/b', '/v2/matches/a', '/']) {
        expect((await get(bad)).statusCode, 404, reason: bad);
      }
      expect(reads.reads, before, reason: 'none of them reached Firestore');
    });
  });

  group('the list', () {
    test('gives cards newest first and says where the next page starts', () async {
      reads.cardList = [for (var n = 0; n < 5; n++) card(n)];
      final first = await body(await get('/v1/matches?limit=2'));
      final matches = (first['matches']! as List<Object?>).cast<Json>();
      expect([for (final m in matches) m['id']], ['m0', 'm1']);
      expect(matches.first.containsKey('ownerUid'), isFalse);
      expect(first['next'], matches.last['sourceUpdateTime']);

      final next = Uri.encodeQueryComponent(first['next']! as String);
      final second = await body(await get('/v1/matches?limit=2&before=$next'));
      expect([for (final m in second['matches']! as List<Object?>) (m! as Json)['id']], ['m2', 'm3']);
      final last = await body(await get('/v1/matches?limit=2&before=${Uri.encodeQueryComponent(second['next']! as String)}'));
      expect([for (final m in last['matches']! as List<Object?>) (m! as Json)['id']], ['m4']);
      expect(last['next'], isNull, reason: 'a short page is the last');
    });

    test('asks for $defaultLimit cards unless told', () async {
      await get('/v1/matches');
      expect(reads.lastQuery!.limit, defaultLimit);
      expect(reads.lastQuery!.stages, isNull);
    });

    test('live means every stage but finished', () async {
      reads.cardList = [
        card(0, stage: 'starting'),
        card(1, stage: 'live'),
        card(2, stage: 'inningsBreak'),
        card(3, stage: 'finished'),
      ];
      final live = await body(await get('/v1/matches?state=live'));
      expect([for (final m in live['matches']! as List<Object?>) (m! as Json)['id']], ['m0', 'm1', 'm2']);
      final done = await body(await get('/v1/matches?state=finished'));
      expect([for (final m in done['matches']! as List<Object?>) (m! as Json)['id']], ['m3']);
    });

    test('refuses what it does not understand, without reading anything', () async {
      for (final bad in ['?limit=0', '?limit=51', '?limit=many', '?state=soon', '?before=', '?before=${'9' * 41}']) {
        final response = await get('/v1/matches$bad');
        expect(response.statusCode, 400, reason: bad);
        expect((await body(response))['error'], isA<String>());
      }
      expect(reads.reads, 0);
    });
  });

  group('kept answers', () {
    test('a crowd in the same few seconds costs one read', () async {
      reads.views['m1'] = card(1);
      for (var i = 0; i < 20; i++) {
        await get('/v1/matches/m1');
      }
      expect(reads.reads, 1);
      now = now.add(const Duration(seconds: 3));
      expect((await get('/v1/matches/m1')).headers['cache-control'], 'public, max-age=${liveSeconds - 3}',
          reason: 'only what is left of its time');
      now = now.add(const Duration(seconds: liveSeconds));
      reads.views['m1'] = {...card(1), 'status': 'Lions 7/0'};
      expect((await body(await get('/v1/matches/m1')))['status'], 'Lions 7/0');
      expect(reads.reads, 2);
    });

    test('a made-up parameter does not get past them', () async {
      reads.views['m1'] = card(1);
      await get('/v1/matches/m1?x=1');
      await get('/v1/matches/m1?x=2');
      await get('/v1/matches?junk=1');
      await get('/v1/matches?junk=2');
      expect(reads.reads, 2, reason: 'one for the match, one for the list');
    });

    test('a missing match is kept too', () async {
      await get('/v1/matches/nope');
      await get('/v1/matches/nope');
      expect(reads.reads, 1);
    });

    test('a failure is told plainly and never kept', () async {
      final logs = <Map<String, Object?>>[];
      handler = apiHandler(reads, now: () => now, log: logs.add);
      reads.failure = StateError('Firestore is down');
      final failed = await get('/v1/matches/m1');
      expect(failed.statusCode, 500);
      expect(await body(failed), {'error': 'failed'}, reason: 'no details leave the server');
      expect(failed.headers['cache-control'], 'no-store');
      expect(logs.single['error'], contains('Firestore is down'));
      reads
        ..failure = null
        ..views['m1'] = card(1);
      expect((await get('/v1/matches/m1')).statusCode, 200);
    });
  });

  group('other sites and other methods', () {
    test('any site may read it', () async {
      reads.views['m1'] = card(1);
      expect((await get('/v1/matches/m1')).headers['access-control-allow-origin'], '*');
      final preflight = await get('/v1/matches/m1', method: 'OPTIONS');
      expect(preflight.statusCode, 204);
      expect(preflight.headers['access-control-allow-methods'], 'GET, OPTIONS');
    });

    test('nothing can be changed through it', () async {
      for (final method in ['POST', 'PUT', 'PATCH', 'DELETE']) {
        final response = await get('/v1/matches/m1', method: method);
        expect(response.statusCode, 405, reason: method);
        expect(response.headers['allow'], 'GET, OPTIONS');
      }
      expect((await get('/rebuild', method: 'POST')).statusCode, 405, reason: 'the writer is another service');
      expect(reads.reads, 0);
    });
  });
}
