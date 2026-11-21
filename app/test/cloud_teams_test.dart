import 'dart:io';

import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/app_links.dart';
import 'package:bnp_scorer/data/cloud_teams.dart';
import 'package:bnp_scorer/data/player_directory.dart';
import 'package:bnp_scorer/data/syncing_teams.dart';
import 'package:bnp_scorer/screens/home_screen.dart';
import 'package:bnp_scorer/screens/player_profile_screen.dart';
import 'package:bnp_scorer/screens/team_edit_screen.dart';
import 'package:bnp_scorer/screens/teams_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/format.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);
const _captain = Scorer(uid: 'c1', name: 'Captain Asha');
// A made-up number: never put a real player's number in a test.
const _number = '+919876543210';

Team _alpha() => Team(
      id: 'alpha',
      name: 'Alpha',
      players: const [Player(id: 'p1', name: 'Asha'), Player(id: 'p2', name: 'Bilal')],
    );

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  group('join codes', () {
    test('are six letters from the clear alphabet, the same every time', () {
      final code = joinCodeOf('alpha');
      expect(code, hasLength(6));
      expect(code.split('').every(joinCodeAlphabet.contains), isTrue);
      expect(joinCodeOf('alpha'), code);
      expect(joinCodeOf('beta'), isNot(code));
    });

    test('are read however they are typed', () {
      final code = joinCodeOf('alpha');
      expect(normalizeJoinCode(code.toLowerCase()), code);
      expect(normalizeJoinCode('${code.substring(0, 3)} ${code.substring(3)}'), code);
      expect(normalizeJoinCode('${code.substring(0, 3)}-${code.substring(3)}'), code);
      expect(normalizeJoinCode('ABC'), isNull);
      expect(normalizeJoinCode('ABCDE0'), isNull, reason: '0 is not in the alphabet');
    });

    test('the website join page accepts exactly the same letters', () {
      final page = File('../site/join.html').readAsStringSync();
      expect(page, contains('[^$joinCodeAlphabet]'));
    });

    test('the invite names the team, the code and the join page', () {
      final text = teamInviteText('Alpha', 'ABC234');
      expect(text, contains('Join Alpha on BNP Scorer'));
      expect(text, contains('ABC234'));
      expect(text, contains(joinPageLink('ABC234')));
      expect(joinPageLink('ABC234'), '$joinPageAddress?code=ABC234');
    });

    test('an invite link gives its code; any other link gives nothing', () {
      final code = joinCodeOf('alpha');
      expect(joinCodeFromLink(Uri.parse('bnpscorer://join?code=$code')), code);
      expect(joinCodeFromLink(Uri.parse('bnpscorer://join?code=${code.toLowerCase()}')), code);
      expect(joinCodeFromLink(Uri.parse('bnpscorer://join?code=nope')), isNull);
      expect(joinCodeFromLink(Uri.parse('bnpscorer://join')), isNull);
      expect(joinCodeFromLink(Uri.parse('https://example.com/join?code=$code')), isNull);
    });

    test('the join page opens the app with the scheme the manifest declares', () {
      final page = File('../site/join.html').readAsStringSync();
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(page, contains("'intent://join?code=' + code + '#Intent;scheme=bnpscorer;package=com.bitsnpixs.bnp_scorer;end'"));
      expect(manifest, contains('<data android:scheme="bnpscorer" android:host="join"/>'));
      expect(manifest, contains('android:name="flutter_deeplinking_enabled" android:value="false"'));
    });
  });

  group('SyncingTeamRepository', () {
    late InMemoryTeamRepository local;
    late FakeCloudTeams cloud;
    late FakeAccounts accounts;
    late SyncingTeamRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      local = InMemoryTeamRepository();
      cloud = FakeCloudTeams();
      accounts = FakeAccounts(signedIn: _captain);
      repo = SyncingTeamRepository(local, cloud, accounts, await SharedPreferences.getInstance());
    });

    test('a team stays on the phone until its invite is shared', () async {
      await repo.save(_alpha());
      await pumpEventQueue();
      expect(local.teams, contains('alpha'));
      expect(cloud.teams, isEmpty);
      expect(repo.isShared('alpha'), isFalse);
    });

    test('once shared, later saves keep the cloud copy in step', () async {
      await repo.share(_alpha());
      expect(cloud.teams['alpha']!.ownerUid, 'c1');
      expect(repo.isShared('alpha'), isTrue);

      final bigger = Team(id: 'alpha', name: 'Alpha', players: [..._alpha().players, const Player(id: 'p3', name: 'Chitra')]);
      await repo.save(bigger);
      await pumpEventQueue();
      expect(cloud.teams['alpha']!.team.players, hasLength(3));
    });

    test('signed out, sharing is refused and saves stay local', () async {
      await repo.share(_alpha());
      await accounts.signOut();
      expect(() => repo.share(_alpha()), throwsA(isA<AccountsException>()));
      await repo.save(Team(id: 'alpha', name: 'Renamed', players: _alpha().players));
      await pumpEventQueue();
      expect(cloud.teams['alpha']!.team.name, 'Alpha');
    });

    test('deleting a shared team unshares it', () async {
      await repo.share(_alpha());
      await repo.delete('alpha');
      await pumpEventQueue();
      expect(cloud.teams, isEmpty);
      expect(repo.isShared('alpha'), isFalse);
    });
  });

  group('screens', () {
    late InMemoryTeamRepository local;
    late FakeCloudTeams cloud;
    late FakeAccounts accounts;
    late FakePlayerDirectory directory;
    late TextShares files;
    late SyncingTeamRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      local = InMemoryTeamRepository();
      cloud = FakeCloudTeams();
      accounts = FakeAccounts(signedIn: _captain);
      directory = FakePlayerDirectory();
      files = TextShares();
      repo = SyncingTeamRepository(local, cloud, accounts, await SharedPreferences.getInstance());
      await local.save(_alpha());
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
          teamRepositoryProvider.overrideWithValue(repo),
          teamSharingProvider.overrideWithValue(repo),
          cloudTeamsProvider.overrideWithValue(cloud),
          accountsProvider.overrideWithValue(accounts),
          playerDirectoryProvider.overrideWithValue(directory),
          deviceFilesProvider.overrideWithValue(files),
          matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
          tournamentRepositoryProvider.overrideWithValue(InMemoryTournamentRepository()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ));
      await settle(tester);
    }

    testWidgets('Invite players shares the team and shows its code and QR to send', (tester) async {
      await pump(tester, TeamEditScreen(team: _alpha()));
      expect(find.textContaining('Join code'), findsNothing);
      await tester.tap(find.byTooltip('Invite players'));
      await settle(tester);

      final code = joinCodeOf('alpha');
      expect(cloud.teams, contains('alpha'));
      expect(find.text('Invite to Alpha'), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-qr')), findsOneWidget);
      // The QR is a fair size to scan at the ground.
      expect(tester.getSize(find.byKey(const ValueKey('invite-qr'))).width, greaterThanOrEqualTo(180));
      expect(find.text(code), findsOneWidget);
      await tester.tap(find.text('Send invite'));
      await settle(tester);
      expect(files.text, contains(code));

      await tester.tapAt(const Offset(180, 40)); // close the sheet
      await settle(tester);
      expect(find.text('JOIN CODE · $code'), findsOneWidget);
      expect(find.textContaining('Nobody has asked to join yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed out, Invite players asks to sign in', (tester) async {
      accounts = FakeAccounts();
      repo = SyncingTeamRepository(local, cloud, accounts, await SharedPreferences.getInstance());
      await pump(tester, TeamEditScreen(team: _alpha()));
      await tester.tap(find.byTooltip('Invite players'));
      await settle(tester);
      expect(find.text('Sign in from Settings to invite players.'), findsOneWidget);
      expect(cloud.teams, isEmpty);
    });

    testWidgets('a new, unsaved team has no invite yet', (tester) async {
      await pump(tester, const TeamEditScreen());
      expect(find.byTooltip('Invite players'), findsNothing);
    });

    testWidgets('the captain adds or ignores players who asked to join', (tester) async {
      await repo.share(_alpha());
      await cloud.requestJoin('alpha', playerId: 'dir9', name: 'Ravi');
      await cloud.requestJoin('alpha', playerId: 'dir8', name: 'Kiran');
      await pump(tester, TeamEditScreen(team: _alpha()));

      expect(find.text('Asked to join'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Add').first);
      await settle(tester);
      expect(find.text('Added Ravi. Save to keep them.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Ignore'));
      await settle(tester);
      expect(cloud.requests['alpha'], isEmpty);

      await tester.tap(find.text('Save team'));
      await settle(tester);
      expect(local.teams['alpha']!.players.map((p) => p.id), ['p1', 'p2', 'dir9']);
      expect(tester.takeException(), isNull);
    });

    group('Join a team', () {
      Future<void> openJoin(WidgetTester tester) async {
        await pump(tester, const TeamsScreen());
        await tester.tap(find.byTooltip('Join a team'));
        await settle(tester);
      }

      Future<void> typeCode(WidgetTester tester, String code) async {
        await tester.enterText(find.byKey(const ValueKey('join-code')), code);
        await tester.tap(find.text('Find team'));
        await settle(tester);
      }

      testWidgets('a wrong or unknown code is explained', (tester) async {
        await openJoin(tester);
        await typeCode(tester, 'AB');
        expect(find.textContaining('A join code is 6 letters'), findsOneWidget);
        await typeCode(tester, 'ZZZZZZ');
        expect(find.text('No team has that code. Check it with your captain.'), findsOneWidget);
      });

      testWidgets('a player with a profile asks to join, and the captain sees it', (tester) async {
        await repo.share(_alpha());
        final me = directory.seed('Ravi', _number);
        accounts = FakeAccounts(signedIn: const Scorer(uid: 'u9', name: 'Ravi', phone: _number));
        await openJoin(tester);
        await typeCode(tester, joinCodeOf('alpha').toLowerCase());
        expect(find.text('Alpha'), findsWidgets);
        expect(find.textContaining('Shared by Captain Asha'), findsOneWidget);

        await tester.tap(find.text('Ask to join'));
        await settle(tester);
        expect(find.text('Asked to join Alpha. Your captain adds you.'), findsOneWidget);
        expect(cloud.requests['alpha']!.keys, [me.id]);
      });

      testWidgets('without a confirmed number it asks for one first', (tester) async {
        await repo.share(_alpha());
        await openJoin(tester);
        await typeCode(tester, joinCodeOf('alpha'));
        await tester.tap(find.text('Ask to join'));
        await settle(tester);
        expect(find.textContaining('Add your mobile number in Settings first'), findsOneWidget);
        expect(cloud.requests, isEmpty);
      });

      testWidgets('someone already in the team is told so', (tester) async {
        final me = directory.seed('Ravi', _number);
        await repo.share(Team(id: 'alpha', name: 'Alpha', players: [..._alpha().players, me.player]));
        accounts = FakeAccounts(signedIn: const Scorer(uid: 'u9', name: 'Ravi', phone: _number));
        await openJoin(tester);
        await typeCode(tester, joinCodeOf('alpha'));
        await tester.tap(find.text('Ask to join'));
        await settle(tester);
        expect(find.text('You are already in Alpha.'), findsOneWidget);
      });
    });

    testWidgets('an invite link opens the join sheet with the code looked up', (tester) async {
      await repo.share(_alpha());
      final links = FakeAppLinks(initial: Uri.parse('bnpscorer://join?code=${joinCodeOf('alpha')}'));
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          teamRepositoryProvider.overrideWithValue(repo),
          teamSharingProvider.overrideWithValue(repo),
          cloudTeamsProvider.overrideWithValue(cloud),
          accountsProvider.overrideWithValue(accounts),
          playerDirectoryProvider.overrideWithValue(directory),
          appLinksProvider.overrideWithValue(links),
          matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
          tournamentRepositoryProvider.overrideWithValue(InMemoryTournamentRepository()),
          scheduleRepositoryProvider.overrideWithValue(InMemoryScheduleRepository()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const HomeScreen()),
      ));
      await settle(tester);
      expect(find.text('Join a team'), findsWidgets);
      expect(find.textContaining('Shared by Captain Asha'), findsOneWidget);

      // A second link while the app is open does the same.
      await tester.tapAt(const Offset(180, 40));
      await settle(tester);
      links.send(Uri.parse('bnpscorer://join?code=${joinCodeOf('alpha')}'));
      await settle(tester);
      expect(find.textContaining('Shared by Captain Asha'), findsOneWidget);
    });

    testWidgets("a player's profile lists the shared teams they are in", (tester) async {
      await repo.share(Team(id: 'alpha', name: 'Alpha', players: [..._alpha().players, const Player(id: 'dir1', name: 'Ravi')]));
      directory.players['dir1'] = const PlayerProfile(id: 'dir1', name: 'Ravi');
      await pump(tester, const PlayerProfileScreen(playerId: 'dir1'));
      // No matches yet: the shared squad still shows under Teams.
      expect(find.text('No finished matches yet.'), findsOneWidget);
      expect(find.text('TEAMS'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
    });
  });
}
