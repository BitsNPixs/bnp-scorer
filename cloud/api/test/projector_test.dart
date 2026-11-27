import 'package:bnp_api/projector.dart';
import 'package:bnp_api/store.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late FakeMatchStore store;
  late Projector projector;
  late List<Map<String, Object?>> logs;

  setUp(() {
    store = FakeMatchStore();
    logs = [];
    projector = Projector(store, now: () => DateTime.utc(2026, 11, 27, 12), log: logs.add);
  });

  test('a saved match gets its card and view', () async {
    store.save('m1', matchDoc(balls: 2), '2026-11-27T10:05:01Z');
    expect(await projector.project('m1'), Outcome.stored);
    expect(store.cards['m1']!['status'], 'Lions 2/0 (0.2 ov)');
    expect(store.views['m1']!['status'], 'Lions 2/0 (0.2 ov)');
    expect(store.views['m1']!['sourceUpdateTime'], '2026-11-27T10:05:01Z');
    expect(logs.single['message'], 'stored');
  });

  test('each ball replaces the copy, and an undo takes it back', () async {
    store.save('m1', matchDoc(balls: 2), '2026-11-27T10:05:01Z');
    await projector.project('m1');
    store.save('m1', matchDoc(balls: 3), '2026-11-27T10:05:09Z');
    await projector.project('m1');
    expect(store.cards['m1']!['seq'], 5);
    store.save('m1', matchDoc(balls: 1), '2026-11-27T10:05:20Z');
    expect(await projector.project('m1'), Outcome.stored, reason: 'fewer events, but a newer save');
    expect(store.cards['m1']!['seq'], 3);
    expect(store.views['m1']!['status'], 'Lions 1/0 (0.1 ov)');
  });

  test('the same save delivered twice is stored again, harmlessly', () async {
    store.save('m1', matchDoc(), '2026-11-27T10:05:01Z');
    await projector.project('m1');
    expect(await projector.project('m1'), Outcome.stored);
    expect(store.writes, 2);
  });

  test('a copy made from a newer save is never replaced by an older one', () async {
    store.save('m1', matchDoc(balls: 2), '2026-11-27T10:05:01.250Z');
    store.rivalCopy('m1', '2026-11-27T10:05:01.900Z');
    expect(await projector.project('m1'), Outcome.alreadyNewer);
    expect(store.views['m1']!['rival'], isTrue);
    expect(store.writes, 0);
  });

  test('a rival write in between is noticed, and the match is done again', () async {
    store.save('m1', matchDoc(balls: 2), '2026-11-27T10:05:01Z');
    // Another instance stores an older save just before this one writes.
    store.rivals.add(() => store.rivalCopy('m1', '2026-11-27T10:05:00Z'));
    expect(await projector.project('m1'), Outcome.stored);
    expect(store.views['m1']!['status'], 'Lions 2/0 (0.2 ov)');
    expect(store.views['m1']!.containsKey('rival'), isFalse);
  });

  test('a rival that stored something newer wins', () async {
    store.save('m1', matchDoc(balls: 2), '2026-11-27T10:05:01Z');
    store.rivals.add(() => store.rivalCopy('m1', '2026-11-27T10:05:30Z'));
    expect(await projector.project('m1'), Outcome.alreadyNewer);
    expect(store.views['m1']!['rival'], isTrue);
  });

  test('endless rivals end in an error, so the event is sent again', () async {
    store.save('m1', matchDoc(), '2026-11-27T10:05:01Z');
    for (var i = 0; i < 10; i++) {
      store.rivals.add(() => store.rivalCopy('m1', '2026-11-27T10:05:00Z'));
    }
    await expectLater(projector.project('m1'), throwsA(isA<CopyChanged>()));
  });

  test('a deleted match loses its copies', () async {
    store.save('m1', matchDoc(), '2026-11-27T10:05:01Z');
    await projector.project('m1');
    store.matches.remove('m1');
    expect(await projector.project('m1'), Outcome.removed);
    expect(store.cards, isEmpty);
    expect(store.views, isEmpty);
  });

  test('a match that cannot be read keeps its last good copies', () async {
    store.save('m1', matchDoc(balls: 2), '2026-11-27T10:05:01Z');
    await projector.project('m1');
    store.save('m1', matchDoc(schema: 99), '2026-11-27T10:06:00Z');
    expect(await projector.project('m1'), Outcome.unreadable);
    expect(store.views['m1']!['status'], 'Lions 2/0 (0.2 ov)');
    expect(logs.last['severity'], 'ERROR');
    expect(logs.last['matchId'], 'm1');
  });
}
