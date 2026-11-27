import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'projector.dart';
import 'store.dart';

Response _json(Object? body, [int status = 200]) =>
    Response(status, body: jsonEncode(body), headers: {'content-type': 'application/json'});

/// The match id in a Firestore event's document path
/// ("matches/abc" or "documents/matches/abc"), or null for anything else.
String? matchIdOf(String? document) {
  final parts = (document ?? '').split('/');
  final at = parts.indexOf('matches');
  if (at < 0 || at != parts.length - 2 || parts.last.isEmpty) return null;
  return parts.last;
}

/// The private service Firestore calls when a match is saved.
///
/// - `POST /` is the Eventarc trigger: the CloudEvent's `ce-document` header
///   names the match; the body (protobuf) is not read.
/// - `POST /rebuild` re-stores one page of all matches, for a new view
///   version; pass the returned `nextPageToken` until there is none.
Handler projectorHandler(Projector projector, MatchStore store, {void Function(Map<String, Object?>)? log}) {
  return (Request request) async {
    final path = request.url.pathSegments;
    try {
      if (request.method == 'GET' && path.isEmpty) return _json({'ok': true});
      if (request.method == 'POST' && path.isEmpty) {
        final id = matchIdOf(request.headers['ce-document'] ?? request.headers['ce-subject']);
        if (id == null) return _json({'ignored': true});
        // An unreadable match answers 200 too: sending it again cannot help.
        return _json({'outcome': (await projector.project(id)).name});
      }
      if (request.method == 'POST' && path.length == 1 && path[0] == 'rebuild') {
        final page = await store.listMatches(pageToken: request.url.queryParameters['pageToken']);
        final counts = {for (final outcome in Outcome.values) outcome.name: 0};
        for (final match in page.matches) {
          final outcome = await projector.projectRead(match);
          counts[outcome.name] = counts[outcome.name]! + 1;
        }
        return _json({...counts, 'nextPageToken': page.nextPageToken});
      }
      return _json({'error': 'not found'}, 404);
    } on Object catch (e, stack) {
      // A 500 makes Eventarc send the event again later.
      log?.call({'severity': 'ERROR', 'message': 'failed', 'error': '$e', 'stack': '$stack'});
      return _json({'error': 'failed'}, 500);
    }
  };
}
