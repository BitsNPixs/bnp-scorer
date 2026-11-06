import 'package:bnp_scorer/data/team_repository.dart';
import 'package:bnp_scorer/screens/new_match_screen.dart';
import 'package:bnp_scorer/screens/team_edit_screen.dart';
import 'package:bnp_scorer/screens/teams_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/format.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

Team _team() => Team(
      id: 't',
      name: 'Alpha',
      players: const [
        Player(id: 'p1', name: 'Asha'),
        Player(id: 'p2', name: 'Bilal'),
        Player(id: 'p3', name: 'Chitra'),
      ],
      captainId: 'p1',
    );

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  late InMemoryTeamRepository teams;
  late InMemoryMatchRepository matches;

  setUp(() {
    teams = InMemoryTeamRepository();
    matches = InMemoryMatchRepository();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view
      ..physicalSize = const Size(1080, 4000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        teamRepositoryProvider.overrideWithValue(teams),
        matchRepositoryProvider.overrideWithValue(matches),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    ));
    await settle(tester);
  }

  /// Opens a route over a blank page, so the editor can pop back.
  Future<void> openEditor(WidgetTester tester, [Team? team]) async {
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => TeamEditScreen(team: team)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> addPlayer(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField).last, name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(_settle);
  }

  testWidgets('the list shows squads and captains', (tester) async {
    await teams.save(_team());
    await pump(tester, const TeamsScreen());
    expect(find.text('3 players · Captain: Asha'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new team needs a name and two players', (tester) async {
    await openEditor(tester);
    expect(find.text('Give the team a name'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Fresh');
    await tester.pump(_settle);
    expect(find.text('Add at least 2 players'), findsOneWidget);

    await addPlayer(tester, 'Asha');
    await addPlayer(tester, 'Bilal');
    await tester.tap(find.text('Save team'));
    await settle(tester);

    final saved = teams.teams.values.single;
    expect(saved.name, 'Fresh');
    expect(saved.players.map((p) => p.name), ['Asha', 'Bilal']);
  });

  testWidgets('a duplicate name is refused', (tester) async {
    await teams.save(_team());
    await openEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'alpha');
    await tester.pump(_settle);
    expect(find.text('There is already a team called alpha'), findsOneWidget);
  });

  testWidgets('roles and leaders are set from the player sheet', (tester) async {
    await teams.save(_team());
    await openEditor(tester, _team());

    await tester.tap(find.text('Bilal'));
    await settle(tester);
    await tester.tap(find.text('All-rounder'));
    await settle(tester);

    await tester.tap(find.text('Bilal'));
    await settle(tester);
    await tester.tap(find.text('Make wicket-keeper'));
    await settle(tester);

    await tester.tap(find.text('Chitra'));
    await settle(tester);
    await tester.tap(find.text('Make captain'));
    await settle(tester);

    await tester.tap(find.text('Save team'));
    await settle(tester);

    final saved = teams.teams['t']!;
    expect(saved.captainId, 'p3');
    expect(saved.keeperId, 'p2');
    expect(saved.playerById('p2')!.role, PlayerRole.allRounder);
  });

  testWidgets('captain and vice-captain are different people', (tester) async {
    await teams.save(_team());
    await openEditor(tester, _team());
    await tester.tap(find.text('Asha'));
    await settle(tester);
    await tester.tap(find.text('Make vice-captain'));
    await settle(tester);
    await tester.tap(find.text('Save team'));
    await settle(tester);

    expect(teams.teams['t']!.viceCaptainId, 'p1');
    expect(teams.teams['t']!.captainId, isNull);
  });

  testWidgets('renaming keeps the id, so stats stay with the player', (tester) async {
    await teams.save(_team());
    await openEditor(tester, _team());
    await tester.tap(find.text('Bilal'));
    await settle(tester);
    await tester.tap(find.text('Rename'));
    await settle(tester);
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'Bilal K',
    );
    await tester.tap(find.text('Save'));
    await settle(tester);
    await tester.tap(find.text('Save team'));
    await settle(tester);

    expect(teams.teams['t']!.playerById('p2')!.name, 'Bilal K');
  });

  testWidgets('removing the captain clears the captaincy', (tester) async {
    await teams.save(_team());
    await openEditor(tester, _team());
    await tester.tap(find.text('Asha'));
    await settle(tester);
    await tester.tap(find.text('Remove from squad'));
    await settle(tester);
    await tester.tap(find.text('Save team'));
    await settle(tester);

    expect(teams.teams['t']!.players, hasLength(2));
    expect(teams.teams['t']!.captainId, isNull);
  });

  testWidgets('a failed save stays on the form', (tester) async {
    await teams.save(_team());
    await openEditor(tester, _team());
    teams.failSaves = true;
    await tester.tap(find.text('Save team'));
    await settle(tester);
    expect(find.textContaining('Could not save the team'), findsOneWidget);
    expect(find.text('Save team'), findsOneWidget);
  });

  testWidgets('a team can be deleted', (tester) async {
    await teams.save(_team());
    await openEditor(tester, _team());
    await tester.tap(find.byTooltip('Delete team'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(teams.teams, isEmpty);
  });

  testWidgets('a match keeps the captain, keeper and roles', (tester) async {
    final team = Team(
      id: 't',
      name: 'Alpha',
      players: const [
        Player(id: 'p1', name: 'Asha', role: PlayerRole.batter),
        Player(id: 'p2', name: 'Bilal'),
      ],
      captainId: 'p1',
      keeperId: 'p2',
    );
    await teams.save(team);
    await teams.save(Team(id: 'u', name: 'Bravo', players: const [
      Player(id: 'q1', name: 'Dev'),
      Player(id: 'q2', name: 'Esha'),
    ]));
    await pump(tester, const NewMatchScreen());
    await tester.tap(find.text('Saved teams').first);
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Alpha'));
    await settle(tester);
    await tester.tap(find.text('Saved teams').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Bravo'));
    await settle(tester);
    await tester.tap(find.text('Start match'));
    await settle(tester);

    final played = matches.records.values.single.setup.teamA;
    expect(played.captainId, 'p1');
    expect(played.keeperId, 'p2');
    expect(played.playerById('p1')!.role, PlayerRole.batter);
    expect(teams.teams['t']!.captainId, 'p1', reason: 'saving the squad keeps its leaders');
  });

  group('tags', () {
    final setup = MatchSetup(
      id: 'm',
      teamA: Team(
        id: 'a',
        name: 'A',
        players: const [Player(id: 'p', name: 'Asha'), Player(id: 'k', name: 'Kiran')],
        captainId: 'p',
        keeperId: 'k',
      ),
      teamB: Team(id: 'b', name: 'B', players: const [
        Player(id: 'x', name: 'X'),
        Player(id: 'y', name: 'Y'),
      ]),
      rules: MatchRules(oversPerInnings: 1),
      tossWinnerId: 'a',
      tossDecision: TossDecision.bat,
    );

    test('mark the captain and keeper only', () {
      expect(taggedPlayerName(setup, 'p'), 'Asha (c)');
      expect(taggedPlayerName(setup, 'k'), 'Kiran (wk)');
      expect(taggedPlayerName(setup, 'x'), 'X');
    });

    test('a captain who keeps wicket shows both', () {
      final both = MatchSetup(
        id: 'm',
        teamA: Team(id: 'a', name: 'A', players: const [
          Player(id: 'p', name: 'Asha'),
          Player(id: 'k', name: 'K'),
        ], captainId: 'p', keeperId: 'p'),
        teamB: setup.teamB,
        rules: setup.rules,
        tossWinnerId: 'a',
        tossDecision: TossDecision.bat,
      );
      expect(taggedPlayerName(both, 'p'), 'Asha (c & wk)');
    });
  });

  group('merging a squad', () {
    test('keeps leaders and roles when a player sits out', () {
      final saved = Team(
        id: 't',
        name: 'Alpha',
        players: const [
          Player(id: 'a', name: 'A', role: PlayerRole.bowler),
          Player(id: 'b', name: 'B'),
          Player(id: 'c', name: 'C'),
        ],
        captainId: 'a',
        viceCaptainId: 'b',
        keeperId: 'c',
      );
      final played = Team(id: 't', name: 'Alpha', players: const [
        Player(id: 'b', name: 'B'),
        Player(id: 'c', name: 'C'),
      ]);
      final merged = mergeIntoSquad([saved], played)!;
      expect(merged.captainId, 'a');
      expect(merged.viceCaptainId, 'b');
      expect(merged.keeperId, 'c');
      expect(merged.playerById('a')!.role, PlayerRole.bowler);
    });
  });

  test('players and teams read back, old records included', () {
    final team = _team();
    final back = Team.fromJson(team.toJson());
    expect(back.captainId, 'p1');
    final old = Team.fromJson(const {
      'id': 't',
      'name': 'Old',
      'players': [
        {'id': 'a', 'name': 'A'},
        {'id': 'b', 'name': 'B'},
      ],
    });
    expect(old.captainId, isNull);
    expect(old.players.first.role, isNull);
    expect(Player.fromJson(const Player(id: 'a', name: 'A', role: PlayerRole.bowler).toJson()).role,
        PlayerRole.bowler);
  });
}
