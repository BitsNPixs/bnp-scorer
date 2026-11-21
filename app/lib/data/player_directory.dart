import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cricket_engine/cricket_engine.dart';

import 'accounts.dart';
import 'ids.dart';
import 'phone_numbers.dart';

enum BattingStyle {
  right('Right-hand bat'),
  left('Left-hand bat');

  const BattingStyle(this.label);

  final String label;
}

enum BowlingArm {
  right('Right-arm'),
  left('Left-arm');

  const BowlingArm(this.label);

  final String label;
}

enum BowlingType {
  fast('fast'),
  medium('medium'),
  spin('spin');

  const BowlingType(this.label);

  final String label;
}

/// The longest name or home town a profile keeps (the rules agree).
const profileTextLimit = 60;

/// A player in the cloud directory, found by mobile number. Their [id] is the
/// `Player.id` used in every squad and match, so career stats follow them
/// across scorers. A captain can add someone before they register: the
/// player is "invited" until the owner of the number confirms it and claims
/// the profile ([ownerUid] set). Only the owner fills in the rest.
class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.name,
    this.ownerUid,
    this.role,
    this.battingStyle,
    this.bowlingArm,
    this.bowlingType,
    this.homeTown,
  });

  final String id;
  final String name;

  /// The account that confirmed the number, or null while only invited.
  final String? ownerUid;
  final PlayerRole? role;
  final BattingStyle? battingStyle;
  final BowlingArm? bowlingArm;
  final BowlingType? bowlingType;
  final String? homeTown;

  bool get claimed => ownerUid != null;

  /// "Right-arm medium", or null when neither part is set.
  String? get bowlingStyle {
    final arm = bowlingArm;
    final type = bowlingType;
    if (arm == null && type == null) return null;
    if (arm == null) return type!.label[0].toUpperCase() + type.label.substring(1);
    return type == null ? arm.label : '${arm.label} ${type.label}';
  }

  /// The player as a squad holds them.
  Player get player => Player(id: id, name: name, role: role);

  /// The fields only the owner edits, as stored.
  Map<String, Object?> detailsJson() => {
        'name': name,
        'role': role?.name,
        'battingStyle': battingStyle?.name,
        'bowlingArm': bowlingArm?.name,
        'bowlingType': bowlingType?.name,
        'homeTown': homeTown,
      };
}

/// Thrown when the directory cannot be reached or refuses a change. The
/// message is written for scorers.
class PlayerDirectoryException implements Exception {
  const PlayerDirectoryException(this.message);

  final String message;

  @override
  String toString() => 'PlayerDirectoryException: $message';
}

const offlineMessage = "You're offline. Add the name now and link the number later.";

/// Players by mobile number (`firestore.rules`: `players` and `phones`). A
/// number is stored only as its hash ([phoneHash]), readable one at a time by
/// signed-in users and never listed.
abstract interface class PlayerDirectory {
  /// The player registered or invited under [e164], or null when nobody is.
  Future<PlayerProfile?> lookupByPhone(String e164);

  /// Invites [name] under [e164] for the captain [by]. When someone else
  /// added that number first, returns their player instead.
  Future<PlayerProfile> invite(String name, String e164, Scorer by);

  /// The profile under [me]'s confirmed number, now owned by [me]: the one a
  /// captain invited, or a new one in [me]'s name.
  Future<PlayerProfile> claim(Scorer me);

  /// One player as they change. Null when there is no such player.
  Stream<PlayerProfile?> watch(String playerId);

  /// Saves the owner's own details: name, role, styles and home town.
  Future<void> saveDetails(PlayerProfile profile);
}

class FirestorePlayerDirectory implements PlayerDirectory {
  FirestorePlayerDirectory(this._db, {String Function() makeId = newId}) : _makeId = makeId;

  final FirebaseFirestore _db;
  final String Function() _makeId;

  /// Bump only for a change older app versions cannot read.
  static const schema = 1;

  /// A lookup gives up after this long, so a captain on a poor signal can
  /// add the name instead.
  static const timeout = Duration(seconds: 10);
  static const _fromServer = GetOptions(source: Source.server);

  CollectionReference<Map<String, Object?>> get _players => _db.collection('players');
  CollectionReference<Map<String, Object?>> get _phones => _db.collection('phones');

