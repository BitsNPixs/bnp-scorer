import 'package:bnp_scorer/app.dart';
import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/app_settings.dart';
import 'package:bnp_scorer/data/scheduled_match.dart';
import 'package:bnp_scorer/screens/new_match_screen.dart';
import 'package:bnp_scorer/screens/tournament_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/state/upcoming.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/format.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _settle = Duration(milliseconds: 400);

Team _squad(String id, String name) => Team(
      id: id,
      name: name,
      players: [for (var i = 1; i <= 3; i++) Player(id: '$id-$i', name: '$name P$i')],
    );

final _alpha = _squad('a', 'Alpha');
final _bravo = _squad('b', 'Bravo');
final _charlie = _squad('c', 'Charlie');

Tournament _cup({String? venue}) => Tournament(
      id: 't',
      name: 'Cup',
      oversPerInnings: 6,
      hasFinal: false,
      venue: venue,
      teams: [_alpha, _bravo, _charlie],
      fixtures: roundRobinFixtures([_alpha, _bravo, _charlie]),
      createdAt: DateTime.utc(2026),
    );

ScheduledMatch _friendly(DateTime startsAt, {String id = 's1', String? venue}) => ScheduledMatch(
      id: id,
      teamA: _alpha,
      teamB: _bravo,
      oversPerInnings: 8,
      startsAt: startsAt,
      createdAt: DateTime.utc(2026),
      venue: venue,
    );

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  group('upcomingMatches', () {
    final now = DateTime(2026, 11, 20, 12);

    test('lists dated fixtures not started and friendlies, soonest first', () {
      final cup = _cup()
          .withFixtureDate('f1', DateTime(2026, 11, 22, 9))
          .withFixtureDate('f2', DateTime(2026, 11, 21, 9))
          .withFixtureDate('f3', DateTime(2026, 11, 23, 9))
          .withMatch('f3', 'm3');
      final list = upcomingMatches([cup], [_friendly(DateTime(2026, 11, 21, 18))], now);
      expect([for (final u in list) u.id], ['t/f2', 's1', 't/f1'],
          reason: 'a started fixture and an undated one are not upcoming');
    });

    test('keeps a match for 12 hours after its start, then drops it', () {
      final list = upcomingMatches(const [], [
        _friendly(now.subtract(const Duration(hours: 11)), id: 'this-morning'),
        _friendly(now.subtract(const Duration(hours: 13)), id: 'last-night'),
      ], now);
      expect([for (final u in list) u.id], ['this-morning']);
    });

    test('names, ground and overs come from the fixture or the friendly', () {
      final cup = _cup(venue: 'Oval').withFixtureVenue('f2', 'Park');
      final fixture = UpcomingMatch.fixture(cup, cup.fixtures[0]);
      expect(fixture.title, 'Cup · Match 1');
      expect(fixture.venue, 'Oval');
      expect(UpcomingMatch.fixture(cup, cup.fixtures[1]).venue, 'Park');
      expect(fixture.overs, 6);

      final friendly = UpcomingMatch.friendly(_friendly(now, venue: 'Maidan'));
      expect((friendly.homeName, friendly.awayName, friendly.title), ('Alpha', 'Bravo', 'Friendly'));
      expect(friendly.venue, 'Maidan');
      expect(friendly.overs, 8);
    });
  });

  group('ScheduledMatch', () {
    test('survives a round trip, and a blank ground clears it', () {
      final match = _friendly(DateTime.utc(2026, 11, 21, 12, 30), venue: 'Maidan');
      final back = ScheduledMatch.fromJson(match.toJson());
      expect(back.toJson(), match.toJson());
      expect(back.withVenue('  ').venue, isNull);
      expect(back.withStart(DateTime.utc(2026, 12, 1)).startsAt, DateTime.utc(2026, 12, 1));
    });

    test('are stored on the phone, soonest first', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = LocalScheduleRepository(await SharedPreferences.getInstance());
      await repository.save(_friendly(DateTime.utc(2026, 11, 25), id: 'later'));
      await repository.save(_friendly(DateTime.utc(2026, 11, 21), id: 'sooner'));
      expect([for (final s in await repository.loadAll()) s.id], ['sooner', 'later']);
      await repository.delete('sooner');
      expect([for (final s in await repository.loadAll()) s.id], ['later']);
    });
  });

  group('wording', () {
    final now = DateTime(2026, 11, 20, 12);

    test('says today and tomorrow, then the date', () {
      expect(upcomingWhen(DateTime(2026, 11, 20, 18), now), 'Today, 6:00 PM');
      expect(upcomingWhen(DateTime(2026, 11, 21, 9), now), 'Tomorrow, 9:00 AM');
      expect(upcomingWhen(DateTime(2026, 11, 24, 9, 30), now), 'Tue 24 Nov, 9:30 AM');
    });

    test('an invite names the teams, what it is, when, where and the overs', () {
      final text = inviteText(UpcomingMatch.friendly(_friendly(DateTime(2026, 11, 21, 18), venue: 'Maidan')));
      expect(text.split('\n'), [
        '\u{1F3CF} Alpha v Bravo',
        'Friendly',
        'Sat 21 Nov, 6:00 PM',
        'Maidan',
        '8 overs a side. Follow it ball by ball on BNP Scorer.',
      ]);
    });
  });

  group('on screen', () {
    late InMemoryMatchRepository matches;
    late InMemoryTeamRepository teams;
    late InMemoryTournamentRepository tournaments;
    late InMemoryScheduleRepository schedules;
    late TextShares shares;

    setUp(() {
      matches = InMemoryMatchRepository();
      teams = InMemoryTeamRepository();
      tournaments = InMemoryTournamentRepository();
      schedules = InMemoryScheduleRepository();
      shares = TextShares();
    });

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(_settle);
      }
    }

    Future<void> pump(WidgetTester tester, Widget home, {Accounts? accounts}) async {
      tester.view
        ..physicalSize = const Size(1080, 6000)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appSettingsProvider.overrideWithValue(AppSettings(prefs)),
          matchRepositoryProvider.overrideWithValue(matches),
          teamRepositoryProvider.overrideWithValue(teams),
          tournamentRepositoryProvider.overrideWithValue(tournaments),
          scheduleRepositoryProvider.overrideWithValue(schedules),
          deviceFilesProvider.overrideWithValue(shares),
          if (accounts != null) accountsProvider.overrideWithValue(accounts),
        ],
        child: home is BnpScorerApp ? home : MaterialApp(theme: AppTheme.light(), home: home),
      ));
      await settle(tester);
    }

    DateTime tomorrowAt(int hour) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day + 1, hour);
    }

    testWidgets('Schedule for later saves the teams, overs and ground, without starting', (tester) async {
      await teams.save(_alpha);
      await teams.save(_bravo);
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NewMatchScreen())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        accounts: FakeAccounts(signedIn: const Scorer(uid: 'u1', name: 'Asha Scorer')),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      for (final (side, team) in [(0, 'Alpha'), (1, 'Bravo')]) {
        final button = find.text('Saved teams', skipOffstage: false).at(side);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await settle(tester);
        await tester.tap(find.widgetWithText(ListTile, team));
        await settle(tester);
      }
      await tester.enterText(find.byType(TextField).last, 'Maidan');
      await tester.tap(find.text('Schedule for later'));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);

      expect(matches.records, isEmpty, reason: 'no toss yet, so no match');
      final saved = schedules.schedules.values.single;
      expect((saved.teamA.id, saved.teamB.id), ('a', 'b'));
      expect(saved.oversPerInnings, 10);
      expect(saved.venue, 'Maidan');
      expect(saved.publishedBy, 'u1');
      expect(find.text('open'), findsOneWidget, reason: 'back where it was opened');
      expect(find.textContaining('Scheduled for'), findsOneWidget);
    });

    testWidgets('Matches shows what is coming up, and a friendly can be invited to or cancelled', (tester) async {
      await schedules.save(_friendly(tomorrowAt(18), venue: 'Maidan'));
      await tournaments.save(_cup().withFixtureDate('f1', tomorrowAt(20)));
      await pump(tester, const BnpScorerApp());

      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Tomorrow, 6:00 PM'), findsOneWidget);
      expect(find.text('Tomorrow, 8:00 PM'), findsOneWidget);
      expect(find.text('Friendly · Maidan'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Friendly · Maidan'));
      await settle(tester);
      await tester.tap(find.text('Send invite'));
      await settle(tester);
      expect(shares.text, startsWith('\u{1F3CF} Alpha v Bravo\nFriendly'));

      await tester.tap(find.text('Friendly · Maidan'));
      await settle(tester);
      await tester.tap(find.text('Cancel this match'));
      await settle(tester);
      expect(schedules.schedules, isEmpty);
      expect(find.text('Tomorrow, 6:00 PM'), findsNothing);
      expect(find.text('Tomorrow, 8:00 PM'), findsOneWidget, reason: 'the fixture is still coming up');
    });

    testWidgets('starting a friendly fills in New match and removes it from Upcoming', (tester) async {
      await teams.save(_alpha);
      await teams.save(_bravo);
      await schedules.save(_friendly(tomorrowAt(18)));
      await pump(tester, const BnpScorerApp());

      await tester.tap(find.text('Friendly'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Start match'));
      await settle(tester);
      expect(find.byType(NewMatchScreen), findsOneWidget);
      expect(find.text('8'), findsWidgets, reason: 'the overs come from the schedule');
      expect(find.text('Schedule for later'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Start match'));
      await settle(tester);
      final setup = matches.records.values.single.setup;
      expect((setup.teamA.id, setup.teamB.id), ('a', 'b'));
      expect(setup.rules.oversPerInnings, 8);
      expect(schedules.schedules, isEmpty);
    });

    testWidgets('a match past its time but not started says since when', (tester) async {
      final earlier = DateTime.now().subtract(const Duration(hours: 1));
      await schedules.save(_friendly(earlier));
      await pump(tester, const BnpScorerApp());
      expect(find.text('Due since ${clockTime(earlier)}'), findsOneWidget);
    });

    testWidgets('a fixture\'s ground is changed from its sheet and shown on its card', (tester) async {
      await tournaments.save(_cup().withFixtureDate('f1', DateTime(2026, 12, 5, 9)));
      await pump(tester, const TournamentScreen(tournamentId: 't'));

      await tester.longPress(find.text('MATCH 1'));
      await settle(tester);
      await tester.tap(find.text('Change ground'));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('ground')), 'Park');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(tournaments.tournaments['t']!.fixtures.first.venue, 'Park');
      expect(find.text('Sat 5 Dec, 9:00 AM · Park'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
