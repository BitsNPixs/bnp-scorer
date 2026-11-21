/// Value types describing who is playing and under which rules.
library;

typedef Json = Map<String, Object?>;

enum TossDecision { bat, bowl }

/// How a delivery was scored beyond (or instead of) runs off the bat.
enum ExtraType { none, wide, noBall, bye, legBye }

enum DismissalType {
  bowled,
  caught,
  lbw,
  stumped,
  hitWicket,
  runOut,
  obstructingTheField,
  retiredOut,
  retiredHurt;

  /// Whether the bowler gets the wicket in their figures.
  bool get creditedToBowler => switch (this) {
        bowled || caught || lbw || stumped || hitWicket => true,
        _ => false,
      };

  /// Retired hurt is not a wicket: the batter may come back later.
  bool get countsAsWicket => this != retiredHurt;

  /// Retirements are recorded with [BatterRetired], never on a delivery.
  bool get isRetirement => this == retiredHurt || this == retiredOut;

  /// A fielder took part, so it counts for them.
  bool get isFieldingAssist => this == caught || this == stumped || this == runOut;

  /// Dismissals where the non-striker can be the batter who is out.
  bool get canDismissNonStriker =>
      this == runOut || this == obstructingTheField || isRetirement;

  String get label => switch (this) {
        bowled => 'Bowled',
        caught => 'Caught',
        lbw => 'LBW',
        stumped => 'Stumped',
        hitWicket => 'Hit wicket',
        runOut => 'Run out',
        obstructingTheField => 'Obstructing the field',
        retiredOut => 'Retired out',
        retiredHurt => 'Retired hurt',
      };
}

/// Where a shot went, clockwise from straight past the bowler, as seen for a
/// right-handed batter.
enum ShotZone {
  midOff('Mid-off'),
  cover('Cover'),
  point('Point'),
  thirdMan('Third man'),
  fineLeg('Fine leg'),
  squareLeg('Square leg'),
  midwicket('Midwicket'),
  midOn('Mid-on');

  const ShotZone(this.label);

  final String label;

  /// Clockwise from the bowler, at the middle of the zone.
  double get angleDegrees => index * 45 + 22.5;
}

/// The two ends of the pitch, named for where the striker and bowler stand.
enum CreaseEnd {
  striker("Striker's end"),
  bowler("Bowler's end");

  const CreaseEnd(this.label);

  final String label;
}

/// A rule set aside so that someone can bowl, used only when nobody is free
/// under the usual rules. Each step also keeps the ones before it.
enum BowlingRelaxation {
  none(''),
  partOver('Rule eased so play goes on: a bowler from part of the last over may bowl.'),
  oversLimit('Rule eased so play goes on: the overs limit is lifted.'),
  anyone('Rule eased so play goes on: the bowler of the last over may bowl.');

  const BowlingRelaxation(this.message);

  /// Why the picker looks different, for the scorer. Empty for [none].
  final String message;
}

enum PlayerRole {
  batter('Batter'),
  bowler('Bowler'),
  allRounder('All-rounder');

  const PlayerRole(this.label);

  final String label;
}

class Player {
  const Player({required this.id, required this.name, this.role});

  final String id;
  final String name;

  /// Null until someone sets it.
  final PlayerRole? role;

  Json toJson() => {'id': id, 'name': name, 'role': role?.name};

  factory Player.fromJson(Json json) => Player(
        id: json['id']! as String,
        name: json['name']! as String,
        role: switch (json['role']) {
          final String role => PlayerRole.values.byName(role),
          _ => null,
        },
      );
}

class Team {
  Team({
    required this.id,
    required this.name,
    required List<Player> players,
    this.captainId,
    this.viceCaptainId,
    this.keeperId,
    this.logoUrl,
  }) : players = List.unmodifiable(players) {
    if (players.length < 2) {
      throw ArgumentError('A team needs at least 2 players.');
    }
    final ids = players.map((p) => p.id).toSet();
    if (ids.length != players.length) {
      throw ArgumentError('Player ids within a team must be unique.');
    }
  }

  final String id;
  final String name;
  final List<Player> players;
  final String? captainId;
  final String? viceCaptainId;
  final String? keeperId;

  /// The team's logo on the app's photos service, or null for initials.
  final String? logoUrl;

  bool hasPlayer(String playerId) => players.any((p) => p.id == playerId);

  Player? playerById(String playerId) {
    for (final p in players) {
      if (p.id == playerId) return p;
    }
    return null;
  }

  Json toJson() => {
        'id': id,
        'name': name,
        'players': [for (final p in players) p.toJson()],
        'captainId': captainId,
        'viceCaptainId': viceCaptainId,
        'keeperId': keeperId,
        // Written only when set, so teams without a logo read as before.
        if (logoUrl != null) 'logoUrl': logoUrl,
      };

  factory Team.fromJson(Json json) => Team(
        id: json['id']! as String,
        name: json['name']! as String,
        players: [
          for (final p in json['players']! as List<Object?>)
            Player.fromJson(p! as Json),
        ],
        captainId: json['captainId'] as String?,
        viceCaptainId: json['viceCaptainId'] as String?,
        keeperId: json['keeperId'] as String?,
        logoUrl: json['logoUrl'] as String?,
      );
}

