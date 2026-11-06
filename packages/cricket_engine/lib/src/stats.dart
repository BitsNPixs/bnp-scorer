/// Career numbers for players and teams, derived from finished matches. They
/// are never stored: replay the matches and call [computeStats] again.
library;

import 'models.dart';
import 'state.dart';

/// Stats are reported in six-ball overs, whatever a match was played with.
const _statBallsPerOver = 6;

const pointsForWin = 2;
const pointsForTie = 1;

class HighScore {
  const HighScore({required this.runs, required this.notOut});

  final int runs;
  final bool notOut;

  bool beats(HighScore other) =>
      runs > other.runs || (runs == other.runs && notOut && !other.notOut);
}

class BestBowling {
  const BestBowling({required this.wickets, required this.runs});

  final int wickets;
  final int runs;

  bool beats(BestBowling other) =>
      wickets > other.wickets || (wickets == other.wickets && runs < other.runs);
}

class BattingStats {
  const BattingStats({
    this.innings = 0,
    this.notOuts = 0,
    this.runs = 0,
    this.balls = 0,
    this.fours = 0,
    this.sixes = 0,
    this.fifties = 0,
    this.hundreds = 0,
    this.high,
  });

  final int innings;
  final int notOuts;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;

  /// Scores of 50 to 99. A hundred counts only as a hundred.
  final int fifties;
  final int hundreds;
  final HighScore? high;

  int get dismissals => innings - notOuts;

  /// Runs per dismissal. Null until the batter has been out.
  double? get average => dismissals == 0 ? null : runs / dismissals;

  double? get strikeRate => balls == 0 ? null : runs * 100 / balls;
}

class BowlingStats {
  const BowlingStats({
    this.innings = 0,
    this.legalBalls = 0,
    this.runs = 0,
    this.wickets = 0,
    this.maidens = 0,
    this.dots = 0,
    this.wides = 0,
    this.noBalls = 0,
    this.best,
  });

  final int innings;
  final int legalBalls;
  final int runs;
  final int wickets;
  final int maidens;
  final int dots;
  final int wides;
  final int noBalls;
  final BestBowling? best;

  String get oversText => formatOvers(legalBalls, _statBallsPerOver);

  /// Runs per over.
  double? get economy => legalBalls == 0 ? null : runs * _statBallsPerOver / legalBalls;

  /// Runs per wicket.
  double? get average => wickets == 0 ? null : runs / wickets;

  /// Balls per wicket.
  double? get strikeRate => wickets == 0 ? null : legalBalls / wickets;
}

class FieldingStats {
  const FieldingStats({this.catches = 0, this.stumpings = 0, this.runOuts = 0});

  final int catches;
  final int stumpings;
  final int runOuts;
}

class PlayerStats {
  const PlayerStats({
    required this.playerId,
    required this.name,
    required this.teamId,
    required this.teamName,
    required this.matches,
    required this.batting,
    required this.bowling,
    required this.fielding,
  });

  final String playerId;
  final String name;

  /// The side in the player's most recent match.
  final String teamId;
  final String teamName;
  final int matches;
  final BattingStats batting;
  final BowlingStats bowling;
  final FieldingStats fielding;
}

enum MatchOutcome { won, lost, tied }

class TeamStats {
  const TeamStats({
    required this.teamId,
    required this.name,
    required this.won,
    required this.lost,
    required this.tied,
    required this.runsFor,
    required this.runsAgainst,
    required this.oversFaced,
    required this.oversBowled,
    required this.highest,
    required this.lowest,
    required this.form,
  });

  final String teamId;
  final String name;
  final int won;
  final int lost;
  final int tied;
  final int runsFor;
  final int runsAgainst;

  /// Decimal overs for run rates, so 10.3 overs is 10.5 here.
  final double oversFaced;
  final double oversBowled;
  final int highest;
  final int lowest;

  /// Results in the order they were played.
  final List<MatchOutcome> form;

  int get played => won + lost + tied;
  int get points => won * pointsForWin + tied * pointsForTie;

