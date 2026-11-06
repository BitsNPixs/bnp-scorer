import 'dart:convert';

import 'package:cricket_engine/cricket_engine.dart';

import 'match_record.dart';
import 'match_repository.dart';
import 'team_repository.dart';
import 'tournament_repository.dart';

const _appName = 'bnp_scorer';
const _version = 1;

/// Everything worth keeping, as one document. Stats are left out because they
/// are derived from the matches.
class Backup {
  const Backup({required this.matches, required this.teams, required this.tournaments});

  final List<MatchRecord> matches;
  final List<Team> teams;
  final List<Tournament> tournaments;

  bool get isEmpty => matches.isEmpty && teams.isEmpty && tournaments.isEmpty;

  /// "12 matches, 4 teams and 2 tournaments".
  String get summary => _summary(matches.length, teams.length, tournaments.length);

  String encode(DateTime now) => jsonEncode({
        'app': _appName,
        'version': _version,
        'exportedAt': now.toUtc().toIso8601String(),
        'matches': [for (final m in matches) m.toJson()],
        'teams': [for (final t in teams) t.toJson()],
        'tournaments': [for (final t in tournaments) t.toJson()],
      });

  /// Reads a whole backup or none of it. Throws [FormatException] with a message
  /// for the scorer, so a bad file cannot leave half a restore behind.
  factory Backup.decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('That file is not a BNP Scorer backup.');
    }
    if (json is! Map<String, Object?> || json['app'] != _appName) {
      throw const FormatException('That file is not a BNP Scorer backup.');
    }
    final version = json['version'];
    if (version is! int || version > _version) {
      throw const FormatException('This backup is from a newer app. Update the app first.');
    }
    try {
      return Backup(
        matches: [
          for (final m in json['matches']! as List<Object?>) MatchRecord.fromJson(m! as Json),
        ],
        teams: [
          for (final t in json['teams']! as List<Object?>) Team.fromJson(t! as Json),
        ],
        tournaments: [
          for (final t in json['tournaments']! as List<Object?>) Tournament.fromJson(t! as Json),
        ],
      );
    } on Object {
      throw const FormatException('This backup is damaged, so nothing was restored.');
    }
  }
}

String _summary(int matches, int teams, int tournaments) {
  String count(int n, String word) => '$n $word${n == 1 ? '' : (word.endsWith('ch') ? 'es' : 's')}';
  return '${count(matches, 'match')}, ${count(teams, 'team')} and ${count(tournaments, 'tournament')}';
}

Future<Backup> collectBackup(
  MatchRepository matches,
  TeamRepository teams,
  TournamentRepository tournaments,
) async =>
    Backup(
      matches: await matches.loadAll(),
      teams: await teams.loadAll(),
      tournaments: await tournaments.loadAll(),
    );

/// What a restore changed.
class RestoreResult {
  const RestoreResult({required this.matches, required this.teams, required this.tournaments});

  final int matches;
  final int teams;
  final int tournaments;

  bool get addedNothing => matches + teams + tournaments == 0;

  String get summary => _summary(matches, teams, tournaments);
}

/// Adds whatever the device does not have. Anything already here is kept, so a
/// restore can never undo newer scoring, and running it twice changes nothing.
Future<RestoreResult> restoreBackup(
  Backup backup,
  MatchRepository matches,
  TeamRepository teams,
  TournamentRepository tournaments,
) async {
  final existingMatches = {for (final m in await matches.loadAll()) m.id};
  final existingTeams = {for (final t in await teams.loadAll()) t.id};
  final existingTournaments = {for (final t in await tournaments.loadAll()) t.id};

  final newMatches = backup.matches.where((m) => !existingMatches.contains(m.id)).toList();
  final newTeams = backup.teams.where((t) => !existingTeams.contains(t.id)).toList();
  final newTournaments = backup.tournaments.where((t) => !existingTournaments.contains(t.id)).toList();

  for (final record in newMatches) {
    await matches.save(record);
  }
  for (final team in newTeams) {
    await teams.save(team);
  }
  for (final tournament in newTournaments) {
    await tournaments.save(tournament);
  }
  return RestoreResult(
    matches: newMatches.length,
    teams: newTeams.length,
    tournaments: newTournaments.length,
  );
}
