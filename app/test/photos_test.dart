import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/photo_store.dart';
import 'package:bnp_scorer/data/player_directory.dart';
import 'package:bnp_scorer/screens/player_profile_screen.dart';
import 'package:bnp_scorer/screens/team_edit_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/avatars.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);
final _jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

void main() {
  setUpAll(() {
    AppFonts.useGoogleFonts = false;
    photosBaseForTesting = 'https://photos.example';
  });

  group('HttpPhotoStore', () {
    late HttpServer server;
    late List<(String method, String path, String? auth, List<int> body)> seen;
    var status = 200;
    var reply = <String, Object?>{'url': 'https://photos.example/img/avatars/u1.img?v=1'};

    setUp(() async {
      seen = [];
      status = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
        seen.add((request.method, request.uri.path, request.headers.value('authorization'), body));
        request.response
          ..statusCode = status
          ..write(jsonEncode(reply));
        await request.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    // flutter_test answers every request with 400 unless a real client is made.
    HttpClient realClient() => HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());

    HttpPhotoStore store(Accounts accounts) =>
        HttpPhotoStore(accounts, baseUrl: 'http://${server.address.host}:${server.port}', client: realClient());

    test('uploads with the sign-in token and returns the address', () async {
      final url = await store(FakeAccounts(signedIn: const Scorer(uid: 'u1', name: 'Asha'))).uploadAvatar(_jpeg);
      expect(url, 'https://photos.example/img/avatars/u1.img?v=1');
      expect(seen.single.$1, 'PUT');
      expect(seen.single.$2, '/v1/avatar');
      expect(seen.single.$3, 'Bearer token-u1');
      expect(seen.single.$4, _jpeg);
    });

    test('removes with DELETE', () async {
      await store(FakeAccounts(signedIn: const Scorer(uid: 'u1', name: 'Asha'))).removeAvatar();
      expect(seen.single.$1, 'DELETE');
    });

    test("passes on the service's reason when it refuses", () async {
      status = 413;
      reply = {'error': 'That photo is too large.'};
      expect(
        () => store(FakeAccounts(signedIn: const Scorer(uid: 'u1', name: 'Asha'))).uploadAvatar(_jpeg),
        throwsA(isA<PhotoException>().having((e) => e.message, 'message', 'That photo is too large.')),
      );
    });

    test('needs a signed-in account, and sends nothing without one', () async {
      expect(() => store(FakeAccounts()).uploadAvatar(_jpeg), throwsA(isA<PhotoException>()));
      expect(seen, isEmpty);
    });

    test('a service that cannot be reached reads as no internet', () async {
      final closed = HttpPhotoStore(
        FakeAccounts(signedIn: const Scorer(uid: 'u1', name: 'Asha')),
        baseUrl: 'http://127.0.0.1:1',
        client: realClient(),
      );
      expect(
        () => closed.uploadAvatar(_jpeg),
        throwsA(isA<PhotoException>().having((e) => e.message, 'message', contains('internet'))),
      );
    });
  });

  test('only addresses on our photos service are loaded', () {
    expect(trustedPhoto('https://photos.example/img/avatars/u1.img?v=1'), 'https://photos.example/img/avatars/u1.img?v=1');
    expect(trustedPhoto('https://tracker.example/img/avatars/u1.img'), isNull);
    expect(trustedPhoto('https://photos.example/other'), isNull);
    expect(trustedPhoto(null), isNull);
  });

  testWidgets('a team badge shows a logo from our service, and initials for anything else', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Column(
        children: [
          TeamBadge(name: 'Alpha', logoUrl: 'https://photos.example/img/teams/u/t.img?v=1'),
          TeamBadge(name: 'Beta', logoUrl: 'https://tracker.example/img/teams/u/t.img'),
        ],
      ),
    ));
    await tester.pump(_settle);
    expect(find.byType(Image), findsOneWidget);
    // Until (and unless) the logo loads, the initials show in its place.
    expect(find.text('AL'), findsOneWidget);
    expect(find.text('BE'), findsOneWidget);
    expect(tester.getSize(find.byType(TeamBadge).first), const Size(40, 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an avatar with a photo that cannot load still shows the initials', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: PlayerAvatar(name: 'Ravi Kumar', photoUrl: 'https://photos.example/img/avatars/x.img')),
    ));
    await tester.pump(_settle);
    expect(find.text('RK'), findsOneWidget);
    expect(tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage, isA<NetworkImage>());
    expect(tester.takeException(), isNull);
  });

  group('profile photo', () {
    late FakePlayerDirectory directory;
    late FakePhotoStore photos;
    late FakeDevicePhotos picker;

    setUp(() {
      directory = FakePlayerDirectory()..players['me'] = const PlayerProfile(id: 'me', name: 'Ravi', ownerUid: 'u9');
      photos = FakePhotoStore();
      picker = FakeDevicePhotos(next: _jpeg);
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(_settle);
      }
    }

    Future<void> openEdit(WidgetTester tester, {bool withStore = true, bool edit = true}) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
          tournamentRepositoryProvider.overrideWithValue(InMemoryTournamentRepository()),
          accountsProvider.overrideWithValue(FakeAccounts(signedIn: const Scorer(uid: 'u9', name: 'Ravi'))),
          playerDirectoryProvider.overrideWithValue(directory),
          if (withStore) photoStoreProvider.overrideWithValue(photos),
          devicePhotosProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const PlayerProfileScreen(playerId: 'me')),
      ));
      await settle(tester);
      if (!edit) return;
      await tester.tap(find.byTooltip('Edit profile'));
      await settle(tester);
    }

    testWidgets('a player adds a photo, and the profile carries it', (tester) async {
      await openEdit(tester);
      await tester.tap(find.text('Add photo'));
      await settle(tester);
      expect(photos.avatar, _jpeg);
      expect(directory.players['me']!.photoUrl, 'https://photos.example/img/avatars/me.img?v=1');
      expect(find.text('Change photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a photo can be removed', (tester) async {
      directory.players['me'] = directory.players['me']!.withPhoto('https://photos.example/img/avatars/me.img?v=1');
      await openEdit(tester);
      await tester.tap(find.text('Remove'));
      await settle(tester);
      expect(directory.players['me']!.photoUrl, isNull);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('backing out of the picker changes nothing; a failed upload says why', (tester) async {
      picker.next = null;
      await openEdit(tester);
      await tester.tap(find.text('Add photo'));
      await settle(tester);
      expect(photos.uploads, 0);

      picker.next = _jpeg;
      photos.failWith = 'No internet. Connect and try again.';
      await tester.tap(find.text('Add photo'));
      await settle(tester);
      expect(find.text('No internet. Connect and try again.'), findsOneWidget);
      expect(directory.players['me']!.photoUrl, isNull);
    });

    testWidgets('a photo makes the header tall, like a player card; initials keep it shorter', (tester) async {
      Future<double> headerHeight() async {
        await openEdit(tester, edit: false);
        return tester.widget<SliverAppBar>(find.byType(SliverAppBar)).expandedHeight!;
      }

      expect(await headerHeight(), 290);
      await directory.saveDetails(directory.players['me']!.withPhoto('https://photos.example/img/avatars/me.img?v=1'));
      await settle(tester);
      expect(tester.widget<SliverAppBar>(find.byType(SliverAppBar)).expandedHeight, 440);
      expect(find.byTooltip('Share profile'), findsOneWidget);
      expect(find.byTooltip('Edit profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without the photos service there is no photo row', (tester) async {
      await openEdit(tester, withStore: false);
      expect(find.text('Add photo'), findsNothing);
    });
  });

  group('team logo', () {
    late InMemoryTeamRepository teams;
    late FakePhotoStore photos;
    late FakeDevicePhotos picker;

    setUp(() {
      teams = InMemoryTeamRepository();
      photos = FakePhotoStore();
      picker = FakeDevicePhotos(next: _jpeg);
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(_settle);
      }
    }

    Future<void> pump(WidgetTester tester, Widget home, {bool signedIn = true}) async {
      tester.view
        ..physicalSize = const Size(1080, 4000)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          teamRepositoryProvider.overrideWithValue(teams),
          matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
          accountsProvider.overrideWithValue(FakeAccounts(signedIn: signedIn ? const Scorer(uid: 'c1', name: 'Asha') : null)),
          photoStoreProvider.overrideWithValue(photos),
          devicePhotosProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ));
      await settle(tester);
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.tap(find.text(text));
      await settle(tester);
    }

    final alpha = Team(
      id: 't1',
      name: 'Alpha',
      players: const [Player(id: 'a', name: 'Asha'), Player(id: 'b', name: 'Bilal')],
    );

    testWidgets('a captain adds a logo, and the saved team keeps it', (tester) async {
      await pump(tester, TeamEditScreen(team: alpha));
      await tapText(tester, 'Add logo');
      expect(photos.logos.keys, ['t1']);
      expect(find.text('Change logo'), findsOneWidget);
      await tapText(tester, 'Save team');
      expect(teams.teams['t1']!.logoUrl, 'https://photos.example/img/teams/me/t1.img?v=1');
    });

    testWidgets('a new team gets its logo under the id it is then saved with', (tester) async {
      await pump(tester, const TeamEditScreen());
      await tester.enterText(find.widgetWithText(TextField, 'Team name'), 'Gamma');
      for (final name in ['Asha', 'Bilal']) {
        await tester.enterText(find.widgetWithText(TextField, 'Add player name'), name);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump(_settle);
      }
      await tapText(tester, 'Add logo');
      await tapText(tester, 'Save team');
      final saved = teams.teams.values.single;
      expect(photos.logos.keys, [saved.id]);
      expect(saved.logoUrl, contains('/img/teams/me/${saved.id}.img'));
    });

    testWidgets('removing the logo clears it on save', (tester) async {
      final withLogo = Team(
        id: 't1',
        name: 'Alpha',
        players: alpha.players,
        logoUrl: 'https://photos.example/img/teams/me/t1.img?v=1',
      );
      await pump(tester, TeamEditScreen(team: withLogo));
      await tapText(tester, 'Remove logo');
      await tapText(tester, 'Save team');
      expect(teams.teams['t1']!.logoUrl, isNull);
    });

    testWidgets('a failed upload says why and keeps the team as it was', (tester) async {
      photos.failWith = 'That photo is too large.';
      await pump(tester, TeamEditScreen(team: alpha));
      await tapText(tester, 'Add logo');
      expect(find.text('That photo is too large.'), findsOneWidget);
      expect(find.text('Add logo'), findsOneWidget);
    });

    testWidgets('signed out there is no logo row', (tester) async {
      await pump(tester, TeamEditScreen(team: alpha), signedIn: false);
      expect(find.text('Add logo'), findsNothing);
    });
  });
}

/// The real network stack, not flutter_test's stand-in.
class _RealHttp extends HttpOverrides {}