  /// Net run rate: runs per over scored minus runs per over conceded. A side
  /// bowled out is charged its full quota of overs.
  double? get netRunRate {
    if (oversFaced == 0 || oversBowled == 0) return null;
    return runsFor / oversFaced - runsAgainst / oversBowled;
  }
}

class StatsBook {
  const StatsBook({required this.players, required this.teams, required this.matches});

  /// Finished matches counted.
  final int matches;

  /// Everyone who played, in no particular order.
  final List<PlayerStats> players;

  /// Most points first, then net run rate.
  final List<TeamStats> teams;

  bool get isEmpty => matches == 0;

  /// Players who batted: most runs first, then the faster scorer.
  List<PlayerStats> get batters {
    final list = [
      for (final p in players)
        if (p.batting.innings > 0) p,
    ];
    return list
      ..sort((a, b) {
        final runs = b.batting.runs.compareTo(a.batting.runs);
        if (runs != 0) return runs;
        final rate = (b.batting.strikeRate ?? 0).compareTo(a.batting.strikeRate ?? 0);
        return rate != 0 ? rate : a.name.compareTo(b.name);
      });
  }

  /// Players who bowled: most wickets first, then the cheaper bowler.
  List<PlayerStats> get bowlers {
    final list = [
      for (final p in players)
        if (p.bowling.innings > 0) p,
    ];
    return list
      ..sort((a, b) {
        final wickets = b.bowling.wickets.compareTo(a.bowling.wickets);
        if (wickets != 0) return wickets;
        final economy = (a.bowling.economy ?? 0).compareTo(b.bowling.economy ?? 0);
        return economy != 0 ? economy : a.name.compareTo(b.name);
      });
  }
}

/// Builds the book from [matches], oldest first. Unfinished matches are left
/// out, so a live match joins the numbers once it has a result.
StatsBook computeStats(Iterable<MatchState> matches) {
  final players = <String, _PlayerBuilder>{};
  final teams = <String, _TeamBuilder>{};
  var counted = 0;

  for (final match in matches) {
    final result = match.result;
    if (!match.isCompleted || result == null) continue;
    counted++;
    final setup = match.setup;

    for (final team in [setup.teamA, setup.teamB]) {
      final record = teams.putIfAbsent(team.id, _TeamBuilder.new)..name = team.name;
      record.form.add(switch (result.winnerTeamId) {
        null => MatchOutcome.tied,
        final winner when winner == team.id => MatchOutcome.won,
        _ => MatchOutcome.lost,
      });
      for (final player in team.players) {
        players.putIfAbsent(player.id, _PlayerBuilder.new)
          ..matches += 1
          ..name = player.name
          ..teamId = team.id
          ..teamName = team.name;
      }
    }

    for (final innings in match.innings) {
      final batting = setup.teamById(innings.battingTeamId);
      final overs = _oversForRunRate(innings, batting, setup.rules);
      teams[innings.battingTeamId]!.addInningsBatted(innings.runs, overs);
      teams[innings.bowlingTeamId]!.addInningsBowled(innings.runs, overs);

      for (final score in innings.batters) {
        players[score.playerId]!.addInnings(score);
        final dismissal = score.dismissal;
        final fielder = players[dismissal?.fielderId];
        if (dismissal != null && fielder != null) fielder.addDismissal(dismissal.type);
      }
      for (final figures in innings.bowlers) {
        players[figures.playerId]!.addSpell(figures);
      }
    }
  }

  final book = [for (final team in teams.entries) team.value.build(team.key)];
  book.sort((a, b) {
    final points = b.points.compareTo(a.points);
    if (points != 0) return points;
    final rate = (b.netRunRate ?? 0).compareTo(a.netRunRate ?? 0);
    return rate != 0 ? rate : a.name.compareTo(b.name);
  });
  return StatsBook(
    matches: counted,
    players: [for (final player in players.entries) player.value.build(player.key)],
    teams: List.unmodifiable(book),
  );
}

