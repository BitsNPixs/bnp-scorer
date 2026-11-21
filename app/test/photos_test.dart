import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/photo_store.dart';
import 'package:bnp_scorer/data/player_directory.dart';
import 'package:bnp_scorer/screens/player_profile_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/avatars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);
final _jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

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

    Future<void> openEdit(WidgetTester tester, {bool withStore = true}) async {
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

    testWidgets('without the photos service there is no photo row', (tester) async {
      await openEdit(tester, withStore: false);
      expect(find.text('Add photo'), findsNothing);
    });
  });
}

/// The real network stack, not flutter_test's stand-in.
class _RealHttp extends HttpOverrides {}
