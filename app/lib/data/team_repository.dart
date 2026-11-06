import 'package:cricket_engine/cricket_engine.dart';

/// Storage boundary for saved squads, kept apart from matches. A match holds
/// its own copy of the teams, so editing a squad never changes past scorecards.
abstract interface class TeamRepository {
  /// Sorted by name. Unreadable records are skipped.
  Future<List<Team>> loadAll();

  Future<void> save(Team team);

  Future<void> delete(String id);
}

final _placeholderName = RegExp(r'^Player \d+$');

/// The stand-in name "Fill to 11" gives a player.
String placeholderPlayerName(int number) => 'Player $number';

/// The squad to store after [played] takes the field, or null if there is
/// nothing worth keeping. Everyone in the saved squad stays, including players
/// who sat this match out, and newcomers join at the end. A team typed with a
/// saved team's name is treated as that team.
Team? mergeIntoSquad(List<Team> saved, Team played) {
  final name = played.name.toLowerCase();
  final existing = saved.where((t) => t.id == played.id).firstOrNull ??
      saved.where((t) => t.name.toLowerCase() == name).firstOrNull;
  final squad = <Player>[...?existing?.players];
  bool inSquad(Player p) => squad.any((s) => s.id == p.id || s.name == p.name);
  for (final player in played.players) {
    if (!_placeholderName.hasMatch(player.name) && !inSquad(player)) squad.add(player);
  }
  if (squad.length < 2) return null;
  return Team(
    id: existing?.id ?? played.id,
    name: played.name,
    players: squad,
    captainId: existing?.captainId ?? played.captainId,
    viceCaptainId: existing?.viceCaptainId ?? played.viceCaptainId,
    keeperId: existing?.keeperId ?? played.keeperId,
  );
}
