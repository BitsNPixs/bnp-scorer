import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accounts.dart';
import 'cloud_matches.dart';
import 'match_repository.dart';

/// The accounts on this phone whose published matches were sent again.
const playerIdsBackfillKey = 'bnp_scorer.playerIdsBackfill';

/// Sends every match [scorer] published from this phone once more, so ones
/// published before `playerIds` existed show on player profiles. Runs once
/// per account per phone; a failure leaves it to run again next launch.
Future<void> republishForPlayerIds({
  required SharedPreferences prefs,
  required MatchRepository local,
  required CloudMatches cloud,
  required Scorer scorer,
}) async {
  final done = prefs.getStringList(playerIdsBackfillKey) ?? const <String>[];
  if (done.contains(scorer.uid)) return;
  try {
    for (final record in await local.loadAll()) {
      if (record.publishedBy == scorer.uid) await cloud.publish(record, scorer);
    }
    await prefs.setStringList(playerIdsBackfillKey, [...done, scorer.uid]);
  } on Object catch (e) {
    debugPrint('Sending published matches again failed: $e');
  }
}

/// Runs [republishForPlayerIds] whenever a scorer is signed in, now or later.
StreamSubscription<Scorer?> backfillPlayerIdsOnSignIn({
  required Accounts accounts,
  required SharedPreferences prefs,
  required MatchRepository local,
  required CloudMatches cloud,
}) =>
    accounts.changes.listen((scorer) {
      if (scorer != null) {
        unawaited(republishForPlayerIds(prefs: prefs, local: local, cloud: cloud, scorer: scorer));
      }
    });
