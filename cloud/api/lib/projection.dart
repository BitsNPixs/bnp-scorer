import 'package:cricket_engine/cricket_engine.dart';
import 'package:match_view/match_view.dart';

/// The newest `matches/{id}` format this server reads (the app's
/// `FirestoreCloudMatches.schema`). A match saved by a newer app is left
/// alone until the server is updated.
const matchSchema = 1;

/// The two ready-to-read copies of one match: a card for lists and the full
/// view for a match page.
class MatchCopies {
  const MatchCopies({required this.card, required this.view});

  final Json card;
  final Json view;
}

/// Replays a `matches/{id}` document with the engine and builds its copies.
///
/// [sourceUpdateTime] is when Firestore last saved that document; it is kept
/// on the copies so an older save never replaces a newer one. Throws when the
/// match cannot be read: a newer [matchSchema], or data the engine refuses.
MatchCopies copiesOf(Json match, {required String sourceUpdateTime, required DateTime now}) {
  final schema = match['schema'];
  if (schema is int && schema > matchSchema) {
    throw FormatException('Match saved in schema $schema; this server reads up to $matchSchema.');
  }
  final setup = MatchSetup.fromJson(match['setup']! as Json);
  final events = [
    for (final e in match['events']! as List<Object?>) MatchEvent.fromJson(e! as Json),
  ];
  final state = ScoringEngine.replay(setup, events);
  final about = {
    // How many events the copy was made from. It goes down after an undo.
    'seq': events.length,
    'ownerUid': match['ownerUid'],
    'ownerName': match['ownerName'] as String? ?? 'A scorer',
    'createdAt': match['createdAt'],
    'updatedAt': match['updatedAt'],
    'sourceUpdateTime': sourceUpdateTime,
    'projectedAt': now.toUtc().toIso8601String(),
  };
  return MatchCopies(
    card: {
      ...matchCard(state),
      ...about,
      // For finding a player's matches, as on the match itself.
      'playerIds': [
        for (final team in [setup.teamA, setup.teamB])
          for (final player in team.players) player.id,
      ],
    },
    view: {...matchView(state), ...about},
  );
}
