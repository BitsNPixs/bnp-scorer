import 'dart:convert';
import 'dart:typed_data';

import 'package:bnp_scorer/data/backup.dart';
import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/data/device_files.dart';
import 'package:bnp_scorer/screens/backup_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/format.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

class _FakeFiles implements DeviceFiles {
  String? sharedName;
  String? sharedContents;
  String? fileToPick;
  bool failShare = false;

  @override
  Future<void> shareImage(Uint8List png, {required String caption}) async {}

  @override
  Future<void> shareTextFile(String name, String contents) async {
    if (failShare) throw StateError('No apps to share with');
    sharedName = name;
    sharedContents = contents;
  }

  @override
  Future<String?> pickTextFile() async => fileToPick;
}

Team _team(String id) => Team(id: id, name: 'Team $id', players: const [
      Player(id: 'p1', name: 'One'),
      Player(id: 'p2', name: 'Two'),
    ]);

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  final now = DateTime.utc(2026, 11, 6);

  late InMemoryMatchRepository matches;
  late InMemoryTeamRepository teams;
  late InMemoryTournamentRepository tournaments;

  setUp(() {
    matches = InMemoryMatchRepository();
    teams = InMemoryTeamRepository();
    tournaments = InMemoryTournamentRepository();
  });

  Future<void> seed() async {
    await seedDemoMatches(matches, now: now);
    await seedDemoTeams(teams);
    await seedDemoTournaments(tournaments, now: now);
  }

  group('the file', () {
    test('holds everything and reads back intact', () async {
      await seed();
      final raw = (await collectBackup(matches, teams, tournaments)).encode(now);
      final back = Backup.decode(raw);

      expect(back.matches, hasLength(matches.records.length));
      expect(back.teams, hasLength(4));
      expect(back.tournaments, hasLength(tournaments.tournaments.length));
      final original = matches.records['demo-match-1']!;
      final restored = back.matches.firstWhere((m) => m.id == original.id);
      expect(restored.toJson(), original.toJson());
    });

    test('rejects a file that is not JSON', () {
      expect(() => Backup.decode('not json'), throwsFormatException);
    });

    test('rejects JSON from something else', () {
      expect(() => Backup.decode('{"hello":"world"}'), throwsFormatException);
      expect(() => Backup.decode('[1,2]'), throwsFormatException);
    });

    test('refuses a backup from a newer app, and says so', () {
      final raw = jsonEncode({'app': 'bnp_scorer', 'version': 99, 'matches': [], 'teams': [], 'tournaments': []});
      expect(
        () => Backup.decode(raw),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('newer'))),
      );
    });

    test('one damaged record rejects the whole file', () {
      final raw = jsonEncode({
        'app': 'bnp_scorer',
        'version': 1,
        'matches': [],
        'teams': [
          _team('a').toJson(),
          {'id': 'broken'},
        ],
        'tournaments': [],
      });
      expect(
        () => Backup.decode(raw),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('damaged'))),
      );
    });

    test('summaries read naturally', () {
      expect(
        const RestoreResult(matches: 1, teams: 2, tournaments: 0).summary,
        '1 match, 2 teams and 0 tournaments',
      );
      expect(
        const RestoreResult(matches: 2, teams: 1, tournaments: 1).summary,
        '2 matches, 1 team and 1 tournament',
      );
    });
  });

  group('restoring', () {
    test('rebuilds an empty phone completely', () async {
      await seed();
      final backup = await collectBackup(matches, teams, tournaments);

      final emptyMatches = InMemoryMatchRepository();
      final emptyTeams = InMemoryTeamRepository();
      final emptyTournaments = InMemoryTournamentRepository();
      final result = await restoreBackup(backup, emptyMatches, emptyTeams, emptyTournaments);

      expect(result.matches, matches.records.length);
      expect(emptyMatches.records, hasLength(matches.records.length));
      expect(emptyTeams.teams, hasLength(4));
      expect(emptyTournaments.tournaments, hasLength(tournaments.tournaments.length));
    });

    test('never overwrites what is already here', () async {
      await seed();
      final backup = await collectBackup(matches, teams, tournaments);
      final newer = _team('team-a');
      await teams.save(newer);

      final result = await restoreBackup(backup, matches, teams, tournaments);

      expect(result.addedNothing, isTrue);
      expect(teams.teams['team-a'], same(newer));
    });

    test('adds only what is missing, and can be run twice', () async {
      await seed();
      final backup = await collectBackup(matches, teams, tournaments);
      await matches.delete('demo-match-1');

      expect((await restoreBackup(backup, matches, teams, tournaments)).matches, 1);
      expect((await restoreBackup(backup, matches, teams, tournaments)).addedNothing, isTrue);
    });
  });

  group('the screen', () {
    Future<_FakeFiles> pump(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final files = _FakeFiles();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          matchRepositoryProvider.overrideWithValue(matches),
          teamRepositoryProvider.overrideWithValue(teams),
          tournamentRepositoryProvider.overrideWithValue(tournaments),
          deviceFilesProvider.overrideWithValue(files),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const BackupScreen()),
      ));
      await tester.pump(_settle);
      return files;
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(_settle);
      }
    }

    testWidgets('warns that data lives only on the phone', (tester) async {
      await pump(tester);
      expect(find.textContaining('Uninstalling'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('creates a dated backup file', (tester) async {
      await teams.save(_team('a'));
      final files = await pump(tester);
      await tester.tap(find.text('Create backup'));
      await settle(tester);

      expect(files.sharedName, 'bnp-scorer-backup-${isoDate(DateTime.now())}.json');
      expect(Backup.decode(files.sharedContents!).teams.single.id, 'a');
    });

    testWidgets('says when there is nothing to back up', (tester) async {
      final files = await pump(tester);
      await tester.tap(find.text('Create backup'));
      await settle(tester);
      expect(find.text('Nothing to back up yet.'), findsOneWidget);
      expect(files.sharedName, isNull);
    });

    testWidgets('a failed backup explains itself', (tester) async {
      await teams.save(_team('a'));
      final files = await pump(tester);
      files.failShare = true;
      await tester.tap(find.text('Create backup'));
      await settle(tester);
      expect(find.textContaining('Could not back up'), findsOneWidget);
    });

    testWidgets('restores after confirming what the file holds', (tester) async {
      final raw = Backup(matches: const [], teams: [_team('a')], tournaments: const []).encode(now);
      final files = await pump(tester);
      files.fileToPick = raw;

      await tester.tap(find.text('Restore from a file'));
      await settle(tester);
      expect(find.textContaining('0 matches, 1 team and 0 tournaments'), findsOneWidget);

      await tester.tap(find.text('Restore'));
      await settle(tester);

      expect(teams.teams.keys, ['a']);
      expect(find.text('Added 0 matches, 1 team and 0 tournaments.'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation changes nothing', (tester) async {
      final files = await pump(tester);
      files.fileToPick =
          Backup(matches: const [], teams: [_team('a')], tournaments: const []).encode(now);
      await tester.tap(find.text('Restore from a file'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(teams.teams, isEmpty);
    });

    testWidgets('cancelling the file picker does nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Restore from a file'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bad file gets a plain message', (tester) async {
      final files = await pump(tester);
      files.fileToPick = 'holiday photos';
      await tester.tap(find.text('Restore from a file'));
      await settle(tester);
      expect(find.text('That file is not a BNP Scorer backup.'), findsOneWidget);
      expect(teams.teams, isEmpty);
    });

    testWidgets('restoring what is already here says so', (tester) async {
      await teams.save(_team('a'));
      final files = await pump(tester);
      files.fileToPick =
          Backup(matches: const [], teams: [_team('a')], tournaments: const []).encode(now);
      await tester.tap(find.text('Restore from a file'));
      await settle(tester);
      await tester.tap(find.text('Restore'));
      await settle(tester);
      expect(find.text('Everything in that backup is already here.'), findsOneWidget);
    });
  });

  test('dates in file names sort correctly', () {
    expect(isoDate(DateTime(2026, 3, 9)), '2026-03-09');
  });
}
