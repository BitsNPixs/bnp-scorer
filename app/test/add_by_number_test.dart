import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/player_directory.dart';
import 'package:bnp_scorer/screens/new_match_screen.dart';
import 'package:bnp_scorer/screens/team_edit_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

// Made-up numbers: never put a real player's number in a test.
const _ravi = '+919876543210';
const _new = '+919876543211';
const _captain = Scorer(uid: 'c1', name: 'Captain Asha');

Team _alpha() => Team(
      id: 't',
      name: 'Alpha',
      players: const [
        Player(id: 'p1', name: 'Asha'),
        Player(id: 'p2', name: 'Bilal'),
        Player(id: 'p3', name: 'Ravi', role: PlayerRole.bowler),
      ],
      captainId: 'p3',
    );

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  late InMemoryTeamRepository teams;
  late InMemoryMatchRepository matches;
  late FakePlayerDirectory directory;
  late FakeAccounts accounts;

  setUp(() {
    teams = InMemoryTeamRepository();
    matches = InMemoryMatchRepository();
    directory = FakePlayerDirectory();
    accounts = FakeAccounts(signedIn: _captain);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  Future<void> pump(WidgetTester tester, Widget home, {bool withDirectory = true}) async {
    tester.view
      // 360 dp wide, tall enough that New match builds both teams.
      ..physicalSize = const Size(1080, 9000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        teamRepositoryProvider.overrideWithValue(teams),
        matchRepositoryProvider.overrideWithValue(matches),
        accountsProvider.overrideWithValue(accounts),
        if (withDirectory) playerDirectoryProvider.overrideWithValue(directory),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    ));
    await settle(tester);
  }

  Future<void> openSheet(WidgetTester tester, {int index = 0}) async {
    final button = find.text('Add by number').at(index);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settle(tester);
  }

  Future<void> find_(WidgetTester tester, String number) async {
    await tester.enterText(find.byKey(const ValueKey('find-number')), number);
    await tester.tap(find.widgetWithText(FilledButton, 'Find'));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save team'));
    await settle(tester);
  }

  group('the team page', () {
    testWidgets('a verified player found by number joins with their shared id', (tester) async {
      final ravi = directory.seed('Ravi Kumar', _ravi, ownerUid: 'u9');
      await pump(tester, TeamEditScreen(team: _alpha()));
      await openSheet(tester);
      await find_(tester, '98765 43210');

      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('Verified player'), findsOneWidget);
      await tester.tap(find.text('Add to team'));
      await settle(tester);

      expect(find.text('Added Ravi Kumar.'), findsOneWidget);
      // The directory marks them on the squad list.
      expect(find.textContaining('Verified'), findsOneWidget);
      await save(tester);
      expect(teams.teams['t']!.players.map((p) => p.id), ['p1', 'p2', 'p3', ravi.id]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a number nobody has is invited under the name typed', (tester) async {
      await pump(tester, TeamEditScreen(team: _alpha()));
      await openSheet(tester);
      await find_(tester, '9876543211');

      expect(find.textContaining('Nobody has joined with this number yet'), findsOneWidget);
      await tester.tap(find.text('Add as invited'));
      await settle(tester);
      expect(find.text('Type their name.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('invite-name')), 'Kiran');
      await tester.tap(find.text('Add as invited'));
      await settle(tester);

      final kiran = directory.players[directory.phones[_new]]!;
      expect(kiran.name, 'Kiran');
      expect(kiran.claimed, isFalse);
      expect(find.textContaining('Invited'), findsOneWidget);
      await save(tester);
      expect(teams.teams['t']!.players.last.id, kiran.id);
    });

    testWidgets('a player already in the squad cannot be added twice', (tester) async {
      final ravi = directory.seed('Ravi Kumar', _ravi, ownerUid: 'u9');
      final team = Team(id: 't', name: 'Alpha', players: [..._alpha().players, ravi.player]);
      await pump(tester, TeamEditScreen(team: team));
      await openSheet(tester);
      await find_(tester, _ravi);
      expect(find.text('Already in the team'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Already in the team')).onPressed, isNull);
    });

    testWidgets('the same name can be linked: the member keeps their role and captaincy', (tester) async {
      final ravi = directory.seed('Ravi', _ravi, ownerUid: 'u9');
      await pump(tester, TeamEditScreen(team: _alpha()));
      await openSheet(tester);
      await find_(tester, _ravi);
      await tester.tap(find.text('Add to team'));
      await settle(tester);

      expect(find.text('Same person as Ravi?'), findsOneWidget);
      await tester.tap(find.text('Same person'));
      await settle(tester);
      expect(find.text('Ravi is linked to their number.'), findsOneWidget);

      await save(tester);
      final saved = teams.teams['t']!;
      expect(saved.players.map((p) => p.id), ['p1', 'p2', ravi.id]);
      expect(saved.players.last.role, PlayerRole.bowler);
      expect(saved.captainId, ravi.id);
    });

    testWidgets('choosing someone else adds a second player of that name', (tester) async {
      directory.seed('Ravi', _ravi, ownerUid: 'u9');
      await pump(tester, TeamEditScreen(team: _alpha()));
      await openSheet(tester);
      await find_(tester, _ravi);
      await tester.tap(find.text('Add to team'));
      await settle(tester);
      await tester.tap(find.text('Someone else'));
      await settle(tester);
      await save(tester);
      expect(teams.teams['t']!.players.where((p) => p.name == 'Ravi'), hasLength(2));
    });

    testWidgets('offline, the sheet says so', (tester) async {
      directory.offline = true;
      await pump(tester, TeamEditScreen(team: _alpha()));
      await openSheet(tester);
      await find_(tester, _ravi);
      expect(find.text(offlineMessage), findsOneWidget);
    });

    testWidgets('signed out, it asks to sign in first', (tester) async {
      accounts = FakeAccounts();
      await pump(tester, TeamEditScreen(team: _alpha()));
      await openSheet(tester);
      expect(find.text('Sign in from Settings to add players by number.'), findsOneWidget);
      expect(find.byKey(const ValueKey('find-number')), findsNothing);
    });

    testWidgets('without the cloud there is no Add by number', (tester) async {
      await pump(tester, TeamEditScreen(team: _alpha()), withDirectory: false);
      expect(find.text('Paste a list'), findsOneWidget);
      expect(find.text('Add by number'), findsNothing);
    });
  });

  group('New match', () {
    Future<void> start(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Start match'));
      await tester.tap(find.text('Start match'));
      await settle(tester);
    }

    Future<void> addName(WidgetTester tester, String name, {int side = 0}) async {
      final field = find.widgetWithText(TextField, 'Add player name').at(side);
      await tester.ensureVisible(field);
      await tester.enterText(field, name);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(_settle);
    }

    testWidgets('a player added by number plays with their shared id, and the squad keeps it', (tester) async {
      final ravi = directory.seed('Ravi Kumar', _ravi, ownerUid: 'u9');
      await pump(tester, const NewMatchScreen());
      await tester.enterText(find.widgetWithText(TextField, 'Home team name'), 'Alpha');
      await tester.enterText(find.widgetWithText(TextField, 'Away team name'), 'Beta');
      await addName(tester, 'Asha');
      await openSheet(tester);
      await find_(tester, _ravi);
      await tester.tap(find.text('Add to team'));
      await settle(tester);
      expect(find.text('Ravi Kumar'), findsOneWidget);

      await addName(tester, 'Bilal', side: 1);
      await addName(tester, 'Bose', side: 1);
      await start(tester);

      final setup = (await matches.loadAll()).single.setup;
      expect(setup.teamA.players.map((p) => p.id), contains(ravi.id));
      final alpha = (await teams.loadAll()).firstWhere((t) => t.name == 'Alpha');
      expect(alpha.players.map((p) => p.id), contains(ravi.id));
    });

    testWidgets('linking a saved player swaps their id in the saved squad', (tester) async {
      await teams.save(_alpha());
      final beta = Team(
        id: 'b',
        name: 'Beta',
        players: const [Player(id: 'b1', name: 'Bose'), Player(id: 'b2', name: 'Bala')],
      );
      await teams.save(beta);
      final ravi = directory.seed('Ravi', _ravi, ownerUid: 'u9');
      await pump(tester, const NewMatchScreen());
      await tester.tap(find.text('Saved teams').at(0));
      await settle(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Alpha'));
      await settle(tester);
      await tester.tap(find.text('Saved teams', skipOffstage: false).at(1));
      await settle(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Beta'));
      await settle(tester);

      await openSheet(tester);
      await find_(tester, _ravi);
      await tester.tap(find.text('Add to team'));
      await settle(tester);
      await tester.tap(find.text('Same person'));
      await settle(tester);
      await start(tester);

      final setup = (await matches.loadAll()).single.setup;
      expect(setup.teamA.players.map((p) => p.id), ['p1', 'p2', ravi.id]);
      expect(setup.teamA.captainId, ravi.id);
      final alpha = teams.teams['t']!;
      expect(alpha.players.map((p) => p.id), ['p1', 'p2', ravi.id]);
      expect(alpha.players.last.role, PlayerRole.bowler);
      expect(alpha.captainId, ravi.id);
    });
  });
}
