import 'dart:convert';

import 'package:bnp_api/projector.dart';
import 'package:bnp_api/server.dart';
import 'package:bnp_api/store.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support.dart';

class _BrokenStore extends FakeMatchStore {
  @override
  Future<SourceMatch?> readMatch(String id) => throw StateError('Firestore is down');
}

void main() {
  late FakeMatchStore store;
  late Handler handler;

  Future<(int, Map<String, Object?>)> send(String method, String path, {Map<String, String>? headers}) async {
    final response = await handler(Request(method, Uri.parse('http://server$path'), headers: headers));
    return (response.statusCode, jsonDecode(await response.readAsString()) as Map<String, Object?>);
  }

  setUp(() {
    store = FakeMatchStore();
    handler = projectorHandler(Projector(store), store);
  });

  test('only a match document names a match', () {
    expect(matchIdOf('matches/abc'), 'abc');
    expect(matchIdOf('documents/matches/abc'), 'abc');
    expect(matchIdOf('teams/t1/joins/matches'), isNull);
    expect(matchIdOf('matches/abc/notes/n1'), isNull);
    expect(matchIdOf('matches/'), isNull);
    expect(matchIdOf('tournaments/abc'), isNull);
    expect(matchIdOf(null), isNull);
  });

  test('a Firestore event stores the match it names', () async {
    store.save('m1', matchDoc(), '2026-11-27T10:05:01Z');
    final (status, body) = await send('POST', '/', headers: {'ce-document': 'matches/m1'});
    expect(status, 200);
    expect(body, {'outcome': 'stored'});
    expect(store.views.keys, ['m1']);
  });

  test('an event for a deleted match removes its copies', () async {
    store.rivalCopy('gone', '2026-11-27T10:05:01Z');
    final (status, body) = await send('POST', '/', headers: {'ce-subject': 'documents/matches/gone'});
    expect(status, 200);
    expect(body, {'outcome': 'removed'});
    expect(store.views, isEmpty);
  });

  test('an event about anything else is ignored', () async {
    for (final headers in [{'ce-document': 'teams/t1'}, <String, String>{}]) {
      final (status, body) = await send('POST', '/', headers: headers);
      expect(status, 200);
      expect(body, {'ignored': true});
    }
    expect(store.views, isEmpty);
  });

  test('an unreadable match answers 200, so it is not sent again for ever', () async {
    store.save('m1', matchDoc(schema: 99), '2026-11-27T10:05:01Z');
    final (status, body) = await send('POST', '/', headers: {'ce-document': 'matches/m1'});
    expect(status, 200);
    expect(body, {'outcome': 'unreadable'});
  });

  test('a failure answers 500, so the event is sent again', () async {
    final broken = _BrokenStore();
    final logs = <Map<String, Object?>>[];
    handler = projectorHandler(Projector(broken), broken, log: logs.add);
    final (status, body) = await send('POST', '/', headers: {'ce-document': 'matches/m1'});
    expect(status, 500);
    expect(body, {'error': 'failed'}, reason: 'no details leave the server');
    expect(logs.single['error'], contains('Firestore is down'));
  });

  test('a rebuild stores every match, a page at a time', () async {
    for (var i = 0; i < 60; i++) {
      store.save('m$i', matchDoc(id: 'm$i'), '2026-11-27T10:05:01Z');
    }
    store.save('bad', matchDoc(id: 'bad', schema: 99), '2026-11-27T10:05:01Z');
    final (_, first) = await send('POST', '/rebuild');
    expect(first['stored'], 50);
    expect(first['nextPageToken'], '50');
    final (_, second) = await send('POST', '/rebuild?pageToken=50');
    expect(second['stored'], 10);
    expect(second['unreadable'], 1);
    expect(second['nextPageToken'], isNull);
    expect(store.views.length, 60);
  });

  test('health and unknown paths', () async {
    final (status, body) = await send('GET', '/');
    expect(status, 200);
    expect(body, {'ok': true});
    expect((await send('GET', '/rebuild')).$1, 404);
    expect((await send('POST', '/nothing')).$1, 404);
  });
}
