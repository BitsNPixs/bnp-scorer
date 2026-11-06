/// Sample matches for showing the app to people. Only used in builds made with
/// `--dart-define=BNP_DEMO=true`, so normal builds carry none of this.
///
/// Every match is simulated ball by ball through [ScoringEngine], so a demo
/// scorecard is a real event log: the engine applies all the rules here too.
library;

import 'dart:math';

import 'package:cricket_engine/cricket_engine.dart';

import 'match_record.dart';
import 'match_repository.dart';
import 'team_repository.dart';

const demoMode = bool.fromEnvironment('BNP_DEMO');

const _overs = 10;
const _maxOversPerBowler = 2;
const _venue = 'Main Ground';

/// Index in a playing XI of the wicket-keeper, who never bowls.
const _keeper = 2;

/// Index in a playing XI of the first of the six specialist bowlers.
const _firstBowler = 5;

/// Index in a playing XI of the first tail-end batter.
const _firstTailender = 7;

const _squads = {
  'a': [
    'M Monish Savio', 'Livin D', 'Anish Kumar V', 'Bibin Justus', 'Anish Madhavan',
    'Sajin Suthan', 'Gowrishankar', 'Yuvraj Kannan', 'Shabu Mohandhas',
    'Punith Kumar Nayaka R', 'Sathish Kumar A', 'Eben Dany Gilbert', 'Gopi P',
  ],
  'b': [
    'Mohammed Sheriff', 'Asvin J S', 'Santhoshkumar', 'Sobi G', 'Dinesh Kumar',
    'Anbarasan Raja', 'Sabith Selvan', 'Sijin Mano', 'Anish Christhu Dhas',
    'Nigin N', 'Jerin Singh J', 'Subash Ambrose', 'Sankar Kumar',
  ],
  'c': [
    'Godwin S', 'Sarath Kumar R', 'Naveen Kumar Nadarajan', 'Ananth Stephen',
    'Jayaram R B', 'Sajin Gilbert', 'Karthick Muthusamy', 'Mohamed Ibrahim',
    'Palanivel Anbazhagan', 'Sajin Raj K', 'Anil Stalin W', 'Siddiq Noor Mohamed',
    'Mari Selvam M',
  ],
  'd': [
    'Aravindan senthilvel', 'Ashik Ramesh Babu', 'Reshikesh V', 'Anish Mon',
    'Jeevin V', 'Jenil Rubin', 'Raja S', 'Subash P', 'Ajith Stephen',
    'Arun Kanakaraj', 'Manikandan', 'Sudhy Sekhar G S', 'Suraj Rajendran',
  ],
};

Team _squad(String key) {
  final names = _squads[key]!;
  return Team(
    id: 'team-$key',
    name: 'Team ${key.toUpperCase()}',
    players: [
      for (var i = 0; i < names.length; i++) Player(id: '$key${i + 1}', name: names[i]),
    ],
  );
}

/// The playing XI for match [number]. Squads have 13 players, so two sit out,
/// a different pair each match. The captain, vice-captain and keeper always
/// play. Player ids stay the same across matches.
Team _team(String key, int number) {
  final squad = _squad(key);
  final firstRested = 3 + (number * 2) % 10;
  return Team(
    id: squad.id,
    name: squad.name,
    players: [
      for (var i = 0; i < squad.players.length; i++)
        if (i != firstRested && i != firstRested + 1) squad.players[i],
    ],
  );
}

class _Fixture {
  const _Fixture({
    required this.number,
    required this.title,
    required this.home,
    required this.away,
    required this.daysAgo,
    this.winner,
    this.close = false,
    this.chase = false,
    this.stopAtBall,
  });

  final int number;
  final String title;
  final String home;
  final String away;
  final int daysAgo;

  /// Team key that must win. Null only for the unfinished match.
  final String? winner;

  /// The result must be a tight one.
  final bool close;

  /// The winner must bat second, for a "won by N wickets" result.
  final bool chase;

  /// Stop here in the second innings, leaving the match live.
  final int? stopAtBall;

  String get id => stopAtBall == null ? 'demo-match-$number' : 'demo-live';
}

/// A four-team cup: four league games, then the top two meet in the final.
/// Team A and Team D each win both league games, so no tie-break is needed.
const _fixtures = [
  _Fixture(number: 1, title: 'BNP Cup Match 1', home: 'a', away: 'b', daysAgo: 9, winner: 'a'),
  _Fixture(number: 2, title: 'BNP Cup Match 2', home: 'c', away: 'd', daysAgo: 9, winner: 'd', chase: true),
  _Fixture(number: 3, title: 'BNP Cup Match 3', home: 'a', away: 'c', daysAgo: 8, winner: 'a'),
  _Fixture(number: 4, title: 'BNP Cup Match 4', home: 'b', away: 'd', daysAgo: 8, winner: 'd', chase: true),
  _Fixture(number: 5, title: 'BNP Cup Final', home: 'a', away: 'd', daysAgo: 2, winner: 'd', close: true),
  _Fixture(number: 6, title: 'Friendly', home: 'b', away: 'c', daysAgo: 0, stopAtBall: 40),
];

