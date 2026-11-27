import 'package:bnp_api/store.dart';
import 'package:cricket_engine/cricket_engine.dart';

final _at = DateTime.utc(2026, 11, 27);

/// A `matches/{id}` document as the app publishes it: Lions v Tigers, two a
/// side, one over each, with [balls] singles bowled.
Json matchDoc({String id = 'm1', int balls = 2, Object? schema = 1}) {
  final setup = MatchSetup(
    id: id,
    teamA: Team(id: 'a', name: 'Lions', players: const [Player(id: 'a1', name: 'Asha'), Player(id: 'a2', name: 'Bilal')]),
    teamB: Team(id: 'b', name: 'Tigers', players: const [Player(id: 'b1', name: 'Dev'), Player(id: 'b2', name: 'Esha')]),
    rules: MatchRules(oversPerInnings: 1),
    tossWinnerId: 'a',
    tossDecision: TossDecision.bat,
  );
  final events = <MatchEvent>[
    OpenersSelected(id: 'e0', at: _at, strikerId: 'a1', nonStrikerId: 'a2'),
    BowlerChanged(id: 'e1', at: _at, bowlerId: 'b1'),
    for (var i = 0; i < balls; i++) BallBowled(id: 'b$i', at: _at, runsOffBat: 1),
  ];
  ScoringEngine.replay(setup, events); // The fixture itself must be legal.
  return {
    'setup': setup.toJson(),
    'events': [for (final e in events) e.toJson()],
    'createdAt': '2026-11-27T10:00:00.000Z',
    'updatedAt': '2026-11-27T10:05:00.000Z',
    'playerIds': ['a1', 'a2', 'b1', 'b2'],
    'ownerUid': 'u1',
    'ownerName': 'Aswin',
    'schema': schema,
  };
}

/// Firestore in memory. Copies get a new update time on every write.
class FakeMatchStore implements MatchStore {
  final matches = <String, SourceMatch>{};
  final cards = <String, Json>{};
  final views = <String, Json>{};
  final _copyTimes = <String, String>{};
  var _clock = 0;

  /// Rival writes to slip in just before the next [writeCopies].
  final rivals = <void Function()>[];
  var writes = 0;

  void save(String id, Json data, String updateTime) =>
      matches[id] = SourceMatch(id: id, data: data, updateTime: updateTime);

  /// Stores a copy as another instance of the server would.
  void rivalCopy(String id, String sourceUpdateTime) {
    views[id] = {'sourceUpdateTime': sourceUpdateTime, 'rival': true};
    cards[id] = {'sourceUpdateTime': sourceUpdateTime, 'rival': true};
    _copyTimes[id] = 'copy-${_clock++}';
  }

  @override
  Future<SourceMatch?> readMatch(String id) async => matches[id];

  @override
  Future<CopyState?> readCopy(String id) async {
    final view = views[id];
    if (view == null) return null;
    return CopyState(sourceUpdateTime: view['sourceUpdateTime'] as String?, updateTime: _copyTimes[id]!);
  }

  @override
  Future<void> writeCopies(String id, {required Json card, required Json view, required CopyState? seen}) async {
    if (rivals.isNotEmpty) rivals.removeAt(0)();
    if (seen?.updateTime != _copyTimes[id]) throw const CopyChanged();
    cards[id] = card;
    views[id] = view;
    _copyTimes[id] = 'copy-${_clock++}';
    writes++;
  }

  @override
  Future<void> deleteCopies(String id) async {
    cards.remove(id);
    views.remove(id);
    _copyTimes.remove(id);
  }

  @override
  Future<({List<SourceMatch> matches, String? nextPageToken})> listMatches({String? pageToken, int pageSize = 50}) async {
    final all = matches.values.toList();
    final from = pageToken == null ? 0 : int.parse(pageToken);
    final to = from + pageSize > all.length ? all.length : from + pageSize;
    return (matches: all.sublist(from, to), nextPageToken: to < all.length ? '$to' : null);
  }
}
