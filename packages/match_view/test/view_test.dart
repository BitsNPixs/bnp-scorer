import 'dart:convert';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:match_view/match_view.dart';
import 'package:test/test.dart';

/// Lions v Tigers, three a side, one over each, Lions batting first.
MatchSetup setup() => MatchSetup(
      id: 'm1',
      teamA: Team(
        id: 'a',
        name: 'Lions',
        captainId: 'a1',
        players: const [
          Player(id: 'a1', name: 'Asha'),
          Player(id: 'a2', name: 'Bilal'),
          Player(id: 'a3', name: 'Chitra'),
        ],
      ),
      teamB: Team(
        id: 'b',
        name: 'Tigers',
        keeperId: 'b1',
        logoUrl: 'https://photos.example/tigers.jpg',
        players: const [
          Player(id: 'b1', name: 'Dev'),
          Player(id: 'b2', name: 'Esha'),
          Player(id: 'b3', name: 'Farid'),
        ],
      ),
      rules: MatchRules(oversPerInnings: 1),
      tossWinnerId: 'a',
      tossDecision: TossDecision.bat,
      venue: 'Marina Ground',
    );

/// Records events the way the app does: each one checked by the engine.
class Play {
  final setup_ = setup();
  final events = <MatchEvent>[];
  final _at = DateTime.utc(2026, 11, 27);

  MatchState get state => ScoringEngine.replay(setup_, events);
  Json get view => matchView(state);
  Json get card => matchCard(state);
  String get _id => 'e${events.length}';

  void _add(MatchEvent e) {
    ScoringEngine.apply(setup_, events, e);
    events.add(e);
  }

  void openers(String striker, String nonStriker) =>
      _add(OpenersSelected(id: _id, at: _at, strikerId: striker, nonStrikerId: nonStriker));
  void bowler(String id) => _add(BowlerChanged(id: _id, at: _at, bowlerId: id));
  void runs(int n) => _add(BallBowled(id: _id, at: _at, runsOffBat: n, boundary: n == 4 || n == 6));
  void wide() => _add(BallBowled(id: _id, at: _at, extra: ExtraType.wide));
  void caught(String fielder) => _add(BallBowled(
        id: _id,
        at: _at,
        wicket: Wicket(type: DismissalType.caught, batterOutId: state.current.strikerId!, fielderId: fielder),
      ));
  void newBatter(String id) => _add(NewBatter(id: _id, at: _at, batterId: id));
  void abandon() => _add(MatchAbandoned(id: _id, at: _at, reason: 'Rain'));

  /// Lions 14/1: Asha 4 and 1 around a wide, Bilal caught, Chitra 6, 0, 2.
  void firstInnings() {
    openers('a1', 'a2');
    bowler('b1');
    runs(4);
    wide();
    runs(1);
    caught('b2');
    newBatter('a3');
    runs(6);
    runs(0);
    runs(2);
  }

  void startChase() {
    openers('b1', 'b2');
    bowler('a1');
  }
}

Json inningsOf(Json view, int index) => (view['innings']! as List<Object?>)[index]! as Json;
List<Json> rows(Json innings, String key) => (innings[key]! as List<Object?>).cast<Json>();

