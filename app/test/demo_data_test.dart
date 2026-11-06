import 'package:bnp_scorer/data/demo_data.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/screens/home_screen.dart';
import 'package:bnp_scorer/screens/scorecard_screen.dart';
import 'package:bnp_scorer/screens/scoring_screen.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

final _now = DateTime.utc(2026, 11, 6, 12);

MatchState _replay(MatchRecord record) => ScoringEngine.replay(record.setup, record.events);

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  final demo = demoMatches(_now);
  final cup = demo.where((m) => m.id.startsWith('demo-match-')).toList();
  final live = demo.firstWhere((m) => m.id == 'demo-live');

  group('demo matches', () {
    test('every match is finished except the live friendly', () {
      expect(cup, hasLength(5));
      for (final record in demo.where((m) => m.id != live.id)) {
        expect(_replay(record).isCompleted, isTrue, reason: record.id);
      }
      final state = _replay(live);
      expect(state.isCompleted, isFalse);
      expect(state.phase, MatchPhase.inPlay);
      expect(state.current.number, 2);
    });

    test('the league leads to a final between its two unbeaten teams', () {
      final winners = [for (final r in cup) _replay(r).result!.winnerTeamId];
      expect(winners, ['team-a', 'team-d', 'team-a', 'team-d', 'team-d']);
      final finalSetup = cup.last.setup;
      expect(finalSetup.venue, contains('Final'));
      expect({finalSetup.teamA.id, finalSetup.teamB.id}, {'team-a', 'team-d'});
    });

    test('results include wins batting first and chasing', () {
      final kinds = {for (final r in cup) _replay(r).result!.kind};
      expect(kinds, {ResultKind.runs, ResultKind.wickets});
    });

    test('every side is a clean eleven from the team sheet', () {
      for (final record in demo) {
        for (final team in [record.setup.teamA, record.setup.teamB]) {
          expect(team.players, hasLength(11), reason: record.id);
          for (final player in team.players) {
            expect(player.name, isNot(matches(RegExp(r'©|\(VC\)|^\s|\s$'))));
          }
        }
      }
    });

    test('players keep their id from match to match', () {
      final captain = cup.first.setup.teamA.players.first;
      expect(cup[2].setup.teamA.players.first.id, captain.id);
      expect(cup[2].setup.teamA.players.first.name, captain.name);
    });

    test('squads rotate, so each match can field a different eleven', () {
      List<String> ids(MatchRecord r) => [for (final p in r.setup.teamA.players) p.id];
      expect(ids(cup[0]), isNot(ids(cup[2])));
    });

    test('matches are ordered oldest first with past dates', () {
      for (var i = 1; i < demo.length; i++) {
        expect(demo[i - 1].createdAt.isAfter(demo[i].createdAt), isFalse);
      }
      for (final record in demo) {
        expect(record.updatedAt.isAfter(_now), isFalse, reason: record.id);
      }
    });

    test('the same date gives the same matches', () {
      final again = demoMatches(_now);
      for (var i = 0; i < demo.length; i++) {
        expect(again[i].toJson(), demo[i].toJson());
      }
    });

    test('records survive the storage JSON round trip', () {
      for (final record in demo) {
        final restored = MatchRecord.fromJson(record.toJson());
        final before = _replay(record).innings.last;
        final after = _replay(restored).innings.last;
        expect(after.runs, before.runs);
        expect(after.wickets, before.wickets);
        expect(after.legalBalls, before.legalBalls);
      }
    });
  });

  group('seeding', () {
    test('adds every demo match to an empty repository', () async {
      final repo = InMemoryMatchRepository();
      await seedDemoMatches(repo, now: _now);
      expect(repo.records.keys, containsAll(demo.map((m) => m.id)));
    });

    test('leaves the scorer\'s own matches alone', () async {
      final repo = InMemoryMatchRepository();
      final own = sampleRecord(id: 'mine');
      await repo.save(own);
      await seedDemoMatches(repo, now: _now);
      expect(repo.records['mine'], same(own));
      expect(repo.records, hasLength(demo.length + 1));
    });

    test('a restart does not overwrite a match scored during the demo', () async {
      final repo = InMemoryMatchRepository();
      await seedDemoMatches(repo, now: _now);
      final scored = repo.records[live.id]!.withEvents(const []);
      await repo.save(scored);
      await seedDemoMatches(repo, now: _now.add(const Duration(days: 1)));
      expect(repo.records[live.id], same(scored));
    });

    test('a deleted demo match comes back on the next launch', () async {
      final repo = InMemoryMatchRepository();
      await seedDemoMatches(repo, now: _now);
      await repo.delete(cup.first.id);
      await seedDemoMatches(repo, now: _now);
      expect(repo.records, contains(cup.first.id));
      expect(repo.records, hasLength(demo.length));
    });
  });

  group('tournaments', () {
    final tournaments = demoTournaments(_now);
    final byId = {for (final m in demo) m.id: _replay(m)};

    test('there is a current cup and three past ones', () {
      expect(tournaments.map((t) => t.name),
          ['Winter Bash', 'Summer Shield', 'Monsoon League', 'BNP Cup']);
    });

    test('each is finished, and every fixture has its match', () {
      for (final tournament in tournaments) {
        final progress = progressOf(tournament, byId);
        expect(progress.isFinished, isTrue, reason: tournament.name);
        expect(progress.championId, isNotNull, reason: tournament.name);
      }
    });

    test('finals are between the top two of the real table', () {
      for (final tournament in tournaments.where((t) => t.hasFinal)) {
        final table = progressOf(tournament, byId).table;
        final finalFixture = tournament.finalFixture!;
        expect(
          {finalFixture.teamAId, finalFixture.teamBId},
          {table[0].teamId, table[1].teamId},
          reason: tournament.name,
        );
      }
    });

    test('champions are the scripted ones', () {
      final winners = [for (final t in tournaments) progressOf(t, byId).championId];
      expect(winners, ['team-b', 'team-b', 'team-c', 'team-d']);
    });

    test('seeding adds them once and keeps edits', () async {
      final repo = InMemoryTournamentRepository();
      await seedDemoTournaments(repo, now: _now);
      expect(repo.tournaments, hasLength(4));
      final edited = repo.tournaments['demo-cup-bnp']!.withMatch('f1', 'other');
      await repo.save(edited);
      await seedDemoTournaments(repo, now: _now);
      expect(repo.tournaments['demo-cup-bnp'], same(edited));
    });
  });

  group('team seeding', () {
    test('adds the four full squads with the ids the matches use', () async {
      final repo = InMemoryTeamRepository();
      await seedDemoTeams(repo);
      expect(repo.teams, hasLength(4));
      for (final team in repo.teams.values) {
        expect(team.players, hasLength(13), reason: team.name);
      }
      final played = cup.first.setup.teamA;
      expect(repo.teams[played.id]!.players.map((p) => p.id), containsAll(played.players.map((p) => p.id)));
    });

    test('a restart does not overwrite an edited squad', () async {
      final repo = InMemoryTeamRepository();
      await seedDemoTeams(repo);
      final edited = Team(id: 'team-a', name: 'Renamed', players: const [
        Player(id: 'x', name: 'X'),
        Player(id: 'y', name: 'Y'),
      ]);
      await repo.save(edited);
      await seedDemoTeams(repo);
      expect(repo.teams['team-a'], same(edited));
    });
  });

  group('demo screens at 360 dp with real names', () {
    Future<InMemoryMatchRepository> pump(WidgetTester tester, Widget home) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final repo = InMemoryMatchRepository();
      await seedDemoMatches(repo, now: _now);
      await tester.pumpWidget(ProviderScope(
        overrides: [matchRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      return repo;
    }

    testWidgets('home lists the matches', (tester) async {
      await pump(tester, const HomeScreen());
      expect(find.textContaining('won by'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the live friendly opens ready to score', (tester) async {
      await pump(tester, ScoringScreen(matchId: live.id));
      expect(find.text('FOUR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every cup scorecard renders', (tester) async {
      for (final record in cup) {
        await pump(tester, ScorecardScreen(matchId: record.id));
        expect(find.textContaining('won by'), findsWidgets, reason: record.id);
        expect(tester.takeException(), isNull, reason: record.id);
      }
    });
  });
}
