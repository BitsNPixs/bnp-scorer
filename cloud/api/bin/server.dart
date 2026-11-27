// TRIAL (2026-11-27): proves a Dart service on Cloud Run can be woken by a
// Firestore write, replay the match with cricket_engine and store the score.
// docs/ROADMAP.md "Website and API".
import 'dart:convert';
import 'dart:io';

import 'package:bnp_api/firestore_values.dart';
import 'package:bnp_api/projection.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

const _views = 'trialViews';

Future<void> main() async {
  final project = Platform.environment['PROJECT_ID'] ?? 'bnp-scorer';
  // On Cloud Run the service's own account signs requests. On a laptop with
  // no credentials, requests go unsigned: public reads work, writes do not.
  http.Client client;
  var signed = true;
  try {
    client = await clientViaApplicationDefaultCredentials(scopes: [FirestoreApi.datastoreScope]);
  } on Object {
    client = http.Client();
    signed = false;
  }
  final docs = FirestoreApi(client).projects.databases.documents;
  final root = 'projects/$project/databases/(default)/documents';

  Future<Map<String, Object?>> project_(String matchId, {required bool store}) async {
    final watch = Stopwatch()..start();
    final match = plainFields((await docs.get('$root/matches/$matchId')).fields);
    final card = scoreCard(match);
    final replayMs = watch.elapsedMilliseconds;
    final updatedAt = DateTime.tryParse(match['updatedAt'] as String? ?? '');
    final out = {
      ...card,
      'projectedAt': DateTime.now().toUtc().toIso8601String(),
      'delayMs': updatedAt == null ? null : DateTime.now().difference(updatedAt).inMilliseconds,
    };
    if (store) {
      // Triggers can arrive twice or out of order: never replace a newer copy.
      final name = '$root/$_views/$matchId';
      int? storedSeq;
      try {
        storedSeq = plainFields((await docs.get(name)).fields)['seq'] as int?;
      } on DetailedApiRequestError catch (e) {
        if (e.status != 404) rethrow;
      }
      if (storedSeq != null && storedSeq > (card['seq']! as int)) {
        stdout.writeln(jsonEncode({'message': 'skipped older', 'matchId': matchId, 'seq': card['seq']}));
        return out;
      }
      await docs.patch(Document(fields: typedFields(out)), name);
    }
    stdout.writeln(jsonEncode({
      'message': 'projected',
      'matchId': matchId,
      'seq': card['seq'],
      'stored': store,
      'replayMs': replayMs,
      'totalMs': watch.elapsedMilliseconds,
      'delayMs': out['delayMs'],
    }));
    return out;
  }

  Response json(Object? body, [int status = 200]) =>
      Response(status, body: jsonEncode(body), headers: {'content-type': 'application/json'});

  Future<Response> handle(Request request) async {
    final path = request.url.pathSegments;
    try {
      if (request.method == 'GET' && path.isEmpty) return json({'ok': true, 'signed': signed});
      // Eventarc: a Firestore write, named in the CloudEvent headers.
      if (request.method == 'POST' && path.isEmpty) {
        final doc = request.headers['ce-document'] ?? request.headers['ce-subject'] ?? '';
        final parts = doc.split('/');
        final at = parts.indexOf('matches');
        if (at < 0 || at + 1 >= parts.length) return json({'ignored': doc});
        try {
          await project_(parts[at + 1], store: true);
        } on DetailedApiRequestError catch (e) {
          if (e.status != 404) rethrow; // A deleted match: nothing to score.
        }
        return json({'ok': true});
      }
      if (request.method == 'GET' && path.length == 2 && path[0] == 'project') {
        return json(await project_(path[1], store: request.url.queryParameters['store'] == '1'));
      }
      if (request.method == 'GET' && path.length == 2 && path[0] == 'views') {
        return json(plainFields((await docs.get('$root/$_views/${path[1]}')).fields));
      }
      return json({'error': 'not found'}, 404);
    } on DetailedApiRequestError catch (e) {
      return json({'error': e.message}, e.status ?? 500);
    } on Object catch (e, stack) {
      stderr.writeln(jsonEncode({'severity': 'ERROR', 'message': '$e', 'stack': '$stack'}));
      return json({'error': '$e'}, 500);
    }
  }

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  await shelf_io.serve(handle, InternetAddress.anyIPv4, port);
  stdout.writeln(jsonEncode({'message': 'listening', 'port': port, 'signed': signed}));
}