double _oversForRunRate(InningsState innings, Team batting, MatchRules rules) {
  final allOut = innings.wickets >= rules.maxWicketsFor(batting.players.length);
  final balls = allOut ? innings.maxBalls : innings.legalBalls;
  return balls / innings.ballsPerOver;
}

class _PlayerBuilder {
  int matches = 0;
  String name = '';
  String teamId = '';
  String teamName = '';

  int innings = 0;
  int notOuts = 0;
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  int fifties = 0;
  int hundreds = 0;
  HighScore? high;

  int spells = 0;
  int legalBalls = 0;
  int runsConceded = 0;
  int wickets = 0;
  int maidens = 0;
  int dots = 0;
  int wides = 0;
  int noBalls = 0;
  BestBowling? best;

  int catches = 0;
  int stumpings = 0;
  int runOuts = 0;

  void addInnings(BatterScore score) {
    innings++;
    if (!score.isOut) notOuts++;
    runs += score.runs;
    balls += score.balls;
    fours += score.fours;
    sixes += score.sixes;
    if (score.runs >= 100) {
      hundreds++;
    } else if (score.runs >= 50) {
      fifties++;
    }
    final scored = HighScore(runs: score.runs, notOut: !score.isOut);
    final top = high;
    if (top == null || scored.beats(top)) high = scored;
  }

  void addSpell(BowlerFigures figures) {
    spells++;
    legalBalls += figures.legalBalls;
    runsConceded += figures.runs;
    wickets += figures.wickets;
    maidens += figures.maidens;
    dots += figures.dots;
    wides += figures.wides;
    noBalls += figures.noBalls;
    final spell = BestBowling(wickets: figures.wickets, runs: figures.runs);
    final top = best;
    if (top == null || spell.beats(top)) best = spell;
  }

  void addDismissal(DismissalType type) {
    switch (type) {
      case DismissalType.caught:
        catches++;
      case DismissalType.stumped:
        stumpings++;
      case DismissalType.runOut:
        runOuts++;
      default:
        break;
    }
  }

  PlayerStats build(String id) => PlayerStats(
        playerId: id,
        name: name,
        teamId: teamId,
        teamName: teamName,
        matches: matches,
        batting: BattingStats(
          innings: innings,
          notOuts: notOuts,
          runs: runs,
          balls: balls,
          fours: fours,
          sixes: sixes,
          fifties: fifties,
          hundreds: hundreds,
          high: high,
        ),
        bowling: BowlingStats(
          innings: spells,
          legalBalls: legalBalls,
          runs: runsConceded,
          wickets: wickets,
          maidens: maidens,
          dots: dots,
          wides: wides,
          noBalls: noBalls,
          best: best,
        ),
        fielding: FieldingStats(catches: catches, stumpings: stumpings, runOuts: runOuts),
      );
}

class _TeamBuilder {
  String name = '';
  final form = <MatchOutcome>[];
  int runsFor = 0;
  int runsAgainst = 0;
  double oversFaced = 0;
  double oversBowled = 0;
  int? highest;
  int? lowest;

  void addInningsBatted(int runs, double overs) {
    runsFor += runs;
    oversFaced += overs;
    final top = highest;
    final bottom = lowest;
    if (top == null || runs > top) highest = runs;
    if (bottom == null || runs < bottom) lowest = runs;
  }

  void addInningsBowled(int runs, double overs) {
    runsAgainst += runs;
    oversBowled += overs;
  }

  TeamStats build(String id) => TeamStats(
        teamId: id,
        name: name,
        won: form.where((o) => o == MatchOutcome.won).length,
        lost: form.where((o) => o == MatchOutcome.lost).length,
        tied: form.where((o) => o == MatchOutcome.tied).length,
        runsFor: runsFor,
        runsAgainst: runsAgainst,
        oversFaced: oversFaced,
        oversBowled: oversBowled,
        highest: highest ?? 0,
        lowest: lowest ?? 0,
        form: List.unmodifiable(form),
      );
}
