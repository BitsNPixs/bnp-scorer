import 'package:bnp_scorer/data/local_team_repository.dart';
import 'package:bnp_scorer/data/team_repository.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Team _team(String id, String name, List<String> players) => Team(
      id: id,
      name: name,
      players: [for (final p in players) Player(id: '$id-$p', name: p)],
    );

Future<LocalTeamRepository> _repository([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return LocalTeamRepository(await SharedPreferences.getInstance());
}

void main() {
  group('LocalTeamRepository', () {
    test('saves and lists teams by name', () async {
      final repo = await _repository();
      await repo.save(_team('2', 'zebras', ['A', 'B']));
      await repo.save(_team('1', 'Ammapet', ['C', 'D']));

      final teams = await repo.loadAll();
      expect(teams.map((t) => t.name), ['Ammapet', 'zebras']);
      expect(teams.first.players.map((p) => p.id), ['1-C', '1-D']);
    });

    test('re-saving a team updates it without duplicating it', () async {
      final repo = await _repository();
      await repo.save(_team('1', 'Old name', ['A', 'B']));
      await repo.save(_team('1', 'New name', ['A', 'B', 'C']));

      final teams = await repo.loadAll();
      expect(teams, hasLength(1));
      expect(teams.single.name, 'New name');
      expect(teams.single.players, hasLength(3));
    });

    test('delete removes the team', () async {
      final repo = await _repository();
      await repo.save(_team('1', 'Team', ['A', 'B']));
      await repo.delete('1');
      expect(await repo.loadAll(), isEmpty);
    });

    test('a corrupt record is skipped instead of breaking the list', () async {
      final repo = await _repository({
        'bnp_scorer.teamIds': ['bad'],
        'bnp_scorer.team.bad': '{not json',
      });
      expect(await repo.loadAll(), isEmpty);
    });
  });

  group('mergeIntoSquad', () {
    test('a new team is saved as played', () {
      final squad = mergeIntoSquad([], _team('1', 'New', ['A', 'B']))!;
      expect(squad.id, '1');
      expect(squad.players.map((p) => p.name), ['A', 'B']);
    });

    test('players who sat out stay in the squad, newcomers join the end', () {
      final saved = _team('1', 'Team', ['A', 'B', 'C']);
      final played = Team(id: '1', name: 'Team', players: const [
        Player(id: '1-A', name: 'A'),
        Player(id: '1-B', name: 'B'),
        Player(id: 'new', name: 'D'),
      ]);
      expect(mergeIntoSquad([saved], played)!.players.map((p) => p.name), ['A', 'B', 'C', 'D']);
    });

    test('renaming a saved team keeps it the same team', () {
      final saved = _team('1', 'Old', ['A', 'B']);
      final squad = mergeIntoSquad([saved], Team(id: '1', name: 'New', players: saved.players))!;
      expect(squad.id, '1');
      expect(squad.name, 'New');
    });

    test('typing a saved name reuses that team and its player ids', () {
      final saved = _team('1', 'Team A', ['A', 'B']);
      final squad = mergeIntoSquad([saved], _team('typed', 'team a', ['A', 'C']))!;
      expect(squad.id, '1');
      expect(squad.players.map((p) => p.id), ['1-A', '1-B', 'typed-C']);
    });

    test('the id wins over a name match', () {
      final other = _team('2', 'Same', ['X', 'Y']);
      final mine = _team('1', 'Mine', ['A', 'B']);
      final squad = mergeIntoSquad([other, mine], Team(id: '1', name: 'Same', players: mine.players))!;
      expect(squad.id, '1');
    });

    test('a member linked to a number takes the shared id, keeping name, role and jobs', () {
      final saved = Team(
        id: '1',
        name: 'Team A',
        players: const [Player(id: '1-A', name: 'A'), Player(id: '1-B', name: 'B', role: PlayerRole.bowler)],
        captainId: '1-B',
        keeperId: '1-B',
      );
      final played = Team(
        id: '1',
        name: 'Team A',
        players: const [Player(id: '1-A', name: 'A'), Player(id: 'global', name: 'B')],
      );
      final squad = mergeIntoSquad([saved], played, sameAs: {'1-B': 'global'})!;
      expect(squad.players.map((p) => p.id), ['1-A', 'global']);
      expect(squad.players.last.name, 'B');
      expect(squad.players.last.role, PlayerRole.bowler);
      expect(squad.captainId, 'global');
      expect(squad.keeperId, 'global');
      // Without the link, the same names keep their old ids as before.
      expect(mergeIntoSquad([saved], played)!.players.map((p) => p.id), ['1-A', '1-B']);
    });

    test("a saved team's logo is kept, and a new team's comes along", () {
      final saved = Team(id: '1', name: 'Team A', players: _team('1', 'Team A', ['A', 'B']).players, logoUrl: 'logo-1');
      expect(mergeIntoSquad([saved], _team('1', 'Team A', ['A', 'C']))!.logoUrl, 'logo-1');
      final fresh = Team(id: '2', name: 'New', players: _team('2', 'New', ['A', 'B']).players, logoUrl: 'logo-2');
      expect(mergeIntoSquad([], fresh)!.logoUrl, 'logo-2');
    });

    test('Fill to 11 placeholders are not kept', () {
      final filled = _team('1', 'Team', [placeholderPlayerName(1), placeholderPlayerName(2)]);
      expect(mergeIntoSquad([], filled), isNull);

      final mixed = _team('2', 'Mixed', ['A', 'B', placeholderPlayerName(1)]);
      expect(mergeIntoSquad([], mixed)!.players.map((p) => p.name), ['A', 'B']);
    });

    test('a name like Playerson is not mistaken for a placeholder', () {
      final squad = mergeIntoSquad([], _team('1', 'Team', ['Playerson', 'Player One']))!;
      expect(squad.players, hasLength(2));
    });
  });
}
