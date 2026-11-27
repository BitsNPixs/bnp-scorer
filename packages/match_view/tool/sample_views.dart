// Writes sample API answers for previewing the website's match pages
// (site/match.html, site/matches.html) without real matches:
//   dart run tool/sample_views.dart <folder>
// Every match is played through the real engine with a fixed seed, so the
// samples are legal scorecards and the same on every run.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:match_view/match_view.dart';

Team _team(String id, String name, List<String> players) => Team(
      id: id,
      name: name,
      captainId: '${id}1',
      keeperId: '${id}4',
      players: [for (final (i, p) in players.indexed) Player(id: '$id${i + 1}', name: p)],
    );

MatchSetup _setup(String id, String a, String b, {int overs = 10, String? venue}) => MatchSetup(
      id: id,
      teamA: _team('${id}a', a, const ['Arun Kumar', 'Bala S', 'Charles D', 'Dinesh R', 'Ezhil M', 'Farook A', 'Ganesh P', 'Hari V']),
      teamB: _team('${id}b', b, const ['Imran K', 'Jeeva T', 'Karthik N', 'Livin D', 'Mani S', 'Naveen J', 'Prabhu R', 'Subash A']),
      rules: MatchRules(oversPerInnings: overs),
      tossWinnerId: '${id}a',
      tossDecision: TossDecision.bat,
      venue: venue,
    );

/// Plays [setup] with a seeded dice until it ends or [stopAt] says so.
MatchState _play(MatchSetup setup, int seed, {bool Function(MatchState)? stopAt}) {
  final dice = Random(seed);
  final events = <MatchEvent>[];
  final at = DateTime.utc(2026, 11, 27, 10);
  var state = ScoringEngine.replay(setup, events);
  void add(MatchEvent e) {
    state = ScoringEngine.apply(setup, events, e);
    events.add(e);
  }

  String id() => 'e${events.length}';
  while (!state.isCompleted && !(stopAt?.call(state) ?? false)) {
    final inn = state.current;
    switch (state.phase) {
      case MatchPhase.awaitingOpeners || MatchPhase.inningsBreak:
        final next = state.phase == MatchPhase.inningsBreak ? setup.opponentOf(inn.battingTeamId) : setup.teamById(inn.battingTeamId);
        add(OpenersSelected(id: id(), at: at, strikerId: next.players[0].id, nonStrikerId: next.players[1].id));
      case MatchPhase.awaitingBowler:
        final free = inn.eligibleBowlerIds;
        add(BowlerChanged(id: id(), at: at, bowlerId: free[(4 + dice.nextInt(4)) % free.length]));
      case MatchPhase.awaitingBatter:
        add(NewBatter(id: id(), at: at, batterId: inn.availableBatterIds.first));
      case MatchPhase.inPlay:
        final roll = dice.nextInt(100);
        if (roll < 6) {
          final fielder = setup.teamById(inn.bowlingTeamId).players[dice.nextInt(4)].id;
          add(BallBowled(
            id: id(),
            at: at,
            wicket: roll < 2
                ? Wicket(type: DismissalType.bowled, batterOutId: inn.strikerId!)
                : Wicket(type: DismissalType.caught, batterOutId: inn.strikerId!, fielderId: fielder),
          ));
        } else if (roll < 11) {
          add(BallBowled(id: id(), at: at, extra: ExtraType.wide));
        } else {
          final runs = roll < 40 ? 0 : roll < 68 ? 1 : roll < 78 ? 2 : roll < 91 ? 4 : 6;
          add(BallBowled(id: id(), at: at, runsOffBat: runs, boundary: runs >= 4));
        }
      case MatchPhase.completed:
        break;
    }
  }
  return state;
}

/// What the API adds to a stored card or view before sending it.
Json _sent(Json copy, String state, String owner, String saved) =>
    {...copy, 'state': state, 'ownerName': owner, 'sourceUpdateTime': saved, 'seq': 0};

void main(List<String> args) {
  final out = Directory(args.isEmpty ? 'build/sample_views' : args.first)..createSync(recursive: true);
  final now = DateTime.now().toUtc();
  String ago(Duration d) => now.subtract(d).toIso8601String();

  final matches = [
    (
      state: _play(_setup('live1', 'Melpuram Kings', 'Marthandam Strikers', venue: 'Panchayat Ground'), 7,
          stopAt: (s) => s.innings.length == 2 && s.current.legalBalls >= 40),
      now: 'live',
      owner: 'Aswin',
      saved: ago(const Duration(seconds: 20)),
    ),
    (
      state: _play(_setup('live2', 'Thuckalay Titans', 'Nagercoil Royals', overs: 8), 3, stopAt: (s) => s.current.legalBalls >= 21),
      now: 'live',
      owner: 'Lewis',
      saved: ago(const Duration(minutes: 1)),
    ),
    (
      state: _play(_setup('done1', 'Colachel Chargers', 'Kuzhithurai Lions', venue: 'St Mary\'s School Ground'), 11),
      now: 'finished',
      owner: 'Aswin',
      saved: ago(const Duration(hours: 3)),
    ),
    (
      state: _play(_setup('done2', 'Karungal Warriors', 'Eraniel Eagles', overs: 6), 5),
      now: 'finished',
      owner: 'Ananth Stephen',
      saved: ago(const Duration(days: 1, hours: 2)),
    ),
    (
      state: _play(_setup('stop1', 'Home Team', 'Trillers', overs: 5), 2, stopAt: (s) => s.current.legalBalls >= 9),
      now: 'stopped',
      owner: 'Aswin',
      saved: ago(const Duration(days: 2)),
    ),
  ];

  File('${out.path}/matches.json').writeAsStringSync(jsonEncode({
    'matches': [for (final m in matches) _sent(matchCard(m.state), m.now, m.owner, m.saved)],
    'next': null,
  }));
  for (final m in matches) {
    File('${out.path}/${m.state.setup.id}.json')
        .writeAsStringSync(jsonEncode(_sent(matchView(m.state), m.now, m.owner, m.saved)));
    stdout.writeln('${m.state.setup.id}: ${matchStatus(m.state)}');
  }
}
