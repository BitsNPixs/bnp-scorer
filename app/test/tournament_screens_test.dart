import 'dart:math';

import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/data/ids.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/data/tournament_repository.dart';
import 'package:bnp_scorer/screens/home_screen.dart';
import 'package:bnp_scorer/screens/new_tournament_screen.dart';
import 'package:bnp_scorer/screens/tournament_details_screen.dart';
import 'package:bnp_scorer/screens/tournament_screen.dart';
import 'package:bnp_scorer/screens/tournaments_screen.dart';
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
const _names = ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot', 'Golf', 'Hotel'];

(String, String) _pair(Fixture f) => (f.teamAId, f.teamBId);

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

  /// Saves the first [count] of [_names] as squads with ids a, b, c...
  Future<void> saveTeams(int count) async {
    for (var i = 0; i < count; i++) {
      await teams.save(_squad(String.fromCharCode(97 + i), _names[i]));
    }
  }

  /// A knockout cup of the first [count] of [_names], in that draw order.
  Tournament cupOf(int count) {
    final list = [for (var i = 0; i < count; i++) _squad(String.fromCharCode(97 + i), _names[i])];
    return Tournament(
      id: 't',
      name: 'Cup',
      oversPerInnings: 4,
      hasFinal: true,
      format: TournamentFormat.knockout,
      teams: list,
      fixtures: knockoutFixtures([for (final t in list) t.id]),
      createdAt: DateTime.utc(2026),
    );
  }

  /// A finished one-over match that [winner] wins, saved and linked to [fixture].
  Future<void> playFixture(
    Tournament start,
    String fixtureId,
    String winner, {
    bool tied = false,
    bool superOver = false,
  }) async {
    final t = tournaments.tournaments[start.id] ?? start;
    final f = t.fixtures.firstWhere((x) => x.id == fixtureId);
    final first = t.teamById(winner);
    final second = t.teamById(winner == f.teamAId ? f.teamBId : f.teamAId);
    final setup = MatchSetup(
      id: 'match-$fixtureId',
      teamA: first,
      teamB: second,
      rules: MatchRules(oversPerInnings: 1, superOver: superOver),
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
      events: [...innings(first, second, 2), ...innings(second, first, tied ? 2 : 0)],
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

    testWidgets('two groups, home and away, with semi-finals', (tester) async {
      for (final (id, name) in [('a', 'Alpha'), ('b', 'Bravo'), ('c', 'Charlie'), ('d', 'Delta')]) {
        await teams.save(_squad(id, name));
      }
      await pump(tester, const NewTournamentScreen());
      await tester.enterText(find.byType(TextField).first, 'Grand');
      for (final name in ['Alpha', 'Bravo', 'Charlie', 'Delta']) {
        await tester.tap(find.text(name));
      }
      await tester.pump(_settle);
      expect(find.text('6 matches + final'), findsOneWidget);

      await tester.tap(find.text('Two groups'));
      await tester.pump(_settle);
      expect(find.text('A: Alpha, Charlie\nB: Bravo, Delta'), findsOneWidget);
      expect(find.text('2 matches + final'), findsOneWidget);

      await tester.tap(find.text('Home and away'));
      await tester.tap(find.text('Semis'));
      await tester.pump(_settle);
      expect(find.text('4 matches + semi-finals + final'), findsOneWidget);

      await tester.tap(find.text('Create tournament'));
      await settle(tester);

      final saved = tournaments.tournaments.values.single;
      expect(saved.groups, hasLength(2));
      expect(saved.legs, 2);
      expect(saved.hasSemiFinals, isTrue);
      expect(saved.fixtures.first.label, 'Group A Match 1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving enough teams keeps the format valid', (tester) async {
      for (final (id, name) in [('a', 'Alpha'), ('b', 'Bravo'), ('c', 'Charlie'), ('d', 'Delta')]) {
        await teams.save(_squad(id, name));
      }
      await pump(tester, const NewTournamentScreen());
      await tester.enterText(find.byType(TextField).first, 'Shrinking');
      for (final name in ['Alpha', 'Bravo', 'Charlie', 'Delta']) {
        await tester.tap(find.text(name));
      }
      await tester.pump(_settle); // Semis is offered once there are 4 teams.
      await tester.tap(find.text('Semis'));
      await tester.pump(_settle);
      await tester.tap(find.text('Two groups'));
      await tester.pump(_settle);

      await tester.tap(find.text('Delta'));
      await tester.pump(_settle);
      expect(find.text('3 matches + final'), findsOneWidget);

      await tester.tap(find.text('Create tournament'));
      await settle(tester);

      final saved = tournaments.tournaments.values.single;
      expect(saved.groups, hasLength(1));
      expect(saved.hasSemiFinals, isFalse);
      expect(saved.hasFinal, isTrue);
    });

    testWidgets('a knockout cup shows its draw, with byes, and saves in that order', (tester) async {
      await saveTeams(5);
      await pump(tester, const NewTournamentScreen());
      await tester.enterText(find.byType(TextField).first, 'Night Cup');
      for (final name in ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo']) {
        await tester.tap(find.text(name));
      }
      await tester.tap(find.text('Knockout cup'));
      await tester.pump(_settle);

      expect(find.text('Two groups'), findsNothing, reason: 'league options are hidden for a cup');
      expect(find.text('4 matches · 3 byes'), findsOneWidget);
      expect(find.text('Delta v Echo'), findsOneWidget);
      expect(find.text('Byes: Alpha, Bravo, Charlie'), findsOneWidget);

      await tester.tap(find.text('Create tournament'));
      await settle(tester);
      final saved = tournaments.tournaments.values.single;
      expect(saved.isKnockout, isTrue);
      expect([for (final t in saved.teams) t.name], ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo']);
      expect([for (final f in saved.fixtures) f.label], ['Quarter-final', 'Semi-final 2']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shuffle draw reorders the cup, keeping the same teams', (tester) async {
      await saveTeams(4);
      await pump(tester, NewTournamentScreen(random: Random(1)));
      await tester.enterText(find.byType(TextField).first, 'Shuffled');
      for (final name in ['Alpha', 'Bravo', 'Charlie', 'Delta']) {
        await tester.tap(find.text(name));
      }
      await tester.tap(find.text('Knockout cup'));
      await tester.pump(_settle);
      expect(find.text('Alpha v Bravo'), findsOneWidget);
      expect(find.text('3 matches'), findsOneWidget);

      await tester.tap(find.text('Shuffle draw'));
      await tester.pump(_settle);
      await tester.tap(find.text('Create tournament'));
      await settle(tester);
      final saved = tournaments.tournaments.values.single;
      final order = [for (final t in saved.teams) t.id];
      expect(order.toSet(), {'a', 'b', 'c', 'd'});
      expect(order, isNot(['a', 'b', 'c', 'd']));
      expect(_pair(saved.fixtures.first), (order[0], order[1]));
    });

    testWidgets('a cup needs three teams', (tester) async {
      await saveTeams(2);
      await pump(tester, const NewTournamentScreen());
      await tester.enterText(find.byType(TextField).first, 'Tiny');
      await tester.tap(find.text('Alpha'));
      await tester.tap(find.text('Bravo'));
      await tester.tap(find.text('Knockout cup'));
      await tester.pump(_settle);
      expect(find.text('A cup needs at least 3 teams'), findsOneWidget);
      await tester.tap(find.text('Create tournament'));
      await settle(tester);
      expect(tournaments.tournaments, isEmpty);
    });

    testWidgets('quarter-finals are offered from eight teams', (tester) async {
      await saveTeams(8);
      await pump(tester, const NewTournamentScreen());
      await tester.enterText(find.byType(TextField).first, 'Big League');
      for (final name in _names.take(7)) {
        await tester.tap(find.text(name));
      }
      await tester.pump(_settle);
      expect(find.text('Quarters'), findsNothing);

      await tester.tap(find.text('Hotel'));
      await tester.pump(_settle);
      await tester.tap(find.text('Quarters'));
      await tester.pump(_settle);
      expect(find.text('28 matches + quarter-finals + semi-finals + final'), findsOneWidget);

      await tester.tap(find.text('Create tournament'));
      await settle(tester);
      final saved = tournaments.tournaments.values.single;
      expect(saved.hasQuarterFinals, isTrue);
      expect(saved.hasSemiFinals, isTrue);
      expect(saved.bracket.first.label, 'Quarter-final 1');
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

    testWidgets('a tied final goes to a Super Over that decides the title', (tester) async {
      final t = threeTeams(hasFinal: true);
      await tournaments.save(t);
      for (final f in t.fixtures) {
        await playFixture(t, f.id, f.teamAId == 'a' || f.teamBId == 'a' ? 'a' : 'b');
      }
      final league = tournaments.tournaments['t']!;
      final byId = {
        for (final m in matches.records.values) m.id: ScoringEngine.replay(m.setup, m.events),
      };
      await tournaments.save(league.withFixtures(progressOf(league, byId).nextRound));
      await playFixture(t, 'final', 'a', tied: true);
      await pump(tester, const TournamentScreen(tournamentId: 't'));

      expect(find.text('Match tied'), findsOneWidget);
      expect(find.text('CHAMPIONS'), findsNothing);
      await tester.tap(find.text('Set up the Super Over: Bravo v Alpha'));
      await settle(tester);

      await tester.tap(find.text('Tap to start'));
      await settle(tester);
      expect(find.text('TOSS'), findsNothing, reason: 'the rules say who bats first');
      expect(find.text('Cup Final Super Over · Oval'), findsOneWidget);

      await tester.tap(find.text('Start match'));
      await settle(tester);

      final record = matches.records.values.firstWhere((m) => m.setup.rules.superOver);
      expect(record.setup.rules.oversPerInnings, 1);
      expect(record.setup.firstBattingTeamId, 'b');
      final fixture = tournaments.tournaments['t']!.fixtures.last;
      expect(fixture.isDecider, isTrue);
      expect(fixture.matchId, record.id);

      await matches.delete(record.id);
      await playFixture(t, fixture.id, 'b', superOver: true);
      await tester.pumpWidget(const SizedBox());
      await pump(tester, const TournamentsScreen());
      expect(find.textContaining('Winner: Bravo'), findsOneWidget);
    });

    testWidgets('a knockout round is offered in one tap, and tables show groups', (tester) async {
      final list = [_squad('a', 'Alpha'), _squad('b', 'Bravo'), _squad('c', 'Charlie'), _squad('d', 'Delta')];
      final groups = splitIntoTwoGroups(list);
      final t = Tournament(
        id: 't',
        name: 'Cup',
        oversPerInnings: 4,
        hasFinal: true,
        hasSemiFinals: true,
        groups: groups,
        teams: list,
        fixtures: leagueFixtures(groups),
        createdAt: DateTime.utc(2026),
      );
      await tournaments.save(t);
      await playFixture(t, 'f1', 'a');
      await playFixture(t, 'f2', 'b');
      await pump(tester, const TournamentScreen(tournamentId: 't'));

      await tester.tap(find.text('Set up the semi-finals'));
      await settle(tester);
      expect(tournaments.tournaments['t']!.fixtures, hasLength(4));
      expect(find.text('SEMI-FINAL 1'), findsOneWidget);
      expect(find.text('Alpha v Delta'), findsOneWidget);
      expect(find.text('Bravo v Charlie'), findsOneWidget);

      await tester.tap(find.text('Table'));
      await settle(tester);
      expect(find.text('GROUP A'), findsOneWidget);
      expect(find.text('GROUP B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cup has a bracket instead of a table, and moves winners on', (tester) async {
      final t = cupOf(5);
      await tournaments.save(t);
      await pump(tester, const TournamentScreen(tournamentId: 't'));
      expect(find.text('Table'), findsNothing);

      await tester.tap(find.text('Bracket'));
      await settle(tester);
      expect(find.text('QUARTER-FINAL'), findsOneWidget);
      expect(find.text('Winner of Quarter-final'), findsOneWidget);
      expect(find.text('Winner of Semi-final 1'), findsOneWidget);
      expect(find.text('bye'), findsNWidgets(3), reason: 'Alpha, Bravo and Charlie skip the first round');
      expect(tester.takeException(), isNull);

      await playFixture(t, 'qf1', 'd');
      await tester.pumpWidget(const SizedBox());
      await pump(tester, const TournamentScreen(tournamentId: 't'));
      await tester.tap(find.text('Bracket'));
      await settle(tester);
      expect(find.text('Ready: set up on Matches'), findsOneWidget);
      await tester.tap(find.text('Matches'));
      await settle(tester);
      await tester.tap(find.text('Set up Semi-final 1: Alpha v Delta'));
      await settle(tester);
      expect(tournaments.tournaments['t']!.fixtures.map((f) => f.id), containsAll(['qf1', 'sf1', 'sf2']));

      await tester.tap(find.text('Bracket'));
      await settle(tester);
      expect(find.text('Winner of Quarter-final'), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget, reason: 'Delta won the quarter-final');
      expect(tester.takeException(), isNull);
    });

    testWidgets('quarter-finals after a league are set up in one tap', (tester) async {
      final list = [for (var i = 0; i < 8; i++) _squad(String.fromCharCode(97 + i), _names[i])];
      final t = Tournament(
        id: 't',
        name: 'League',
        oversPerInnings: 4,
        hasFinal: true,
        hasSemiFinals: true,
        hasQuarterFinals: true,
        teams: list,
        fixtures: roundRobinFixtures(list),
        createdAt: DateTime.utc(2026),
      );
      await tournaments.save(t);
      for (final f in t.fixtures) {
        await playFixture(t, f.id, f.teamAId.compareTo(f.teamBId) < 0 ? f.teamAId : f.teamBId);
      }
      await pump(tester, const TournamentScreen(tournamentId: 't'));
      await tester.dragUntilVisible(
          find.text('Set up the quarter-finals'), find.byType(ListView), const Offset(0, -400));
      await tester.tap(find.text('Set up the quarter-finals'));
      await settle(tester);
      expect(tournaments.tournaments['t']!.fixtures, hasLength(28 + 4));

      await tester.tap(find.text('Bracket'));
      await settle(tester);
      expect(find.text('Quarter-finals'), findsOneWidget);
      expect(find.text('Winner of Quarter-final 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a changed semi-final offers to correct the final', (tester) async {
      final list = [_squad('a', 'Alpha'), _squad('b', 'Bravo'), _squad('c', 'Charlie'), _squad('d', 'Delta')];
      final groups = splitIntoTwoGroups(list);
      final t = Tournament(
        id: 't',
        name: 'Cup',
        oversPerInnings: 4,
        hasFinal: true,
        hasSemiFinals: true,
        groups: groups,
        teams: list,
        fixtures: leagueFixtures(groups),
        createdAt: DateTime.utc(2026),
      );
      await tournaments.save(t);
      await playFixture(t, 'f1', 'a');
      await playFixture(t, 'f2', 'b');
      Map<String, MatchState> states() => {
            for (final m in matches.records.values) m.id: ScoringEngine.replay(m.setup, m.events),
          };
      Tournament current() => tournaments.tournaments['t']!;
      await tournaments.save(current().withFixtures(progressOf(current(), states()).nextRound));
      await playFixture(t, 'sf1', 'a');
      await playFixture(t, 'sf2', 'b');
      await tournaments.save(current().withFixtures(progressOf(current(), states()).nextRound));
      expect(current().finalFixture!.teamAId, 'a');

      await matches.delete('match-sf1');
      await playFixture(t, 'sf1', 'd');
      await pump(tester, const TournamentScreen(tournamentId: 't'));

      expect(find.text('RESULTS CHANGED'), findsOneWidget);
      expect(find.text('Final should now be Delta v Bravo.'), findsOneWidget);
      await tester.tap(find.text('Update Final'));
      await settle(tester);

      expect(current().finalFixture!.teamAId, 'd');
      expect(find.text('RESULTS CHANGED'), findsNothing);
      expect(find.text('Delta v Bravo'), findsOneWidget);
    });

    testWidgets('a final already played cannot be silently changed', (tester) async {
      final list = [_squad('a', 'Alpha'), _squad('b', 'Bravo'), _squad('c', 'Charlie'), _squad('d', 'Delta')];
      final groups = splitIntoTwoGroups(list);
      final base = Tournament(
        id: 't',
        name: 'Cup',
        oversPerInnings: 4,
        hasFinal: true,
        hasSemiFinals: true,
        groups: groups,
        teams: list,
        fixtures: leagueFixtures(groups),
        createdAt: DateTime.utc(2026),
      );
      await tournaments.save(base);
      await playFixture(base, 'f1', 'a');
      await playFixture(base, 'f2', 'b');
      Map<String, MatchState> states() => {
            for (final m in matches.records.values) m.id: ScoringEngine.replay(m.setup, m.events),
          };
      Tournament current() => tournaments.tournaments['t']!;
      await tournaments.save(current().withFixtures(progressOf(current(), states()).nextRound));
      await playFixture(base, 'sf1', 'a');
      await playFixture(base, 'sf2', 'b');
      await tournaments.save(current().withFixtures(progressOf(current(), states()).nextRound));
      await playFixture(base, 'final', 'a');

      await matches.delete('match-sf1');
      await playFixture(base, 'sf1', 'd');
      await pump(tester, const TournamentScreen(tournamentId: 't'));

      expect(find.textContaining('was played by different teams'), findsOneWidget);
      expect(find.text('Update Final'), findsNothing);
    });

    testWidgets('a scheduled fixture shows its date, and a long press moves it', (tester) async {
      final t = threeTeams();
      await tournaments.save(t.withFixtureDate('f1', DateTime(2026, 12, 5, 9)));
      await pump(tester, const TournamentScreen(tournamentId: 't'));

      expect(find.text('Sat 5 Dec, 9:00 AM'), findsOneWidget);

      await tester.longPress(find.text('MATCH 2'));
      await settle(tester);
      await tester.tap(find.text('Set a time'));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);

      expect(tournaments.tournaments['t']!.fixtures[1].scheduledAt, isNotNull);
    });

    testWidgets('tournament leaderboards include boundaries', (tester) async {
      final t = threeTeams();
      await tournaments.save(t);
      await playFixture(t, 'f1', t.fixtures.first.teamAId);
      await pump(tester, const TournamentScreen(tournamentId: 't'));
      await tester.ensureVisible(find.text('Boundaries'));
      await settle(tester);
      await tester.tap(find.text('Boundaries'));
      await settle(tester);
      expect(find.text('No boundaries hit yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
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

  group('prizes and entry fees', () {
    Future<void> openPrizes(WidgetTester tester) async {
      final tab = find.descendant(of: find.byType(TabBar), matching: find.text('Prizes'));
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await settle(tester);
    }

    Tournament withFee() => threeTeams().withDetails(
          prizes: const [Prize(title: 'Winner', reward: '₹25,000 + trophy')],
          entryFee: 2500,
          rules: null,
        );

    testWidgets('start empty, then show what the organiser adds', (tester) async {
      await tournaments.save(threeTeams());
      await pump(tester, const TournamentScreen(tournamentId: 't'));
      await openPrizes(tester);
      await tester.tap(find.text('Add details'));
      await settle(tester);

      expect(find.text('Winner'), findsOneWidget, reason: 'the usual prizes are ready to fill in');
      expect(find.text('Runner-up'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('prize-reward-0')), '₹25,000 + trophy');
      await tester.enterText(find.byKey(const ValueKey('entry-fee')), '2500');
      await tester.enterText(find.byKey(const ValueKey('rules')), 'Tennis ball. Fees not refundable.');
      await tester.tap(find.text('Save'));
      await settle(tester);

      final saved = tournaments.tournaments['t']!;
      expect(saved.prizes.single.title, 'Winner', reason: 'a prize with nothing to win is left out');
      expect(saved.entryFee, 2500);
      expect(saved.rules, 'Tennis ball. Fees not refundable.');

      expect(find.text('WINNER'), findsOneWidget);
      expect(find.text('₹25,000 + trophy'), findsOneWidget);
      expect(find.text('Tennis ball. Fees not refundable.'), findsOneWidget);
      expect(find.text('₹2,500 a team · ₹0 of ₹7,500 collected'), findsOneWidget);
      expect(find.text(PrizesTab.privateNote), findsOneWidget);
      expect(find.text('Not paid'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('payments: part paid, paid in full, and the total', (tester) async {
      await tournaments.save(withFee());
      await pump(tester, const TournamentScreen(tournamentId: 't'));
      await openPrizes(tester);

      await tester.tap(find.text('Alpha'));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('paid-amount')), '1000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      expect(find.text('₹1,000 of ₹2,500'), findsOneWidget);

      await tester.tap(find.text('Bravo'));
      await settle(tester);
      await tester.tap(find.text('Paid in full'));
      await settle(tester);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('₹2,500 a team · ₹3,500 of ₹7,500 collected'), findsOneWidget);

      final saved = tournaments.tournaments['t']!;
      expect(saved.paidBy('a'), 1000);
      expect(saved.paidBy('b'), 2500);
      expect(saved.toPublicJson().containsKey('paid'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a prize needs a name, and rows can be added and removed', (tester) async {
      await pump(tester, TournamentDetailsScreen(tournament: threeTeams()));
      await tester.tap(find.text('Add prize'));
      await tester.pump(_settle);
      expect(find.byKey(const ValueKey('prize-reward-2')), findsOneWidget);
      await tester.tap(find.byTooltip('Remove prize').last);
      await tester.pump(_settle);
      expect(find.byKey(const ValueKey('prize-reward-2')), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('prize-title-0')), '');
      await tester.enterText(find.byKey(const ValueKey('prize-reward-0')), 'A bat');
      await tester.tap(find.text('Save'));
      await tester.pump(_settle);
      expect(find.text(TournamentDetailsScreen.missingTitle), findsOneWidget);
      expect(find.byType(TournamentDetailsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the champions banner shows the winner\'s prize', (tester) async {
      final t = threeTeams(hasFinal: true).withDetails(
        prizes: const [Prize(title: 'Winner', reward: '₹25,000 + trophy')],
        entryFee: null,
        rules: null,
      );
      await tournaments.save(t);
      for (final f in t.fixtures) {
        await playFixture(t, f.id, f.teamAId == 'a' || f.teamBId == 'a' ? 'a' : 'b');
      }
      await pump(tester, const TournamentScreen(tournamentId: 't'));
      await tester.tap(find.text('Set up the final: Alpha v Bravo'));
      await settle(tester);
      await playFixture(t, 'final', 'b');
      await tester.pumpWidget(const SizedBox());
      await pump(tester, const TournamentScreen(tournamentId: 't'));
      expect(find.text('CHAMPIONS'), findsOneWidget);
      expect(find.text('Wins ₹25,000 + trophy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('home filter', () {
    testWidgets('narrows the list to a tournament or to friendlies', (tester) async {
      final t = threeTeams();
      await tournaments.save(t);
      await playFixture(t, 'f1', t.fixtures.first.teamAId);
      await matches.save(sampleRecord(id: 'friendly'));
      await pump(tester, const HomeScreen());

      expect(find.text('Ammapet Kings'), findsOneWidget);
      expect(find.textContaining('won by'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cup'));
      await settle(tester);
      expect(find.text('Ammapet Kings'), findsNothing);
      expect(find.textContaining('won by'), findsOneWidget);

      await tester.tap(find.text('Friendlies'));
      await settle(tester);
      expect(find.text('Ammapet Kings'), findsOneWidget);
      expect(find.textContaining('won by'), findsNothing);

      await tester.tap(find.text('All'));
      await settle(tester);
      expect(find.text('Ammapet Kings'), findsOneWidget);
      expect(find.textContaining('won by'), findsOneWidget);
    });

    testWidgets('a tournament with no matches says so', (tester) async {
      await tournaments.save(threeTeams());
      await matches.save(sampleRecord(id: 'friendly'));
      await pump(tester, const HomeScreen());

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cup'));
      await settle(tester);
      expect(find.text('No matches here yet.'), findsOneWidget);
    });

    testWidgets('deleting warns when a match belongs to a tournament', (tester) async {
      final t = threeTeams();
      await tournaments.save(t);
      await playFixture(t, 'f1', t.fixtures.first.teamAId);
      await pump(tester, const HomeScreen());

      await tester.longPress(find.textContaining('won by'));
      await settle(tester);
      expect(find.textContaining('This is a Cup match'), findsOneWidget);
    });

    testWidgets('deleting a friendly stays a plain warning', (tester) async {
      await tournaments.save(threeTeams());
      await matches.save(sampleRecord(id: 'friendly'));
      await pump(tester, const HomeScreen());

      await tester.longPress(find.text('Ammapet Kings'));
      await settle(tester);
      expect(find.text('The scorecard will be removed from this device.'), findsOneWidget);
    });

    testWidgets('no tournaments, no chips', (tester) async {
      await matches.save(sampleRecord(id: 'friendly'));
      await pump(tester, const HomeScreen());
      expect(find.byType(ChoiceChip), findsNothing);
    });
  });

  testWidgets('the demo tournaments fit at 360 dp', (tester) async {
    final now = DateTime.utc(2026, 11, 6);
    await seedDemoMatches(matches, now: now);
    await seedDemoTournaments(tournaments, now: now);
    await pump(tester, const TournamentsScreen());

    expect(find.textContaining('Winner:'), findsNWidgets(5));
    await tester.tap(find.text('Monsoon League'));
    await settle(tester);

    expect(find.text('CHAMPIONS'), findsOneWidget);
    expect(find.text('Team C'), findsOneWidget);
    expect(find.textContaining('Player of the Tournament:'), findsOneWidget);
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
