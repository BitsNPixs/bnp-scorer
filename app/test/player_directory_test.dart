import 'package:bnp_scorer/data/accounts.dart';
import 'package:bnp_scorer/data/player_directory.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

// Made-up numbers: never put a real player's number in a test.
const _ravi = '+919876543210';
const _other = '+919876543211';
const _captain = Scorer(uid: 'c1', name: 'Captain Asha');
const _raviAccount = Scorer(uid: 'u9', name: 'Ravi Kumar', phone: _ravi);

void main() {
  group('the directory (fake, as the screens use it)', () {
    late FakePlayerDirectory directory;
    setUp(() => directory = FakePlayerDirectory());

    test('a number nobody added finds nobody', () async {
      expect(await directory.lookupByPhone(_ravi), isNull);
    });

    test('a captain invites a player, and the next lookup finds them unclaimed', () async {
      final invited = await directory.invite('Ravi', _ravi, _captain);
      expect(invited.claimed, isFalse);
      final found = await directory.lookupByPhone(_ravi);
      expect(found!.id, invited.id);
      expect(found.name, 'Ravi');
      expect(found.player.id, invited.id);
    });

    test('a second captain adding the same number gets the first player', () async {
      final first = await directory.invite('Ravi', _ravi, _captain);
      final second = await directory.invite('Ravi K', _ravi, const Scorer(uid: 'c2', name: 'Bilal'));
      expect(second.id, first.id);
      expect(second.name, 'Ravi');
      expect(directory.players, hasLength(1));
    });

    test('claiming an invited number keeps its id, so its stats stay', () async {
      final invited = await directory.invite('Ravi', _ravi, _captain);
      final mine = await directory.claim(_raviAccount);
      expect(mine.id, invited.id);
      expect(mine.ownerUid, 'u9');
      expect(mine.claimed, isTrue);
      expect((await directory.lookupByPhone(_ravi))!.claimed, isTrue);
    });

    test('claiming a new number makes a profile in the account name', () async {
      final mine = await directory.claim(_raviAccount);
      expect(mine.name, 'Ravi Kumar');
      expect(mine.claimed, isTrue);
      expect((await directory.lookupByPhone(_ravi))!.id, mine.id);
      expect(await directory.lookupByPhone(_other), isNull);
    });

    test('claiming needs a confirmed number', () async {
      expect(() => directory.claim(_captain), throwsA(isA<PlayerDirectoryException>()));
    });

    test('offline, every call says so', () async {
      directory.offline = true;
      expect(
        () => directory.lookupByPhone(_ravi),
        throwsA(isA<PlayerDirectoryException>().having((e) => e.message, 'message', offlineMessage)),
      );
      expect(() => directory.invite('Ravi', _ravi, _captain), throwsA(isA<PlayerDirectoryException>()));
    });

    test('watch follows a player as they are claimed', () async {
      final invited = await directory.invite('Ravi', _ravi, _captain);
      final seen = expectLater(directory.watch(invited.id).map((p) => p?.claimed), emitsInOrder([false, true]));
      await Future<void>.delayed(Duration.zero);
      await directory.claim(_raviAccount);
      await seen;
    });
  });

  group('parsePlayerProfile', () {
    test('reads a player document', () {
      final p = parsePlayerProfile({'id': 'p1', 'name': 'Ravi', 'ownerUid': null, 'schema': 1});
      expect(p.id, 'p1');
      expect(p.name, 'Ravi');
      expect(p.claimed, isFalse);
      expect(parsePlayerProfile({'id': 'p1', 'name': 'Ravi', 'ownerUid': 'u9'}).claimed, isTrue);
    });

    test('reads the details a player fills in, and ignores names it does not know', () {
      final p = parsePlayerProfile({
        'id': 'p1',
        'name': 'Ravi',
        'ownerUid': 'u9',
        'role': 'allRounder',
        'battingStyle': 'left',
        'bowlingArm': 'right',
        'bowlingType': 'spin',
        'homeTown': 'Arumanai',
      });
      expect(p.role, PlayerRole.allRounder);
      expect(p.battingStyle, BattingStyle.left);
      expect(p.bowlingStyle, 'Right-arm spin');
      expect(p.homeTown, 'Arumanai');
      expect(p.player.role, PlayerRole.allRounder);
      final odd = parsePlayerProfile({'id': 'p1', 'name': 'Ravi', 'battingStyle': 'switch'});
      expect(odd.battingStyle, isNull);
    });

    test('details survive a round trip', () {
      const p = PlayerProfile(
        id: 'p1',
        name: 'Ravi',
        role: PlayerRole.bowler,
        battingStyle: BattingStyle.right,
        bowlingArm: BowlingArm.left,
        bowlingType: BowlingType.fast,
        homeTown: 'Arumanai',
      );
      final back = parsePlayerProfile({'id': 'p1', ...p.detailsJson()});
      expect(back.detailsJson(), p.detailsJson());
    });

    test('bowling style reads naturally from either part', () {
      expect(const PlayerProfile(id: 'p', name: 'R').bowlingStyle, isNull);
      expect(const PlayerProfile(id: 'p', name: 'R', bowlingArm: BowlingArm.left).bowlingStyle, 'Left-arm');
      expect(const PlayerProfile(id: 'p', name: 'R', bowlingType: BowlingType.medium).bowlingStyle, 'Medium');
    });

    test('refuses one saved by a newer version', () {
      expect(
        () => parsePlayerProfile({'id': 'p1', 'name': 'Ravi', 'schema': FirestorePlayerDirectory.schema + 1}),
        throwsFormatException,
      );
    });
  });

  test('directoryErrorMessage treats a lost connection as offline', () {
    expect(directoryErrorMessage('unavailable'), offlineMessage);
    expect(directoryErrorMessage('deadline-exceeded'), offlineMessage);
    expect(directoryErrorMessage('permission-denied'), contains('refused'));
    expect(directoryErrorMessage('weird'), contains('(weird)'));
  });
}
