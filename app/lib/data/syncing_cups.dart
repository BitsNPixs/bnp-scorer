import 'package:cricket_engine/cricket_engine.dart';

import 'accounts.dart';
import 'cloud_cups.dart';
import 'scheduled_match.dart';
import 'syncing_match_repository.dart';
import 'tournament_repository.dart';

/// The organiser's published tournaments, kept on the phone and sent to the
/// cloud, like [SyncingMatchRepository]. Only one created while signed in
/// (`publishedBy`) is sent, by that account, and never with its payments.
class SyncingTournamentRepository implements TournamentRepository {
  SyncingTournamentRepository(this._local, this._cloud, this._accounts);

  final TournamentRepository _local;
  final CloudCups _cloud;
  final Accounts _accounts;

  @override
  Future<List<Tournament>> loadAll() => _local.loadAll();

  @override
  Future<void> save(Tournament tournament) async {
    await _local.save(tournament);
    final owner = publisherOf(_accounts, tournament.publishedBy);
    if (owner != null) {
      sendInBackground(_cloud.publishTournament(tournament, owner), 'Publishing tournament ${tournament.id}');
    }
  }

  @override
  Future<void> delete(String id) async {
    final tournament = (await _local.loadAll()).where((t) => t.id == id).firstOrNull;
    await _local.delete(id);
    if (tournament != null && publisherOf(_accounts, tournament.publishedBy) != null) {
      sendInBackground(_cloud.unpublishTournament(id), 'Unpublishing tournament $id');
    }
  }
}

/// Scheduled friendlies, the same way.
class SyncingScheduleRepository implements ScheduleRepository {
  SyncingScheduleRepository(this._local, this._cloud, this._accounts);

  final ScheduleRepository _local;
  final CloudCups _cloud;
  final Accounts _accounts;

  @override
  Future<List<ScheduledMatch>> loadAll() => _local.loadAll();

  @override
  Future<void> save(ScheduledMatch match) async {
    await _local.save(match);
    final owner = publisherOf(_accounts, match.publishedBy);
    if (owner != null) sendInBackground(_cloud.publishSchedule(match, owner), 'Publishing schedule ${match.id}');
  }

  @override
  Future<void> delete(String id) async {
    final match = (await _local.loadAll()).where((s) => s.id == id).firstOrNull;
    await _local.delete(id);
    if (match != null && publisherOf(_accounts, match.publishedBy) != null) {
      sendInBackground(_cloud.unpublishSchedule(id), 'Unpublishing schedule $id');
    }
  }
}
