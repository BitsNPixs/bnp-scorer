import 'package:bnp_api/projection.dart';
import 'package:match_view/match_view.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 12);

  test('a match becomes a card and a view, with who scored it and when', () {
    final copies = copiesOf(matchDoc(balls: 3), sourceUpdateTime: '2026-11-27T10:05:01.5Z', now: now);
    for (final copy in [copies.card, copies.view]) {
      expect(copy['v'], matchViewVersion);
      expect(copy['id'], 'm1');
      expect(copy['status'], 'Lions 3/0 (0.3 ov)');
      expect(copy['seq'], 5, reason: 'openers, bowler and three balls');
      expect(copy['ownerUid'], 'u1');
      expect(copy['ownerName'], 'Aswin');
      expect(copy['createdAt'], '2026-11-27T10:00:00.000Z');
      expect(copy['updatedAt'], '2026-11-27T10:05:00.000Z');
      expect(copy['sourceUpdateTime'], '2026-11-27T10:05:01.5Z');
      expect(copy['projectedAt'], '2026-11-27T12:00:00.000Z');
    }
    expect(copies.card['playerIds'], ['a1', 'a2', 'b1', 'b2']);
    expect(copies.card.containsKey('toss'), isFalse, reason: 'the card stays small');
    expect(copies.view['toss'], isNotNull);
  });

  test('a scorer with no name is still credited', () {
    final copies = copiesOf(matchDoc()..remove('ownerName'), sourceUpdateTime: 't', now: now);
    expect(copies.card['ownerName'], 'A scorer');
  });

  test('a match from before schemas existed is read', () {
    expect(copiesOf(matchDoc(schema: null), sourceUpdateTime: 't', now: now).card['id'], 'm1');
  });

  test('a match saved by a newer app is refused, not guessed at', () {
    expect(
      () => copiesOf(matchDoc(schema: matchSchema + 1), sourceUpdateTime: 't', now: now),
      throwsFormatException,
    );
  });

  test('a match the engine cannot replay is refused', () {
    final doc = matchDoc();
    // A ball before anyone is at the crease.
    doc['events'] = [(doc['events']! as List<Object?>).last];
    expect(() => copiesOf(doc, sourceUpdateTime: 't', now: now), throwsA(anything));
    expect(() => copiesOf({'ownerUid': 'u1'}, sourceUpdateTime: 't', now: now), throwsA(anything));
  });
}
