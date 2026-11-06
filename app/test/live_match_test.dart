import 'package:bnp_scorer/state/live_match.dart';
import 'package:bnp_scorer/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late InMemoryMatchRepository repo;
  late ProviderContainer container;

  setUp(() async {
    repo = InMemoryMatchRepository();
    await repo.save(sampleRecord());
    container = ProviderContainer(
      overrides: [matchRepositoryProvider.overrideWithValue(repo)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
  });

  Future<LiveMatchNotifier> load(String id) async {
    // Keep the auto-dispose provider alive for the duration of the test.
    final sub = container.listen(liveMatchProvider(id), (_, _) {});
    addTearDown(sub.close);
    await container.read(liveMatchProvider(id).future);
    return container.read(liveMatchProvider(id).notifier);
  }

  LiveMatch current() => container.read(liveMatchProvider('m1')).value!;

  test('records legal events and persists the log', () async {
    final match = await load('m1');
    expect(match.openers('a1', 'a2'), isNull);
    expect(match.bowler('b1'), isNull);
    expect(match.ball(runsOffBat: 4, boundary: true), isNull);

    expect(current().state.current.runs, 4);
    await Future<void>.delayed(Duration.zero);
    expect((await repo.load('m1'))!.events, hasLength(3));
  });

  test('illegal events return a message and never reach the log', () async {
    final match = await load('m1');
    expect(match.ball(runsOffBat: 1), 'Select the opening batters first.');
    expect(current().record.events, isEmpty);
  });

  test('undo removes the last event', () async {
    final match = await load('m1');
    match
      ..openers('a1', 'a2')
      ..bowler('b1')
      ..ball(runsOffBat: 1);
    expect(match.undo(), isTrue);
    expect(current().state.current.runs, 0);
    expect(current().record.events, hasLength(2));
  });

  test('undo with an empty log does nothing', () async {
    final match = await load('m1');
    expect(match.undo(), isFalse);
  });

  test('a failed save is flagged, and the next save clears it', () async {
    final match = await load('m1');
    repo.failSaves = true;
    expect(match.openers('a1', 'a2'), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(current().saveFailed, isTrue);
    expect(current().record.events, hasLength(1));
    expect(await repo.load('m1'), isNotNull);
    expect((await repo.load('m1'))!.events, isEmpty);

    repo.failSaves = false;
    expect(match.bowler('b1'), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(current().saveFailed, isFalse);
    expect((await repo.load('m1'))!.events, hasLength(2));
  });

  test('an unknown match id is an error', () async {
    final sub = container.listen(liveMatchProvider('nope'), (_, _) {});
    addTearDown(sub.close);
    await expectLater(
      container.read(liveMatchProvider('nope').future),
      throwsA(isA<StateError>()),
    );
  });
}
