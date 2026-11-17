import 'package:bnp_scorer/app.dart';
import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/app_settings.dart';
import 'package:bnp_scorer/data/cloud_cups.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/data/scheduled_match.dart';
import 'package:bnp_scorer/data/syncing_cups.dart';
import 'package:bnp_scorer/screens/new_tournament_screen.dart';
import 'package:bnp_scorer/screens/watch_match_screen.dart';
import 'package:bnp_scorer/screens/watch_tournament_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/prizes_tab.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);
const _asha = Scorer(uid: 'u1', name: 'Asha Organiser');
const _bilal = Scorer(uid: 'u2', name: 'Bilal');

Team _squad(String id, String name) => Team(
      id: id,
      name: name,
      players: [for (var i = 1; i <= 3; i++) Player(id: '$id-$i', name: '$name P$i')],
    );

final _teams = [_squad('a', 'Alpha'), _squad('b', 'Bravo'), _squad('c', 'Charlie')];

/// A three-team cup with prizes and a fee, Alpha part paid, published by [by].
Tournament _cup({String? by = 'u1', DateTime? firstMatch}) {
  var t = Tournament(
    id: 'cup',
    name: 'Night Cup',
    oversPerInnings: 1,
    hasFinal: true,
    format: TournamentFormat.knockout,
    teams: _teams,
    fixtures: knockoutFixtures([for (final t in _teams) t.id]),
    createdAt: DateTime.utc(2026),
    publishedBy: by,
  ).withDetails(
    prizes: const [Prize(title: 'Winner', reward: '₹10,000 + trophy')],
    entryFee: 2000,
    rules: 'Tennis ball',
  ).withPaid('a', 500);
  if (firstMatch != null) t = t.withFixtureDate('sf1', firstMatch);
  return t;
}

ScheduledMatch _friendly(DateTime startsAt, {String? by = 'u1'}) => ScheduledMatch(
      id: 's1',
      teamA: _teams[0],
      teamB: _teams[1],
      oversPerInnings: 8,
      startsAt: startsAt,
      createdAt: DateTime.utc(2026),
      publishedBy: by,
    );

