// BNP Scorer's server (docs/ROADMAP.md "Website and API"), one image run as
// two Cloud Run services, chosen by ROLE:
//
// - projector (private): Firestore calls it whenever a match is saved; it
//   replays the match with the cricket engine and stores its copies.
// - api (public): serves those copies, read-only, with an account that
//   cannot write. The internet never reaches the service that writes.
import 'dart:convert';
import 'dart:io';

import 'package:bnp_api/api.dart';
import 'package:bnp_api/projector.dart';
import 'package:bnp_api/reads.dart';
import 'package:bnp_api/server.dart';
import 'package:bnp_api/store.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  void log(Map<String, Object?> entry) => stdout.writeln(jsonEncode(entry));

  final role = Platform.environment['ROLE'];
  if (role != 'projector' && role != 'api') {
    // Never guess: the wrong guess would put the writer on the internet.
    stderr.writeln('ROLE must be "projector" or "api", not "$role".');
    exit(64);
  }
  final project = Platform.environment['PROJECT_ID'] ?? 'bnp-scorer';
  // The Cloud Run service's own account signs every Firestore request.
  final client = await clientViaApplicationDefaultCredentials(scopes: [FirestoreApi.datastoreScope]);
  final firestore = FirestoreApi(client);

  final Handler handler;
  if (role == 'projector') {
    final store = FirestoreMatchStore(firestore, project);
    handler = projectorHandler(Projector(store, log: log), store, log: log);
  } else {
    handler = apiHandler(FirestoreMatchReads(firestore, project), log: log);
  }

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  log({'message': 'listening', 'role': role, 'port': port});
}
