import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/screens/new_match_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

Team _squad(String id, String name, int size) => Team(
      id: id,
      name: name,
      players: [
        for (var i = 1; i <= size; i++) Player(id: '$id-$i', name: '$name P$i'),
      ],
    );

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  late InMemoryMatchRepository matches;
  late InMemoryTeamRepository teams;

  setUp(() {
    matches = InMemoryMatchRepository();
    teams = InMemoryTeamRepository();
  });

  Future<void> pump(WidgetTester tester, {Accounts? accounts}) async {
    tester.view
      // 360 dp wide, and tall enough that the lazy list builds both teams.
      ..physicalSize = const Size(1080, 9000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(matches),
        teamRepositoryProvider.overrideWithValue(teams),
        if (accounts != null) accountsProvider.overrideWithValue(accounts),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const NewMatchScreen()),
    ));
    await tester.pump(_settle);
  }

  Future<void> tapText(WidgetTester tester, String text, {int index = 0}) async {
    final finder = find.text(text, skipOffstage: false).at(index);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> pick(WidgetTester tester, String team, {int side = 0}) async {
    await tapText(tester, 'Saved teams', index: side);
    await tester.tap(find.widgetWithText(ListTile, team));
    await settle(tester);
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.text('Start match'));
    await settle(tester);
  }

  Future<void> addPlayer(WidgetTester tester, Finder field, String name) async {
    await tester.ensureVisible(field);
    await tester.enterText(field, name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(_settle);
  }

  testWidgets('with no saved teams the button is not offered', (tester) async {
    await pump(tester);
    expect(find.text('Saved teams'), findsNothing);
  });

  testWidgets('picking a squad fills an eleven and benches the rest', (tester) async {
    await teams.save(_squad('a', 'Alpha', 13));
    await pump(tester);

    await pick(tester, 'Alpha');

    expect(find.text('PLAYERS · 11'), findsOneWidget);
    expect(find.text('SITTING OUT · 2'), findsOneWidget);
    expect(find.text('Alpha P12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the real squads fit at 360 dp, long names included', (tester) async {
    await seedDemoTeams(teams);
    await pump(tester);

    await pick(tester, 'Team A');
    await pick(tester, 'Team D', side: 1);

    expect(find.text('Punith Kumar Nayaka R'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a match from two saved teams keeps their ids and full squads', (tester) async {
    await teams.save(_squad('a', 'Alpha', 13));
    await teams.save(_squad('b', 'Bravo', 11));
    await pump(tester);

    await pick(tester, 'Alpha');
    await pick(tester, 'Bravo', side: 1);
    await start(tester);

    final setup = matches.records.values.single.setup;
    expect(setup.teamA.id, 'a');
    expect(setup.teamA.players, hasLength(11));
    expect(setup.teamA.players.first.id, 'a-1');
    expect(setup.teamB.id, 'b');
    expect(teams.teams['a']!.players, hasLength(13), reason: 'nobody leaves the squad');
    expect(teams.teams, hasLength(2));
  });

  testWidgets("a signed-in scorer's new match is published; signed out it stays private", (tester) async {
    await teams.save(_squad('a', 'Alpha', 11));
    await teams.save(_squad('b', 'Bravo', 11));
    await pump(tester, accounts: FakeAccounts(signedIn: const Scorer(uid: 'u1', name: 'Asha Scorer')));
    await pick(tester, 'Alpha');
    await pick(tester, 'Bravo', side: 1);
    await start(tester);
    expect(matches.records.values.single.publishedBy, 'u1');
  });

  testWidgets('without signing in, a new match is not published', (tester) async {
    await teams.save(_squad('a', 'Alpha', 11));
    await teams.save(_squad('b', 'Bravo', 11));
    await pump(tester);
    await pick(tester, 'Alpha');
    await pick(tester, 'Bravo', side: 1);
    await start(tester);
    expect(matches.records.values.single.publishedBy, isNull);
  });

  testWidgets('a player can be swapped in from the bench', (tester) async {
    await teams.save(_squad('a', 'Alpha', 12));
    await teams.save(_squad('b', 'Bravo', 2));
    await pump(tester);
    await pick(tester, 'Alpha');
    await pick(tester, 'Bravo', side: 1);

    tester.widget<InputChip>(find.widgetWithText(InputChip, 'Alpha P1', skipOffstage: false)).onDeleted!();
    await tester.pump(_settle);
    expect(find.text('SITTING OUT · 2'), findsOneWidget);

    await tapText(tester, 'Alpha P12');
    await start(tester);

    final names = matches.records.values.single.setup.teamA.players.map((p) => p.name);
    expect(names, contains('Alpha P12'));
    expect(names, isNot(contains('Alpha P1')));
    expect(teams.teams['a']!.players, hasLength(12));
  });

  testWidgets('removing a typed player drops them completely', (tester) async {
    await pump(tester);
    final field = find.byType(TextField).at(1);
    await addPlayer(tester, field, 'Asha');

    tester.widget<InputChip>(find.widgetWithText(InputChip, 'Asha')).onDeleted!();
    await tester.pump(_settle);

    expect(find.textContaining('SITTING OUT'), findsNothing);
    expect(find.text('Asha'), findsNothing);
  });

  testWidgets('a repeated name in a saved team does not break the match', (tester) async {
    await teams.save(_squad('a', 'Alpha', 2));
    await teams.save(_squad('b', 'Bravo', 2));
    await pump(tester);
    await pick(tester, 'Alpha');
    await pick(tester, 'Bravo', side: 1);

    await addPlayer(tester, find.byType(TextField).at(1), 'Alpha P1');
    await start(tester);

    final ids = matches.records.values.single.setup.teamA.players.map((p) => p.id);
    expect(ids.toSet(), hasLength(3));
  });

  testWidgets('a typed team is remembered, and placeholders are not', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField).at(0), 'Fresh');
    await addPlayer(tester, find.byType(TextField).at(1), 'Asha');
    await addPlayer(tester, find.byType(TextField).at(1), 'Bilal');

    await tester.enterText(find.byType(TextField).at(2), 'Others');
    await tester.pump(_settle);
    await tapText(tester, 'Fill to 11', index: 1);
    await start(tester);

    expect(matches.records, hasLength(1));
    expect(teams.teams.values.single.name, 'Fresh');
    expect(teams.teams.values.single.players.map((p) => p.name), ['Asha', 'Bilal']);
  });

  testWidgets('typing a saved name reuses its team and player ids', (tester) async {
    await teams.save(_squad('a', 'Alpha', 3));
    await teams.save(_squad('b', 'Bravo', 2));
    await pump(tester);

    await tester.enterText(find.byType(TextField).at(0), 'alpha');
    await addPlayer(tester, find.byType(TextField).at(1), 'Alpha P2');
    await addPlayer(tester, find.byType(TextField).at(1), 'New Face');
    await pick(tester, 'Bravo', side: 1);
    await start(tester);

    final team = matches.records.values.single.setup.teamA;
    expect(team.id, 'a');
    expect(team.players.first.id, 'a-2');
    expect(teams.teams, hasLength(2), reason: 'no duplicate team');
    expect(teams.teams['a']!.players, hasLength(4));
  });

  testWidgets('renaming a picked team over a typed team keeps two teams', (tester) async {
    await teams.save(_squad('a', 'Alpha', 2));
    await pump(tester);

    await pick(tester, 'Alpha');
    await tester.enterText(find.byType(TextField).at(0), 'Renamed');
    await tester.pump(_settle);
    await tester.enterText(find.byType(TextField).at(2), 'Alpha');
    await addPlayer(tester, find.byType(TextField).at(3), 'Asha');
    await addPlayer(tester, find.byType(TextField).at(3), 'Bilal');
    await start(tester);

    final setup = matches.records.values.single.setup;
    expect(setup.teamA.id, 'a');
    expect(setup.teamB.id, isNot('a'));
  });

  testWidgets('a saved team cannot play itself', (tester) async {
    await teams.save(_squad('a', 'Alpha', 11));
    await pump(tester);
    await pick(tester, 'Alpha');

    expect(find.text('Saved teams'), findsOneWidget, reason: 'only the side already using it');
    await tapText(tester, 'Saved teams');
    expect(find.widgetWithText(ListTile, 'Alpha'), findsOneWidget);
  });

  testWidgets('a team can be deleted from the sheet', (tester) async {
    await teams.save(_squad('a', 'Alpha', 11));
    await teams.save(_squad('b', 'Bravo', 11));
    await pump(tester);

    await tapText(tester, 'Saved teams');
    await tester.tap(find.byTooltip('Delete Alpha'));
    await tester.pump(_settle);
    await tapText(tester, 'Delete');

    expect(teams.teams.keys, ['b']);
    expect(find.widgetWithText(ListTile, 'Alpha'), findsNothing);
  });

  testWidgets('a failed team save does not stop the match', (tester) async {
    await teams.save(_squad('a', 'Alpha', 11));
    await teams.save(_squad('b', 'Bravo', 11));
    await pump(tester);
    await pick(tester, 'Alpha');
    await pick(tester, 'Bravo', side: 1);

    teams.failSaves = true;
    await start(tester);

    expect(matches.records, hasLength(1));
    expect(find.text('Start match'), findsNothing);
  });
}