  @override
  Future<PlayerProfile?> lookupByPhone(String e164) => _guard(() async {
        final phone = await _phones.doc(phoneHash(e164)).get(_fromServer);
        final id = phone.data()?['playerId'];
        if (id is! String) return null;
        final player = await _players.doc(id).get(_fromServer);
        final data = player.data();
        if (data == null) throw const PlayerDirectoryException('This number cannot be added right now.');
        return parsePlayerProfile(data);
      });

  @override
  Future<PlayerProfile> invite(String name, String e164, Scorer by) => _guard(() async {
        final id = _makeId();
        // One batch: the rules check the phone points at a player this captain
        // just created. A number already taken refuses the whole batch.
        final batch = _db.batch()
          ..set(_players.doc(id), _newPlayer(id, name, createdBy: by.uid))
          ..set(_phones.doc(phoneHash(e164)), {'playerId': id, 'createdBy': by.uid});
        try {
          await batch.commit();
          return PlayerProfile(id: id, name: name);
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied') rethrow;
          final first = await lookupByPhone(e164);
          if (first == null) rethrow;
          return first;
        }
      });

  @override
  Future<PlayerProfile> claim(Scorer me) => _guard(() async {
        final phone = me.phone;
        if (phone == null) throw const PlayerDirectoryException('Confirm your mobile number first.');
        final phoneRef = _phones.doc(phoneHash(phone));
        final existing = (await phoneRef.get(_fromServer)).data();
        final invitedId = existing?['playerId'];
        if (invitedId is String) {
          final playerRef = _players.doc(invitedId);
          if (existing?['claimedBy'] != me.uid) {
            await (_db.batch()
                  ..update(phoneRef, {'claimedBy': me.uid})
                  ..update(playerRef, {'ownerUid': me.uid, 'savedAt': FieldValue.serverTimestamp()}))
                .commit();
          }
          final data = (await playerRef.get(_fromServer)).data();
          if (data == null) throw const PlayerDirectoryException('Your profile could not be read. Try again.');
          return parsePlayerProfile(data);
        }
        final id = _makeId();
        await (_db.batch()
              ..set(_players.doc(id), _newPlayer(id, me.name, createdBy: me.uid, ownerUid: me.uid))
              ..set(phoneRef, {'playerId': id, 'createdBy': me.uid, 'claimedBy': me.uid}))
            .commit();
        return PlayerProfile(id: id, name: me.name, ownerUid: me.uid);
      });

  @override
  Stream<PlayerProfile?> watch(String playerId) => _players.doc(playerId).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : parsePlayerProfile(data);
      });

  @override
  Future<void> saveDetails(PlayerProfile profile) => _guard(
        () => _players.doc(profile.id).update({...profile.detailsJson(), 'savedAt': FieldValue.serverTimestamp()}),
      );

  Map<String, Object?> _newPlayer(String id, String name, {required String createdBy, String? ownerUid}) => {
        'id': id,
        'name': name,
        'createdBy': createdBy,
        'ownerUid': ownerUid,
        'schema': schema,
        'savedAt': FieldValue.serverTimestamp(),
      };

  /// Turns timeouts and Firestore errors into messages for scorers.
  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(timeout);
    } on TimeoutException {
      throw const PlayerDirectoryException(offlineMessage);
    } on FirebaseException catch (e) {
      throw PlayerDirectoryException(directoryErrorMessage(e.code));
    }
  }
}

/// What to tell a scorer when the directory fails, by Firestore error code.
String directoryErrorMessage(String code) => switch (code) {
      'unavailable' || 'deadline-exceeded' => offlineMessage,
      'permission-denied' || 'unauthenticated' => 'The cloud refused this. Sign in again and retry.',
      _ => 'Could not reach the player list ($code).',
    };

/// Reads a player document. Throws on one this app cannot read.
PlayerProfile parsePlayerProfile(Map<String, Object?> data) {
  final schema = data['schema'];
  if (schema is int && schema > FirestorePlayerDirectory.schema) {
    throw const FormatException('This was saved by a newer version of BNP Scorer.');
  }
  T? named<T extends Enum>(List<T> values, Object? name) => values.where((v) => v.name == name).firstOrNull;
  return PlayerProfile(
    id: data['id']! as String,
    name: data['name']! as String,
    ownerUid: data['ownerUid'] as String?,
    role: named(PlayerRole.values, data['role']),
    battingStyle: named(BattingStyle.values, data['battingStyle']),
    bowlingArm: named(BowlingArm.values, data['bowlingArm']),
    bowlingType: named(BowlingType.values, data['bowlingType']),
    homeTown: data['homeTown'] as String?,
  );
}
