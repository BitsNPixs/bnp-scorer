import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/data/ids.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/data/tournament_repository.dart';
import 'package:bnp_scorer/screens/home_screen.dart';
import 'package:bnp_scorer/screens/new_tournament_screen.dart';
import 'package:bnp_scorer/screens/tournament_screen.dart';
import 'package:bnp_scorer/screens/tournaments_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
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
      players: [
        for (var i = 1; i <= 3; i++) Player(id: '$id-$i', name: '$name P$i'),
      ],
    );

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  late InMemoryMatchRepository matches;
  late InMemoryTeamRepository teams;
  late InMemoryTournamentRepository tournaments;

  setUp(() {
    matches = InMemoryMatchRepository();
    teams = InMemoryTeamRepository();
    tournaments = InMemoryTournamentRepository();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(_settle);
    }
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view
      // 360 dp wide, and tall enough that the lazy lists build everything.
      ..physicalSize = const Size(1080, 6000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        matchRepositoryProvider.overrideWithValue(matches),
        teamRepositoryProvider.overrideWithValue(teams),
        tournamentRepositoryProvider.overrideWithValue(tournaments),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    ));
    await settle(tester);
  }

  Tournament threeTeams({bool hasFinal = false}) {
    final list = [_squad('a', 'Alpha'), _squad('b', 'Bravo'), _squad('c', 'Charlie')];
    return Tournament(
      id: 't',
      name: 'Cup',
      oversPerInnings: 4,
      hasFinal: hasFinal,
      venue: 'Oval',
      teams: list,
      fixtures: roundRobinFixtures(list),
      createdAt: DateTime.utc(2026),
    );
  }

  /// A finished one-over match that [winner] wins, saved and linked to [fixture].
  Future<void> playFixture(Tournament start, String fixtureId, String winner) async {
    final t = tournaments.tournaments[start.id] ?? start;
    final f = t.fixtures.firstWhere((x) => x.id == fixtureId);
    final first = t.teamById(winner);
    final second = t.teamById(winner == f.teamAId ? f.teamBId : f.teamAId);
    final setup = MatchSetup(
      id: 'match-$fixtureId',
      teamA: first,
      teamB: second,
      rules: MatchRules(oversPerInnings: 1),
      tossWinnerId: first.id,
      tossDecision: TossDecision.bat,
    );
    final at = DateTime.utc(2026);
    List<MatchEvent> innings(Team bat, Team bowl, int run) => [
          OpenersSelected(id: newId(), at: at, strikerId: bat.players[0].id, nonStrikerId: bat.players[1].id),
          BowlerChanged(id: newId(), at: at, bowlerId: bowl.players[0].id),
          for (var i = 0; i < 6; i++) BallBowled(id: newId(), at: at, runsOffBat: run),
        ];
    await matches.save(MatchRecord(
      setup: setup,
      events: [...innings(first, second, 2), ...innings(second, first, 0)],
      createdAt: at,
      updatedAt: at,
    ));
    await tournaments.save(t.withMatch(fixtureId, setup.id));
  }

  testWidgets('home opens the tournaments list', (tester) async {
    await pump(tester, const HomeScreen());
    await tester.tap(find.byTooltip('Tournaments'));
    await settle(tester);
    expect(find.text('New tournament'), findsOneWidget);
    expect(find.textContaining('No tournaments yet'), findsOneWidget);
  });

  group('creating', () {
    testWidgets('picks teams and generates the fixtures', (tester) async {
      await teams.save(_squad('a', 'Alpha'));
      await teams.save(_squad('b', 'Bravo'));
      await teams.save(_squad('c', 'Charlie'));
      await pump(tester, const NewTournamentScreen());

      expect(find.text('Give the tournament a name'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Spring Cup');
      await tester.pump(_settle);
      expect(find.text('Choose at least 2 teams'), findsOneWidget);

      await tester.tap(find.text('Alpha'));
      await tester.tap(find.text('Bravo'));
      await tester.tap(find.text('Charlie'));
      await tester.pump(_settle);
      expect(find.text('3 matches + final'), findsOneWidget);

      await tester.tap(find.text('Create tournament'));
      await settle(tester);

      final saved = tournaments.tournaments.values.single;
      expect(saved.name, 'Spring Cup');
      expect(saved.hasFinal, isTrue);
      expect(saved.fixtures, hasLength(3));
      expect(find.text('Tap to start'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('two teams cannot have a final', (tester) async {
      await teams.save(_squad('a', 'Alpha'));
      await teams.save(_squad('b', 'Bravo'));
      await pump(tester, const NewTournamentScreen());
      await tester.enterText(find.byType(TextField).first, 'Duel');
      await tester.tap(find.text('Alpha'));
      await tester.tap(find.text('Bravo'));
      await tester.pump(_settle);

      expect(find.text('1 match'), findsOneWidget);
      await tester.tap(find.text('Create tournament'));
      await settle(tester);
      expect(tournaments.tournaments.values.single.hasFinal, isFalse);
    });

    testWidgets('without saved teams it says how to get some', (tester) async {
      await pump(tester, const NewTournamentScreen());
      expect(find.textContaining('Teams are saved when they play'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed save stays on the form with a message', (tester) async {
      await teams.save(_squad('a', 'Alpha'));
      await teams.save(_squad('b', 'Bravo'));
      await pump(tester, const NewTournamentScreen());
      await tester.enterText(find.byType(TextField).first, 'Duel');
      await tester.tap(find.text('Alpha'));
      await tester.tap(find.text('Bravo'));
      await tester.pump(_settle);

      tournaments.failSaves = true;
      await tester.tap(find.text('Create tournament'));
      await settle(tester);

      expect(find.textContaining('Could not save the tournament'), findsOneWidget);
      expect(find.text('Create tournament'), findsOneWidget);
    });
  });

  group('playing', () {
    testWidgets('a fixture opens setup filled in, and its match is linked', (tester) async {
      final t = threeTeams();
      await tournaments.save(t);
      await pump(tester, const TournamentScreen(tournamentId: 't'));

      await tester.tap(find.text('Tap to start').first);
      await settle(tester);

      expect(find.text('New match'), findsOneWidget);
      expect(find.text('Saved teams'), findsNothing, reason: 'the fixture fixes the teams');
      expect(find.text('Cup Match 1 · Oval'), findsOneWidget);

      await tester.tap(find.text('Start match'));
      await settle(tester);

      final record = matches.records.values.single;
      expect(record.setup.rules.oversPerInnings, 4);
      expect(record.setup.teamA.id, t.fixtures.first.teamAId);
      expect(tournaments.tournaments['t']!.fixtures.first.matchId, record.id);
      expect(teams.teams, hasLength(2), reason: 'tournament squads are remembered');
    });

    testWidgets('a finished fixture shows its result and table points', (tester) async {
      final t = threeTeams();
      await tournaments.save(t);
      await playFixture(t, 'f1', t.fixtures.first.teamAId);
      await pump(tester, const TournamentScreen(tournamentId: 't'));

      expect(find.textContaining('won by'), findsOneWidget);
      await tester.tap(find.text('Table'));
      await settle(tester);
      expect(find.textContaining('P 1 · W 1 · L 0'), findsOneWidget);
      expect(find.text('2'), findsWidgets, reason: 'two points for the win');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a league ends with a final, then a champion', (tester) async {
      final t = threeTeams(hasFinal: true);
      await tournaments.save(t);
      for (final f in t.fixtures) {
        await playFixture(t, f.id, f.teamAId == 'a' || f.teamBId == 'a' ? 'a' : 'b');
      }
      await pump(tester, const TournamentScreen(tournamentId: 't'));

      await tester.tap(find.text('Set up the final: Alpha v Bravo'));
      await settle(tester);
      expect(tournaments.tournaments['t']!.finalFixture, isNotNull);
      expect(find.text('FINAL'), findsOneWidget);
      expect(find.text('CHAMPIONS'), findsNothing);

      await playFixture(t, 'final', 'b');
      await tester.pumpWidget(const SizedBox()); // a fresh ProviderScope
      await pump(tester, const TournamentsScreen());
      expect(find.textContaining('Winner: Bravo'), findsOneWidget);
    });

    testWidgets('a tournament can be deleted, keeping its matches', (tester) async {
      final t = threeTeams();
      await tournaments.save(t);
      await playFixture(t, 'f1', t.fixtures.first.teamAId);
      await pump(tester, const TournamentsScreen());

      await tester.longPress(find.text('Cup'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(tournaments.tournaments, isEmpty);
      expect(matches.records, hasLength(1));
    });
  });

  testWidgets('the demo tournaments fit at 360 dp', (tester) async {
    final now = DateTime.utc(2026, 11, 6);
    await seedDemoMatches(matches, now: now);
    await seedDemoTournaments(tournaments, now: now);
    await pump(tester, const TournamentsScreen());

    expect(find.textContaining('Winner:'), findsNWidgets(4));
    await tester.tap(find.text('Monsoon League'));
    await settle(tester);

    expect(find.text('CHAMPIONS'), findsOneWidget);
    expect(find.text('Team C'), findsOneWidget);
    await tester.tap(find.text('Table'));
    await settle(tester);
    await tester.tap(find.text('Batting'));
    await settle(tester);
    await tester.tap(find.text('Bowling'));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  test('tournaments survive local storage, newest first', () async {
    SharedPreferences.setMockInitialValues({
      'bnp_scorer.tournamentIds': ['bad'],
      'bnp_scorer.tournament.bad': '{not json',
    });
    final repo = LocalTournamentRepository(await SharedPreferences.getInstance());
    expect(await repo.loadAll(), isEmpty);

    final old = threeTeams();
    await repo.save(old);
    final newer = Tournament.fromJson({...old.toJson(), 'id': 'n', 'createdAt': '2026-06-01T00:00:00Z'});
    await repo.save(newer);
    expect((await repo.loadAll()).map((t) => t.id), ['n', 't']);

    await repo.delete('n');
    expect((await repo.loadAll()).map((t) => t.id), ['t']);
  });
}
