import 'dart:convert';

import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/backfill.dart';
import 'package:bnp_scorer/data/cloud_matches.dart';
import 'package:bnp_scorer/data/match_record.dart';
import 'package:bnp_scorer/data/syncing_match_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('publicScorerName', () {
    test('uses the Google display name, trimmed', () {
      expect(publicScorerName('  Asha Rao '), 'Asha Rao');
    });

    test('never publishes an email address, even as the display name', () {
      expect(publicScorerName('asha.rao@example.com'), 'Scorer');
    });

    test('falls back to "Scorer" with no name', () {
      expect(publicScorerName(null), 'Scorer');
      expect(publicScorerName('   '), 'Scorer');
    });
  });

  group('LocalOnlyAccounts', () {
    test('offers no sign-in and explains why', () async {
      const accounts = LocalOnlyAccounts();
      expect(accounts.available, isFalse);
      expect(accounts.current, isNull);
      expect(await accounts.changes.first, isNull);
      expect(accounts.signIn, throwsA(isA<AccountsException>()));
      expect(() => accounts.requestPhoneCode('+919876543210'), throwsA(isA<AccountsException>()));
      const request = PhoneCodeRequest(phone: '+919876543210', verificationId: 'v');
      expect(() => accounts.linkPhone(request, '123456'), throwsA(isA<AccountsException>()));
    });
  });

  group('Scorer', () {
    test('is equal by account, name and number, so a token refresh is not a change', () {
      const a = Scorer(uid: 'u1', name: 'Asha', phone: '+919876543210');
      expect(a, const Scorer(uid: 'u1', name: 'Asha', phone: '+919876543210'));
      expect(a.hashCode, const Scorer(uid: 'u1', name: 'Asha', phone: '+919876543210').hashCode);
      expect(a, isNot(const Scorer(uid: 'u1', name: 'Asha')));
      expect(a, isNot(const Scorer(uid: 'u2', name: 'Asha', phone: '+919876543210')));
    });
  });

  group('phoneErrorMessage', () {
    test('explains the failures a player can fix', () {
      expect(phoneErrorMessage('invalid-verification-code'), contains('code is not right'));
      expect(phoneErrorMessage('session-expired'), contains('expired'));
      expect(phoneErrorMessage('credential-already-in-use'), contains('another BNP Scorer account'));
      expect(phoneErrorMessage('too-many-requests'), contains('Too many tries'));
      expect(phoneErrorMessage('network-request-failed'), contains('No internet'));
    });

    test('names which setup step is missing, so it can be fixed', () {
      for (final code in ['operation-not-allowed', 'app-not-authorized', 'missing-client-identifier', 'billing-not-enabled']) {
        expect(phoneErrorMessage(code), 'Confirming numbers is not set up yet ($code). Try again after the next update.');
      }
    });

    test('names an unknown code rather than hiding it', () {
      expect(phoneErrorMessage('something-new'), 'Could not confirm the number (something-new).');
    });
  });

  group('FakeAccounts phone', () {
    test('a right code puts the number on the scorer, a wrong one does not', () async {
      final accounts = FakeAccounts(signedIn: _asha);
      final request = await accounts.requestPhoneCode('+919876543210');
      expect(request, isNotNull);
      await expectLater(accounts.linkPhone(request!, '000000'), throwsA(isA<AccountsException>()));
      expect(accounts.current!.phone, isNull);
      await accounts.linkPhone(request, ' 123456 ');
      expect(accounts.current!.phone, '+919876543210');
    });

    test('a phone that reads the code itself needs no code', () async {
      final accounts = FakeAccounts(signedIn: _asha)..autoVerify = true;
      expect(await accounts.requestPhoneCode('+919876543210'), isNull);
      expect(accounts.current!.phone, '+919876543210');
    });

    test('needs a signed-in scorer', () async {
      expect(() => FakeAccounts().requestPhoneCode('+919876543210'), throwsA(isA<AccountsException>()));
    });
  });

  group('playerIds', () {
    test('lists everyone picked, both sides', () {
      expect(matchPlayerIds(sampleRecord().setup), ['a1', 'a2', 'a3', 'a4', 'b1', 'b2', 'b3', 'b4']);
    });

    test('byPlayer finds the published matches a player was in', () async {
      final cloud = FakeCloudMatches();
      await cloud.publish(_published('m1', 'u1'), _asha);
      await cloud.publish(_published('m2', 'u1'), _asha);
      expect((await cloud.byPlayer('b3')).map((m) => m.record.id), unorderedEquals(['m1', 'm2']));
      expect(await cloud.byPlayer('zz'), isEmpty);
      expect(await cloud.byPlayer('b3', limit: 1), hasLength(1));
    });
  });

  group('sending published matches again for playerIds', () {
    late InMemoryMatchRepository local;
    late FakeCloudMatches cloud;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      local = InMemoryMatchRepository();
      cloud = FakeCloudMatches();
      await local.save(_published('mine', 'u1'));
      await local.save(_published('theirs', 'u2'));
      await local.save(sampleRecord(id: 'private'));
    });

    Future<void> run(Scorer scorer) =>
        republishForPlayerIds(prefs: prefs, local: local, cloud: cloud, scorer: scorer);

    test("sends only the scorer's own published matches", () async {
      await run(_asha);
      expect(cloud.published.keys, ['mine']);
      expect(cloud.owners['mine'], _asha);
    });

    test('runs once per account on this phone', () async {
      await run(_asha);
      cloud.published.clear();
      await run(_asha);
      expect(cloud.published, isEmpty);
      await run(_bilal);
      expect(cloud.published.keys, ['theirs']);
      expect(prefs.getStringList(playerIdsBackfillKey), ['u1', 'u2']);
    });

    test('a failed send is tried again next time', () async {
      cloud.failWrites = true;
      await run(_asha);
      expect(prefs.getStringList(playerIdsBackfillKey), isNull);
      cloud.failWrites = false;
      await run(_asha);
      expect(cloud.published.keys, ['mine']);
    });

    test('starts when a scorer signs in', () async {
      final accounts = FakeAccounts();
      final sub = backfillPlayerIdsOnSignIn(accounts: accounts, prefs: prefs, local: local, cloud: cloud);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(cloud.published, isEmpty);
      await accounts.signIn();
      await pumpEventQueue();
      expect(cloud.published.keys, ['mine']);
    });
  });
}
