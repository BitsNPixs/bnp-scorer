// BNP Scorer's server (docs/ROADMAP.md "Website and API"). Firestore calls it
// whenever a match is saved; it replays the match with the cricket engine
// and stores the copies the API and website read.
import 'dart:convert';
import 'dart:io';

import 'package:bnp_api/projector.dart';
import 'package:bnp_api/server.dart';
import 'package:bnp_api/store.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  void log(Map<String, Object?> entry) => stdout.writeln(jsonEncode(entry));

  final project = Platform.environment['PROJECT_ID'] ?? 'bnp-scorer';
  // The Cloud Run service's own account signs every Firestore request.
  final client = await clientViaApplicationDefaultCredentials(scopes: [FirestoreApi.datastoreScope]);
  final store = FirestoreMatchStore(FirestoreApi(client), project);
  final handler = projectorHandler(Projector(store, log: log), store, log: log);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  log({'message': 'listening', 'port': port});
}