/// A finished one-over match that Bravo wins, as published by its scorer.
MatchRecord _played(String id) {
  final at = DateTime.utc(2026);
  final setup = MatchSetup(
    id: id,
    teamA: _teams[1],
    teamB: _teams[2],
    rules: MatchRules(oversPerInnings: 1),
    tossWinnerId: 'b',
    tossDecision: TossDecision.bat,
  );
  var n = 0;
  List<MatchEvent> innings(Team bat, Team bowl, int run) => [
        OpenersSelected(id: 'e${n++}', at: at, strikerId: bat.players[0].id, nonStrikerId: bat.players[1].id),
        BowlerChanged(id: 'e${n++}', at: at, bowlerId: bowl.players[0].id),
        for (var i = 0; i < 6; i++) BallBowled(id: 'e${n++}', at: at, runsOffBat: run),
      ];
  return MatchRecord(
    setup: setup,
    events: [...innings(_teams[1], _teams[2], 2), ...innings(_teams[2], _teams[1], 0)],
    createdAt: at,
    updatedAt: at,
    publishedBy: 'u1',
  );
}

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  group('publishing', () {
    test('a tournament goes out only from its signed-in organiser, never with payments', () async {
      final cloud = FakeCloudCups();
      final local = InMemoryTournamentRepository();
      final accounts = FakeAccounts(signedIn: _asha);
      final repository = SyncingTournamentRepository(local, cloud, accounts);

      await repository.save(_cup());
      await pumpEventQueue();
      expect(local.tournaments['cup']!.paidBy('a'), 500, reason: 'the phone keeps the payments');
      expect(cloud.sentTournaments['cup']!.containsKey('paid'), isFalse);
      expect(cloud.tournaments['cup']!.ownerName, 'Asha Organiser');
      expect(cloud.tournaments['cup']!.tournament.prizes.single.reward, '₹10,000 + trophy');

      await repository.save(Tournament.fromJson({..._cup(by: null).toJson(), 'id': 'private'}));
      await repository.save(Tournament.fromJson({..._cup().toJson(), 'id': 'other', 'publishedBy': 'u2'}));
      await pumpEventQueue();
      expect(cloud.tournaments.keys, ['cup'], reason: 'not a private one, nor one from another account');

      await repository.save(local.tournaments['cup']!.withMatch('sf1', 'm1'));
      await pumpEventQueue();
      expect(cloud.tournaments['cup']!.tournament.fixtures.first.matchId, 'm1', reason: 'every change goes out');

      await repository.delete('cup');
      await pumpEventQueue();
      expect(cloud.tournaments, isEmpty);
    });

    test('signed out, nothing is sent', () async {
      final cloud = FakeCloudCups();
      final repository = SyncingTournamentRepository(InMemoryTournamentRepository(), cloud, FakeAccounts());
      await repository.save(_cup());
      await pumpEventQueue();
      expect(cloud.tournaments, isEmpty);
    });

    test('a scheduled friendly is published, and cancelling it takes it down', () async {
      final cloud = FakeCloudCups();
      final repository = SyncingScheduleRepository(InMemoryScheduleRepository(), cloud, FakeAccounts(signedIn: _asha));
      await repository.save(_friendly(DateTime.utc(2030)));
      await repository.save(ScheduledMatch.fromJson({..._friendly(DateTime.utc(2030)).toJson(), 'id': 's2', 'publishedBy': null}));
      await pumpEventQueue();
      expect(cloud.schedules.keys, ['s1']);
      expect(cloud.schedules['s1']!.schedule.publishedBy, isNull, reason: 'the owner field says who it is');

      await repository.delete('s1');
      await pumpEventQueue();
      expect(cloud.schedules, isEmpty);
    });

    test('reading refuses a newer format and drops payments if any arrive', () {
      final json = {..._cup().toJson(), 'ownerUid': 'u1', 'ownerName': 'Asha', 'schema': 1};
      expect(parsePublishedTournament(json).tournament.paid, isEmpty);
      expect(() => parsePublishedTournament({...json, 'schema': FirestoreCloudCups.schema + 1}), throwsFormatException);
      final schedule = {..._friendly(DateTime.utc(2030)).toJson(), 'ownerUid': 'u1', 'schema': 1};
      expect(parsePublishedSchedule(schedule).ownerName, 'A scorer');
    });
  });

  group('on screen', () {
    late FakeCloudCups cups;
    late FakeCloudMatches matches;

    setUp(() {
      cups = FakeCloudCups();
      matches = FakeCloudMatches();
    });

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(_settle);
      }
    }

    Future<void> pump(WidgetTester tester, Widget home, {Accounts? accounts, TournamentRepositoryHolder? holder}) async {
      tester.view
        ..physicalSize = const Size(1080, 6000)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings(prefs)),
          matchRepositoryProvider.overrideWithValue(InMemoryMatchRepository()),
          teamRepositoryProvider.overrideWithValue(holder?.teams ?? InMemoryTeamRepository()),
          tournamentRepositoryProvider.overrideWithValue(holder?.tournaments ?? InMemoryTournamentRepository()),
          scheduleRepositoryProvider.overrideWithValue(InMemoryScheduleRepository()),
          cloudMatchesProvider.overrideWithValue(matches),
          cloudCupsProvider.overrideWithValue(cups),
          accountsProvider.overrideWithValue(accounts ?? FakeAccounts()),
        ],
        child: home is BnpScorerApp ? home : MaterialApp(theme: AppTheme.light(), home: home),
      ));
      await settle(tester);
    }

    Future<void> showEveryone(WidgetTester tester) async {
      await tester.tap(find.text('Everyone'));
      await settle(tester);
    }

    testWidgets('a tournament created while signed in is marked for publishing', (tester) async {
      final holder = TournamentRepositoryHolder();
      for (final t in _teams) {
        await holder.teams.save(t);
      }
      await pump(tester, const NewTournamentScreen(), accounts: FakeAccounts(signedIn: _bilal), holder: holder);
      await tester.enterText(find.byType(TextField).first, 'Open Cup');
      for (final t in _teams) {
        await tester.tap(find.text(t.name));
      }
      await tester.pump(_settle);
      await tester.tap(find.text('Create tournament'));
      await settle(tester);
      expect(holder.tournaments.tournaments.values.single.publishedBy, 'u2');
    });

    testWidgets('Everyone lists upcoming matches and cups, with invite and the cup to open', (tester) async {
      final soon = DateTime.now().add(const Duration(days: 1));
      await cups.publishTournament(_cup(firstMatch: soon), _asha);
      await cups.publishSchedule(_friendly(soon.add(const Duration(hours: 2))), _bilal);
      await pump(tester, const BnpScorerApp());
      await showEveryone(tester);

      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Cups'), findsOneWidget);
      expect(find.text('Night Cup'), findsOneWidget);
      expect(find.text('3 teams · Knockout cup'), findsOneWidget);
      expect(find.text('By Asha Organiser'), findsOneWidget);
      expect(find.text('Night Cup · Semi-final'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Night Cup · Semi-final'));
      await settle(tester);
      expect(find.text('Start match'), findsNothing, reason: 'only the organiser starts it');
      expect(find.text('Change time'), findsNothing);
      expect(find.text('Send invite'), findsOneWidget);
      await tester.tap(find.text('Open the cup'));
      await settle(tester);
      expect(find.byType(WatchTournamentScreen), findsOneWidget);
    });

    testWidgets('watching a cup is read-only and leaves out payments', (tester) async {
      await cups.publishTournament(_cup(), _asha);
      await pump(tester, const WatchTournamentScreen(tournamentId: 'cup'));

      expect(find.textContaining('Organised by Asha Organiser'), findsOneWidget);
      expect(find.text('Not started'), findsWidgets);
      expect(find.text('Tap to start'), findsNothing);
      expect(find.textContaining('Set up'), findsNothing);

      final prizes = find.descendant(of: find.byType(TabBar), matching: find.text('Prizes'));
      await tester.ensureVisible(prizes);
      await tester.tap(prizes);
      await settle(tester);
      expect(find.text('₹10,000 + trophy'), findsOneWidget);
      expect(find.text('₹2,000 a team'), findsOneWidget);
      expect(find.text(PrizesTab.privateNote), findsNothing);
      expect(find.text('Not paid'), findsNothing);
      expect(find.text('Edit prizes, fee and rules'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a played match in a watched cup opens to watch, and its winner goes through', (tester) async {
      await matches.publish(_played('m1'), _asha);
      await cups.publishTournament(_cup().withMatch('sf1', 'm1'), _asha);
      await pump(tester, const WatchTournamentScreen(tournamentId: 'cup'));
      expect(find.text('Bravo won by 12 runs'), findsOneWidget);

      await tester.tap(find.text('Bracket'));
      await settle(tester);
      expect(find.text('Teams known'), findsOneWidget, reason: 'the final can now be set up by the organiser');

      await tester.tap(find.text('Matches'));
      await settle(tester);
      await tester.tap(find.text('Bravo won by 12 runs'));
      await settle(tester);
      expect(find.byType(WatchMatchScreen), findsOneWidget);
    });

    testWidgets('an unpublished or unreadable cup says so', (tester) async {
      await pump(tester, const WatchTournamentScreen(tournamentId: 'cup'));
      expect(find.text(WatchTournamentScreen.goneMessage), findsOneWidget);

      await cups.publishTournament(_cup(), _asha);
      cups.unreadable.add('cup');
      await tester.pumpWidget(const SizedBox());
      await pump(tester, const WatchTournamentScreen(tournamentId: 'cup'));
      expect(find.text(WatchTournamentScreen.unreadableMessage), findsOneWidget);
    });
  });
}

/// The repositories a test wants to look into afterwards.
class TournamentRepositoryHolder {
  final teams = InMemoryTeamRepository();
  final tournaments = InMemoryTournamentRepository();
}
