import 'package:cricket_engine/cricket_engine.dart';

/// The trial's read model: a match's score line, from replaying its balls
/// with the same engine the app uses. [doc] is a `matches/{id}` document.
Map<String, Object?> scoreCard(Map<String, Object?> doc) {
  final setup = MatchSetup.fromJson(doc['setup']! as Map<String, Object?>);
  final events = [
    for (final e in doc['events']! as List<Object?>) MatchEvent.fromJson(e! as Map<String, Object?>),
  ];
  final state = ScoringEngine.replay(setup, events);
  String teamName(String id) => id == setup.teamA.id ? setup.teamA.name : setup.teamB.name;
  return {
    'matchId': setup.id,
    'seq': events.length,
    'teamA': setup.teamA.name,
    'teamB': setup.teamB.name,
    'innings': [
      for (final innings in state.innings)
        {
          'team': teamName(innings.battingTeamId),
          'runs': innings.runs,
          'wickets': innings.wickets,
          'overs': innings.oversText,
        },
    ],
  };
}