/// Plays one fixture with a seeded [Random], so the same match comes out every
/// time. Asks the engine what is legal and never decides that itself.
class _Simulation {
  _Simulation(this.fixture, this.random, this.startedAt)
      : setup = _setup(fixture, random);

  final _Fixture fixture;
  final Random random;
  final DateTime startedAt;
  final MatchSetup setup;
  final events = <MatchEvent>[];

  static MatchSetup _setup(_Fixture fixture, Random random) {
    final home = _team(fixture.home, fixture.number);
    final away = _team(fixture.away, fixture.number);
    return MatchSetup(
      id: fixture.id,
      teamA: home,
      teamB: away,
      rules: MatchRules(oversPerInnings: _overs, maxOversPerBowler: _maxOversPerBowler),
      tossWinnerId: random.nextBool() ? home.id : away.id,
      tossDecision: random.nextBool() ? TossDecision.bat : TossDecision.bowl,
      venue: '${fixture.title} · $_venue',
    );
  }

  String _nextEventId() => '${fixture.id}-${events.length + 1}';

  /// Scorers take about half a minute per event.
  DateTime _nextEventTime() => startedAt.add(Duration(seconds: 35 * events.length));

  void _add(MatchEvent event) {
    ScoringEngine.apply(setup, events, event);
    events.add(event);
  }

  MatchState run() {
    while (true) {
      final current = ScoringEngine.replay(setup, events);
      final innings = current.current;
      final stopAt = fixture.stopAtBall;
      if (current.phase == MatchPhase.completed) return current;
      if (stopAt != null &&
          innings.number == 2 &&
          innings.legalBalls >= stopAt &&
          current.phase == MatchPhase.inPlay) {
        return current;
      }
      switch (current.phase) {
        case MatchPhase.awaitingOpeners:
          _openers(innings.battingTeamId);
        case MatchPhase.inningsBreak:
          _openers(innings.bowlingTeamId);
        case MatchPhase.awaitingBowler:
          _add(BowlerChanged(id: _nextEventId(), at: _nextEventTime(), bowlerId: _pickBowler(innings)));
        case MatchPhase.awaitingBatter:
          _add(NewBatter(id: _nextEventId(), at: _nextEventTime(), batterId: innings.availableBatterIds.first));
        case MatchPhase.inPlay:
          _add(_delivery(innings));
        case MatchPhase.completed:
          break;
      }
    }
  }

  void _openers(String teamId) {
    final players = setup.teamById(teamId).players;
    _add(OpenersSelected(
      id: _nextEventId(),
      at: _nextEventTime(),
      strikerId: players[0].id,
      nonStrikerId: players[1].id,
    ));
  }

  /// The least-used specialist bowler the engine allows.
  String _pickBowler(InningsState innings) {
    final attack = setup.teamById(innings.bowlingTeamId).players.skip(_firstBowler).map((p) => p.id);
    final options = [
      for (final id in attack)
        if (innings.eligibleBowlerIds.contains(id)) id,
    ];
    if (options.isEmpty) return innings.eligibleBowlerIds.first;
    int ballsBowled(String id) => innings.bowler(id)?.legalBalls ?? 0;
    final fewest = options.map(ballsBowled).reduce(min);
    final freshest = options.where((id) => ballsBowled(id) == fewest).toList();
    return freshest[random.nextInt(freshest.length)];
  }