/// Local cricket varies a lot, so the common house rules are configurable.
const _superOverWickets = 2;

class MatchRules {
  MatchRules({
    required this.oversPerInnings,
    this.ballsPerOver = 6,
    this.wideRuns = 1,
    this.noBallRuns = 1,
    this.freeHitOnNoBall = true,
    this.lastManStands = false,
    this.maxOversPerBowler,
    this.superOver = false,
    this.trackShots = false,
  }) {
    if (oversPerInnings < 1) throw ArgumentError('Overs must be at least 1.');
    if (ballsPerOver < 1) throw ArgumentError('Balls per over must be >= 1.');
    if (wideRuns < 0 || noBallRuns < 0) {
      throw ArgumentError('Penalty runs cannot be negative.');
    }
    final max = maxOversPerBowler;
    if (max != null && max < 1) {
      throw ArgumentError('Max overs per bowler must be at least 1.');
    }
  }

  final int oversPerInnings;
  final int ballsPerOver;
  final int wideRuns;
  final int noBallRuns;
  final bool freeHitOnNoBall;

  /// The last remaining batter may bat alone.
  final bool lastManStands;
  final int? maxOversPerBowler;

  /// A Super Over: an innings ends after 2 wickets. It settles a tied knockout
  /// game and does not count towards career stats.
  final bool superOver;

  /// The scorer records where each scoring shot went.
  final bool trackShots;

  int get ballsPerInnings => oversPerInnings * ballsPerOver;

  /// Wickets that end an innings for a side of [teamSize] players.
  int maxWicketsFor(int teamSize) {
    final wickets = lastManStands ? teamSize : teamSize - 1;
    return superOver && wickets > _superOverWickets ? _superOverWickets : wickets;
  }

  Json toJson() => {
        'oversPerInnings': oversPerInnings,
        'ballsPerOver': ballsPerOver,
        'wideRuns': wideRuns,
        'noBallRuns': noBallRuns,
        'freeHitOnNoBall': freeHitOnNoBall,
        'lastManStands': lastManStands,
        'maxOversPerBowler': maxOversPerBowler,
        'superOver': superOver,
        'trackShots': trackShots,
      };

  factory MatchRules.fromJson(Json json) => MatchRules(
        oversPerInnings: json['oversPerInnings']! as int,
        ballsPerOver: json['ballsPerOver']! as int,
        wideRuns: json['wideRuns']! as int,
        noBallRuns: json['noBallRuns']! as int,
        freeHitOnNoBall: json['freeHitOnNoBall']! as bool,
        lastManStands: json['lastManStands']! as bool,
        maxOversPerBowler: json['maxOversPerBowler'] as int?,
        superOver: json['superOver'] as bool? ?? false,
        trackShots: json['trackShots'] as bool? ?? false,
      );
}

class MatchSetup {
  MatchSetup({
    required this.id,
    required this.teamA,
    required this.teamB,
    required this.rules,
    required this.tossWinnerId,
    required this.tossDecision,
    this.venue,
  }) {
    if (teamA.id == teamB.id) throw ArgumentError('Teams must differ.');
    if (tossWinnerId != teamA.id && tossWinnerId != teamB.id) {
      throw ArgumentError('Toss winner must be one of the teams.');
    }
  }

  final String id;
  final Team teamA;
  final Team teamB;
  final MatchRules rules;
  final String tossWinnerId;
  final TossDecision tossDecision;
  final String? venue;

  String get firstBattingTeamId =>
      (tossDecision == TossDecision.bat) == (tossWinnerId == teamA.id)
          ? teamA.id
          : teamB.id;

  Team teamById(String teamId) {
    if (teamId == teamA.id) return teamA;
    if (teamId == teamB.id) return teamB;
    throw ArgumentError('Unknown team $teamId');
  }

  Team opponentOf(String teamId) {
    teamById(teamId); // validates the id
    return teamId == teamA.id ? teamB : teamA;
  }

  /// Looks a player up in either team.
  Player? playerById(String playerId) =>
      teamA.playerById(playerId) ?? teamB.playerById(playerId);

  Json toJson() => {
        'id': id,
        'teamA': teamA.toJson(),
        'teamB': teamB.toJson(),
        'rules': rules.toJson(),
        'tossWinnerId': tossWinnerId,
        'tossDecision': tossDecision.name,
        'venue': venue,
      };

  factory MatchSetup.fromJson(Json json) => MatchSetup(
        id: json['id']! as String,
        teamA: Team.fromJson(json['teamA']! as Json),
        teamB: Team.fromJson(json['teamB']! as Json),
        rules: MatchRules.fromJson(json['rules']! as Json),
        tossWinnerId: json['tossWinnerId']! as String,
        tossDecision: TossDecision.values.byName(json['tossDecision']! as String),
        venue: json['venue'] as String?,
      );
}
