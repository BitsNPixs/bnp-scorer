import 'dart:convert';

import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/data/syncing_match_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _asha = Scorer(uid: 'u1', name: 'Asha Scorer');
const _bilal = Scorer(uid: 'u2', name: 'Bilal Scorer');

MatchRecord _published(String id, String? by) {
  final record = sampleRecord(id: id);
  return MatchRecord(
    setup: record.setup,
    events: record.events,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
    publishedBy: by,
  );
}

void main() {
  group('MatchRecord.publishedBy', () {
    test('survives JSON, and private matches keep their old format', () {
      final public = _published('m1', 'u1');
      final restored = MatchRecord.fromJson(jsonDecode(jsonEncode(public.toJson())) as Map<String, Object?>);
      expect(restored.publishedBy, 'u1');

      final private = sampleRecord();
      expect(private.toJson().containsKey('publishedBy'), isFalse);
      expect(MatchRecord.fromJson(private.toJson()).publishedBy, isNull);
    });

    test('is kept as balls are added', () {
      expect(_published('m1', 'u1').withEvents(const []).publishedBy, 'u1');
    });
  });

  group('SyncingMatchRepository', () {
    late InMemoryMatchRepository local;
    late FakeCloudMatches cloud;
    late FakeAccounts accounts;
    late SyncingMatchRepository repository;

    setUp(() {
      local = InMemoryMatchRepository();
      cloud = FakeCloudMatches();
      accounts = FakeAccounts(signedIn: _asha);
      repository = SyncingMatchRepository(local, cloud, accounts);
    });

    test('a private match stays on the phone', () async {
      await repository.save(sampleRecord());
      await pumpEventQueue();
      expect(local.records, contains('m1'));
      expect(cloud.published, isEmpty);
    });

    test("the scorer's published match goes to the cloud with their name", () async {
      await repository.save(_published('m1', 'u1'));
      await pumpEventQueue();
      expect(local.records, contains('m1'));
      expect(cloud.published, contains('m1'));
      expect(cloud.owners['m1']!.name, 'Asha Scorer');
    });

    test("another scorer's match, or any match while signed out, is not sent", () async {
      await repository.save(_published('m1', 'u2'));
      await accounts.signOut();
      await repository.save(_published('m2', 'u1'));
      await pumpEventQueue();
      expect(local.records.keys, containsAll(['m1', 'm2']));
      expect(cloud.published, isEmpty);
    });

    test('signing in as someone else does not send the first scorer\'s match', () async {
      await accounts.signOut();
      accounts.nextSignIn = _bilal;
      await accounts.signIn();
      await repository.save(_published('m1', 'u1'));
      await pumpEventQueue();
      expect(cloud.published, isEmpty);
    });

    test('a failed cloud write never fails the save on the phone', () async {
      cloud.failWrites = true;
      await expectLater(repository.save(_published('m1', 'u1')), completes);
      await pumpEventQueue();
      expect(local.records, contains('m1'));
      expect(cloud.published, isEmpty);
    });

    test('deleting a published match takes it off the cloud; a private one is left alone', () async {
      await repository.save(_published('m1', 'u1'));
      await repository.save(sampleRecord(id: 'm2'));
      await repository.delete('m1');
      await repository.delete('m2');
      await pumpEventQueue();
      expect(local.records, isEmpty);
      expect(cloud.unpublished, ['m1']);
    });

    test('loads come from the phone', () async {
      await local.save(sampleRecord());
      expect(await repository.load('m1'), isNotNull);
      expect(await repository.loadAll(), hasLength(1));
    });
  });

  group('LocalOnlyAccounts', () {
    test('offers no sign-in and explains why', () async {
      const accounts = LocalOnlyAccounts();
      expect(accounts.available, isFalse);
      expect(accounts.current, isNull);
      expect(await accounts.changes.first, isNull);
      expect(accounts.signIn, throwsA(isA<AccountsException>()));
    });
  });
}