  BallBowled _delivery(InningsState innings) {
    BallBowled ball({
      int runsOffBat = 0,
      ExtraType extra = ExtraType.none,
      int extraRuns = 0,
      Wicket? wicket,
    }) =>
        BallBowled(
          id: _nextEventId(),
          at: _nextEventTime(),
          runsOffBat: runsOffBat,
          extra: extra,
          extraRuns: extraRuns,
          boundary: runsOffBat == 4 || runsOffBat == 6,
          wicket: wicket,
        );

    final batting = setup.teamById(innings.battingTeamId).players;
    final position = batting.indexWhere((p) => p.id == innings.strikerId);
    final tailender = position >= _firstTailender;
    final hitting = tailender ? 0.55 : 1.0;

    // Chances out of 100, tested in order. Whatever is left is a dot ball.
    var roll = random.nextDouble() * 100;
    bool chance(double percent) {
      roll -= percent;
      return roll < 0;
    }

    if (chance(4)) return ball(extra: ExtraType.wide);
    if (chance(1.5)) {
      return ball(extra: ExtraType.noBall, runsOffBat: const [0, 1, 4][random.nextInt(3)]);
    }
    if (chance(2)) return ball(extra: ExtraType.legBye, extraRuns: 1);
    if (chance(0.5)) return ball(extra: ExtraType.bye, extraRuns: 1);
    if (chance(tailender ? 11 : 6.5)) {
      return innings.isFreeHit ? ball() : _wicketBall(innings, ball);
    }
    if (chance(5 * hitting)) return ball(runsOffBat: 6);
    if (chance(12 * hitting)) return ball(runsOffBat: 4);
    if (chance(1)) return ball(runsOffBat: 3);
    if (chance(8)) return ball(runsOffBat: 2);
    if (chance(30)) return ball(runsOffBat: 1);
    return ball();
  }

  BallBowled _wicketBall(
    InningsState innings,
    BallBowled Function({int runsOffBat, ExtraType extra, int extraRuns, Wicket? wicket}) ball,
  ) {
    final fielders = setup.teamById(innings.bowlingTeamId).players;
    String anyFielder() => fielders[random.nextInt(fielders.length)].id;
    final striker = innings.strikerId!;
    final roll = random.nextInt(100);
    if (roll < 50) {
      return ball(wicket: Wicket(type: DismissalType.caught, batterOutId: striker, fielderId: anyFielder()));
    }
    if (roll < 72) return ball(wicket: Wicket(type: DismissalType.bowled, batterOutId: striker));
    if (roll < 82) return ball(wicket: Wicket(type: DismissalType.lbw, batterOutId: striker));
    if (roll < 90) {
      return ball(
        wicket: Wicket(type: DismissalType.stumped, batterOutId: striker, fielderId: fielders[_keeper].id),
      );
    }
    final target = innings.target;
    final winsOnARun = target != null && innings.runs + 1 >= target;
    return ball(
      runsOffBat: winsOnARun ? 0 : random.nextInt(2),
      wicket: Wicket(
        type: DismissalType.runOut,
        batterOutId: random.nextBool() ? striker : innings.nonStrikerId!,
        fielderId: anyFielder(),
      ),
    );
  }
}

bool _matchesScript(_Fixture fixture, MatchState state) {
  if (fixture.stopAtBall != null) {
    final runsNeeded = state.current.runsNeeded;
    return !state.isCompleted && runsNeeded != null && runsNeeded >= 20 && runsNeeded <= 35;
  }
  final result = state.result!;
  if (result.winnerTeamId != 'team-${fixture.winner}') return false;
  if (fixture.chase && result.kind != ResultKind.wickets) return false;
  if (!fixture.close) return true;
  return result.kind == ResultKind.runs ? result.margin <= 8 : (result.ballsRemaining ?? 0) <= 4;
}

/// Replays seeds in order until the fixture's scripted result comes up.
MatchRecord _play(_Fixture fixture, DateTime now) {
  final startedAt = now.subtract(Duration(days: fixture.daysAgo, hours: 2));
  for (var seed = fixture.number * 1000;; seed++) {
    final simulation = _Simulation(fixture, Random(seed), startedAt);
    final state = simulation.run();
    if (_matchesScript(fixture, state)) {
      return MatchRecord(
        setup: simulation.setup,
        events: simulation.events,
        createdAt: startedAt,
        updatedAt: simulation.events.last.at,
      );
    }
  }
}

/// The five cup matches plus one friendly left in progress to score live.
List<MatchRecord> demoMatches(DateTime now) => [for (final f in _fixtures) _play(f, now)];

/// Adds any demo match the repository does not have. Existing records are left
/// alone, so a match scored during a demo survives a restart.
Future<void> seedDemoMatches(MatchRepository repository, {DateTime? now}) async {
  final existing = {for (final record in await repository.loadAll()) record.id};
  if (_fixtures.every((f) => existing.contains(f.id))) return;
  for (final record in demoMatches(now ?? DateTime.now())) {
    if (!existing.contains(record.id)) await repository.save(record);
  }
}

/// Adds any of the four squads the repository does not have, under the same
/// ids as in the demo matches. Existing teams are left alone.
Future<void> seedDemoTeams(TeamRepository repository) async {
  final existing = {for (final team in await repository.loadAll()) team.id};
  for (final key in _squads.keys) {
    final team = _squad(key);
    if (!existing.contains(team.id)) await repository.save(team);
  }
}
