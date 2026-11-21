import 'package:cricket_engine/cricket_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accounts.dart';
import 'cloud_teams.dart';
import 'syncing_match_repository.dart';
import 'team_repository.dart';

/// Sharing a team's invite. Null without the cloud.
abstract interface class TeamSharing {
  /// True once this phone has shared the team's invite.
  bool isShared(String teamId);

  /// Publishes [team] so players can find it by its join code; from then on
  /// every save keeps the shared copy in step. Awaited, so the code works
  /// before the invite goes out. Throws when signed out or offline.
  Future<void> share(Team team);
}

/// Saved squads stay on the phone. A team whose invite was shared is also
/// kept in step in the cloud, by the account that shared it, like
/// [SyncingMatchRepository] does for matches.
class SyncingTeamRepository implements TeamRepository, TeamSharing {
  SyncingTeamRepository(this._local, this._cloud, this._accounts, this._prefs);

  /// The teams this phone has shared.
  static const sharedKey = 'bnp_scorer.sharedTeamIds';

  final TeamRepository _local;
  final CloudTeams _cloud;
  final Accounts _accounts;
  final SharedPreferences _prefs;

  List<String> get _shared => _prefs.getStringList(sharedKey) ?? const [];

  @override
  bool isShared(String teamId) => _shared.contains(teamId);

  @override
  Future<void> share(Team team) async {
    final scorer = _accounts.current;
    if (scorer == null) throw const AccountsException('Sign in from Settings to invite players.');
    await _cloud.publishTeam(team, scorer);
    if (!isShared(team.id)) await _prefs.setStringList(sharedKey, [..._shared, team.id]);
  }

  @override
  Future<List<Team>> loadAll() => _local.loadAll();

  @override
  Future<void> save(Team team) async {
    await _local.save(team);
    final scorer = _accounts.current;
    if (scorer != null && isShared(team.id)) {
      sendInBackground(_cloud.publishTeam(team, scorer), 'Updating shared team ${team.id}');
    }
  }

  @override
  Future<void> delete(String id) async {
    await _local.delete(id);
    if (!isShared(id)) return;
    await _prefs.setStringList(sharedKey, [for (final s in _shared) if (s != id) s]);
    if (_accounts.current != null) sendInBackground(_cloud.unpublishTeam(id), 'Unsharing team $id');
  }
}
