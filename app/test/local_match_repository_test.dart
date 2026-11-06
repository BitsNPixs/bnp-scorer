import 'package:cricket_engine/cricket_engine.dart';
import 'package:bnp_scorer/data/local_match_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Future<LocalMatchRepository> _repository([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return LocalMatchRepository(await SharedPreferences.getInstance());
}

void main() {
  test('saves, loads and lists newest first', () async {
    final repo = await _repository();
    await repo.save(sampleRecord(id: 'old', updatedAt: DateTime.utc(2026, 1, 1)));
    await repo.save(sampleRecord(id: 'new', updatedAt: DateTime.utc(2026, 2, 1)));

    expect((await repo.loadAll()).map((r) => r.id), ['new', 'old']);
    expect((await repo.load('old'))!.setup.teamA.name, 'Ammapet Kings');
    expect(await repo.load('missing'), isNull);
  });

  test('re-saving a match updates it without duplicating it', () async {
    final repo = await _repository();
    await repo.save(sampleRecord());
    await repo.save(sampleRecord(events: [
      OpenersSelected(id: 'e1', at: DateTime.utc(2026), strikerId: 'a1', nonStrikerId: 'a2'),
    ]));

    final all = await repo.loadAll();
    expect(all, hasLength(1));
    expect(all.single.events.single, isA<OpenersSelected>());
  });

  test('delete removes the match', () async {
    final repo = await _repository();
    await repo.save(sampleRecord());
    await repo.delete('m1');
    expect(await repo.loadAll(), isEmpty);
    expect(await repo.load('m1'), isNull);
  });

  test('a corrupt record is skipped instead of breaking the list', () async {
    final repo = await _repository({
      'bnp_scorer.matchIds': ['bad'],
      'bnp_scorer.match.bad': '{not json',
    });
    await repo.save(sampleRecord());
    expect((await repo.loadAll()).map((r) => r.id), ['m1']);
  });
}
