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
  late TextShares files;

  setUp(() {
    teams = InMemoryTeamRepository();
    matches = InMemoryMatchRepository();
    files = TextShares();
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
        deviceFilesProvider.overrideWithValue(files),
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

  group('paste a list', () {
    Future<void> paste(WidgetTester tester, String list) async {
      final button = find.text('Paste a list');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('paste-list')), list);
      await tester.pump(_settle);
    }

    testWidgets('a WhatsApp list fills the squad with its captain and keeper', (tester) async {
      await openEditor(tester);
      await tester.enterText(find.byType(TextField).first, 'Warriors');
      await paste(tester, '1. Asha (c)\n2. Bilal (wk)\n3. Chitra 🏏\n4. Devi (vc)');

      expect(find.text('ADDING · 4'), findsOneWidget);
      expect(find.text('Asha · C'), findsOneWidget);
      expect(find.text('Bilal · WK'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Add 4 players'));
      await settle(tester);
      expect(find.text('SQUAD · 4'), findsOneWidget);
      expect(find.text('Captain'), findsOneWidget);
      expect(find.text('Wicket-keeper'), findsOneWidget);
      expect(find.text('Vice-captain'), findsOneWidget);

      await tester.tap(find.text('Save team'));
      await settle(tester);
      final saved = teams.teams.values.single;
      expect(saved.players.map((p) => p.name), ['Asha', 'Bilal', 'Chitra', 'Devi']);
      expect(saved.playerById(saved.captainId!)!.name, 'Asha');
      expect(saved.playerById(saved.keeperId!)!.name, 'Bilal');
      expect(saved.playerById(saved.viceCaptainId!)!.name, 'Devi');
    });

    testWidgets('names already in the squad are left out, and one can be taken off', (tester) async {
      await teams.save(_team());
      await openEditor(tester, _team());
      await paste(tester, 'asha\nBilal\nDevi\nEsha\nWarriors XI');

      expect(find.text('2 names already in the team, left out.'), findsOneWidget);
      expect(find.text('ADDING · 3'), findsOneWidget);

      // A heading that came along with the list.
      final heading = find.widgetWithText(InputChip, 'Warriors XI');
      await tester.tap(find.descendant(of: heading, matching: find.byIcon(Icons.clear)));
      await tester.pump(_settle);
      expect(find.text('ADDING · 2'), findsOneWidget);

      await tester.tap(find.text('Add 2 players'));
      await settle(tester);
      await tester.tap(find.text('Save team'));
      await settle(tester);
      final saved = teams.teams['t']!;
      expect(saved.players.map((p) => p.name), ['Asha', 'Bilal', 'Chitra', 'Devi', 'Esha']);
      expect(saved.players.first.id, 'p1', reason: 'old players keep their ids');
      expect(saved.captainId, 'p1');
    });

    testWidgets('a heading in a numbered list starts taken off and can come back', (tester) async {
      await openEditor(tester);
      await paste(tester, '*Warriors* 🏏\n1. Asha\n2. Bilal\nChitra\n3. Devi');

      expect(find.text('ADDING · 3'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Warriors'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Chitra'), findsOneWidget, reason: 'a forgotten number');

      await tester.tap(find.widgetWithText(ActionChip, 'Chitra'));
      await tester.pump(_settle);
      expect(find.text('ADDING · 4'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Chitra'), findsOneWidget);

      await tester.tap(find.text('Add 4 players'));
      await settle(tester);
      expect(find.text('SQUAD · 4'), findsOneWidget);
      expect(find.text('Warriors'), findsNothing);
    });

    testWidgets('backing out adds nobody', (tester) async {
      await openEditor(tester);
      await paste(tester, 'Asha\nBilal');
      await tester.tapAt(const Offset(180, 20)); // above the sheet
      await settle(tester);
      expect(find.text('SQUAD · 0'), findsOneWidget);
    });
  });

  group('import from a CSV file', () {
    Future<void> importFile(WidgetTester tester, String? contents) async {
      files.fileToPick = contents;
      await tester.tap(find.byTooltip('Import teams from a CSV file'));
      await settle(tester);
    }

    testWidgets('new teams are previewed, then saved', (tester) async {
      await pump(tester, const TeamsScreen());
      await importFile(tester, 'Kings,Queens\nAsha (c),Bilal\nChitra,Devi (wk)\nEsha,Farid\n');

      expect(find.text('Import teams'), findsOneWidget);
      expect(find.text('New team · 3 players'), findsNWidgets(2));
      expect(find.text('Asha (C), Chitra, Esha'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Import 2 teams'));
      await settle(tester);
      final saved = {for (final t in teams.teams.values) t.name: t};
      expect(saved.keys, unorderedEquals(['Kings', 'Queens']));
      expect(saved['Kings']!.playerById(saved['Kings']!.captainId!)!.name, 'Asha');
      expect(saved['Queens']!.playerById(saved['Queens']!.keeperId!)!.name, 'Devi');
      expect(find.text('Imported 2 teams with 6 new players.'), findsOneWidget);
      expect(find.text('3 players · Captain: Asha'), findsOneWidget);
    });

    testWidgets('a saved team of the same name gains the new players', (tester) async {
      await teams.save(_team());
      await pump(tester, const TeamsScreen());
      await importFile(tester, 'Team,Player\nalpha,Asha\nalpha,Devi\nSolo,Esha\n');

      expect(find.text('Adds 1 to the saved team · 4 players'), findsOneWidget);
      expect(find.text('Needs at least 2 players, so it is skipped'), findsOneWidget);
      await tester.tap(find.text('Import 1 team'));
      await settle(tester);

      expect(teams.teams.keys, ['t']);
      expect(teams.teams['t']!.players.map((p) => p.name), ['Asha', 'Bilal', 'Chitra', 'Devi']);
    });

    testWidgets('an Excel workbook is explained, not imported', (tester) async {
      await pump(tester, const TeamsScreen());
      await importFile(tester, 'PK\u0003\u0004workbook');

      expect(find.text('Could not import that file'), findsOneWidget);
      expect(find.textContaining('CSV UTF-8'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await settle(tester);
      expect(teams.teams, isEmpty);
    });

    testWidgets('cancelling the picker or the preview saves nothing', (tester) async {
      await pump(tester, const TeamsScreen());
      await importFile(tester, null);
      expect(find.text('Import teams'), findsNothing);

      await importFile(tester, 'Kings\nAsha\nBilal\n');
      expect(find.text('Import teams'), findsOneWidget);
      await tester.tapAt(const Offset(180, 20));
      await settle(tester);
      expect(teams.teams, isEmpty);
    });
  });
}