void main() {
  test('before a ball: the card names the teams and the toss', () {
    final card = Play().card;
    expect(card['v'], matchViewVersion);
    expect(card['id'], 'm1');
    expect(card['teams'], [
      {'id': 'a', 'name': 'Lions', 'logoUrl': null},
      {'id': 'b', 'name': 'Tigers', 'logoUrl': 'https://photos.example/tigers.jpg'},
    ]);
    expect(card['venue'], 'Marina Ground');
    expect(card['oversPerInnings'], 1);
    expect(card['stage'], 'starting');
    expect(card['status'], 'Lions won the toss and chose to bat');
    expect(card['result'], isNull);
    expect(card['innings'], [
      {'number': 1, 'battingTeamId': 'a', 'team': 'Lions', 'runs': 0, 'wickets': 0, 'overs': '0', 'score': '0/0'},
    ]);
  });

  test('a ball makes the match live, with who is in the middle', () {
    final play = Play()
      ..openers('a1', 'a2')
      ..bowler('b1');
    expect(play.card['stage'], 'starting', reason: 'players picked, nothing bowled');
    play.runs(4);
    final view = play.view;
    expect(view['stage'], 'live');
    expect(view['status'], 'Lions 4/0 (0.1 ov)');
    expect(inningsOf(view, 0)['atCrease'], {
      'strikerId': 'a1',
      'nonStrikerId': 'a2',
      'bowlerId': 'b1',
      'partnershipRuns': 4,
      'partnershipBalls': 1,
      'freeHit': false,
    });
  });

  test('a wide alone is live too', () {
    final play = Play()
      ..openers('a1', 'a2')
      ..bowler('b1')
      ..wide();
    expect(play.card['stage'], 'live');
  });

  test('an innings reads as its scorecard does', () {
    final play = Play()..firstInnings();
    final view = play.view;
    expect(view['stage'], 'inningsBreak');
    expect(view['status'], 'Innings break · Tigers need 15');
    expect(view['toss'], {'winnerTeamId': 'a', 'decision': 'bat'});

    final innings = inningsOf(view, 0);
    expect(innings['label'], '1st innings');
    expect(innings['score'], '14/1');
    expect(innings['overs'], '1');
    expect(innings['maxOvers'], '1');
    expect(innings['complete'], isTrue);
    expect(innings['runRate'], 14.0);
    expect(innings['target'], isNull);
    expect(innings['atCrease'], isNull, reason: 'nobody is batting at the break');
    expect(innings['highlights'], 'Chitra 8 (3) · Dev 1/14');

    expect(rows(innings, 'batters'), [
      {
        'id': 'a1',
        'name': 'Asha (c)',
        'runs': 5,
        'balls': 2,
        'fours': 1,
        'sixes': 0,
        'strikeRate': 250.0,
        'out': false,
        'howOut': 'not out',
      },
      {
        'id': 'a2',
        'name': 'Bilal',
        'runs': 0,
        'balls': 1,
        'fours': 0,
        'sixes': 0,
        'strikeRate': 0.0,
        'out': true,
        'howOut': 'c Esha b Dev',
      },
      {
        'id': 'a3',
        'name': 'Chitra',
        'runs': 8,
        'balls': 3,
        'fours': 0,
        'sixes': 1,
        'strikeRate': 266.67,
        'out': false,
        'howOut': 'not out',
      },
    ]);
    expect(innings['yetToBat'], isEmpty);
    expect(innings['extras'], {'wides': 1, 'noBalls': 0, 'byes': 0, 'legByes': 0, 'total': 1});
    expect(rows(innings, 'bowlers'), [
      {
        'id': 'b1',
        'name': 'Dev (wk)',
        'overs': '1',
        'maidens': 0,
        'runs': 14,
        'wickets': 1,
        'economy': 14.0,
        'wides': 1,
        'noBalls': 0,
        'dots': 2,
      },
    ]);
    expect(rows(innings, 'fallOfWickets'), [
      {'wicket': 1, 'runs': 6, 'score': '6-1', 'batterId': 'a2', 'name': 'Bilal', 'over': '0.3'},
    ]);

    final over = rows(innings, 'overByOver').single;
    expect(over['number'], 1);
    expect(over['runs'], 14);
    expect(over['wickets'], 1);
    expect(over['score'], '14/1');
    expect(over['headline'], 'Dev to Asha & Bilal & Chitra');
    final balls = (over['balls']! as List<Object?>).cast<Json>();
    expect([for (final b in balls) b['kind']], ['four', 'extra', 'runs', 'wicket', 'six', 'dot', 'runs']);
    expect([for (final b in balls) b['legal']], [true, false, true, true, true, true, true]);
    expect([for (final b in balls) b['runs']], [4, 1, 1, 0, 6, 0, 2]);
  });

  test('batters still to come are listed until they bat', () {
    final play = Play()
      ..openers('a1', 'a2')
      ..bowler('b1')
      ..runs(1);
    expect(inningsOf(play.view, 0)['yetToBat'], [
      {'id': 'a3', 'name': 'Chitra'},
    ]);
  });

  test('a chase shows the target and what is needed', () {
    final play = Play()
      ..firstInnings()
      ..startChase()
      ..runs(6);
    final view = play.view;
    expect(view['stage'], 'live');
    expect(view['status'], 'Tigers need 9 runs from 5 balls');
    final chase = inningsOf(view, 1);
    expect(chase['label'], '2nd innings');
    expect(chase['target'], 15);
    expect(chase['runsNeeded'], 9);
    expect(chase['ballsRemaining'], 5);
    expect(chase['requiredRunRate'], 10.8);
    expect(chase['atCrease'], isNotNull);
    expect(inningsOf(view, 0)['atCrease'], isNull, reason: 'the first innings is over');
  });

  test('a finished match carries its result and its best player', () {
    final play = Play()
      ..firstInnings()
      ..startChase()
      ..runs(6)
      ..runs(6)
      ..runs(4);
    final view = play.view;
    expect(view['stage'], 'finished');
    expect(view['status'], 'Tigers won by 2 wickets (3 balls left)');
    expect(view['result'], {'kind': 'wickets', 'winnerTeamId': 'b', 'margin': 2, 'ballsRemaining': 3});
    expect(view['playerOfTheMatch'], {'id': 'b1', 'name': 'Dev'});
    expect(inningsOf(view, 1)['atCrease'], isNull);
    expect(inningsOf(view, 1)['score'], '16/0');
  });

  test('an abandoned match is finished with no result and no best player', () {
    final play = Play()
      ..openers('a1', 'a2')
      ..bowler('b1')
      ..runs(1)
      ..abandon();
    final view = play.view;
    expect(view['stage'], 'finished');
    expect(view['status'], 'No result');
    expect((view['result']! as Json)['kind'], 'noResult');
    expect(view['playerOfTheMatch'], isNull);
  });

  test('the view holds everything the card does', () {
    final play = Play()
      ..firstInnings()
      ..startChase()
      ..runs(6);
    final card = play.card;
    final view = play.view;
    for (final key in card.keys.where((k) => k != 'innings')) {
      expect(view[key], card[key], reason: key);
    }
    final lines = (card['innings']! as List<Object?>).cast<Json>();
    for (final (index, line) in lines.indexed) {
      for (final key in line.keys) {
        expect(inningsOf(view, index)[key], line[key], reason: 'innings $index $key');
      }
    }
  });

  test('both are plain JSON, safe to store and send', () {
    final play = Play()
      ..firstInnings()
      ..startChase()
      ..runs(6);
    for (final json in [play.card, play.view]) {
      expect(jsonDecode(jsonEncode(json)), json);
    }
  });
}
