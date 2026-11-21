import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/foundation.dart';

import 'accounts.dart';

/// Letters and digits that cannot be mixed up when read out or typed: no
/// 0/O, 1/I/L. Thirty-one of them, so six make close to a billion codes.
const joinCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// The six-character code players type to ask to join a team. Worked out
/// from the team id, so it never changes and nothing extra is stored to
/// make it.
String joinCodeOf(String teamId) {
  final digest = sha256.convert(utf8.encode(teamId)).bytes;
  return String.fromCharCodes([
    for (var i = 0; i < 6; i++) joinCodeAlphabet.codeUnitAt(digest[i] % joinCodeAlphabet.length),
  ]);
}

/// A typed code in the form [joinCodeOf] gives, or null when it cannot be
/// one. Case and spaces do not matter.
String? normalizeJoinCode(String raw) {
  final code = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (code.length != 6) return null;
  return code.split('').every(joinCodeAlphabet.contains) ? code : null;
}

/// A team its captain shared, and who that is.
class PublishedTeam {
  const PublishedTeam({required this.team, required this.ownerUid, required this.ownerName});

  final Team team;
  final String ownerUid;
  final String ownerName;
}

/// A player asking to join a team, by their profile id.
class JoinRequest {
  const JoinRequest({required this.playerId, required this.name});

  final String playerId;
  final String name;
}

/// Shared teams (`teams/{id}`) and the requests to join them
/// (`teams/{id}/joins/{playerId}`), in `firestore.rules`. A team is public
/// once its captain shares its invite; only the captain changes it.
abstract interface class CloudTeams {
  Future<void> publishTeam(Team team, Scorer owner);

  Future<void> unpublishTeam(String teamId);

  /// The shared team with this join code, or null.
  Future<PublishedTeam?> teamByCode(String code);

  /// Shared teams [playerId] is in.
  Future<List<PublishedTeam>> teamsOfPlayer(String playerId);

  /// Who has asked to join, live. Only the captain may read it.
  Stream<List<JoinRequest>> joins(String teamId);

  /// Asks to join as the player [playerId], whose profile the signed-in user
  /// owns (the rules check).
  Future<void> requestJoin(String teamId, {required String playerId, required String name});

  /// Removes a request, accepted or not.
  Future<void> dismissJoin(String teamId, String playerId);
}

class FirestoreCloudTeams implements CloudTeams {
  FirestoreCloudTeams(this._db);

  final FirebaseFirestore _db;

  /// Bump only for a change older app versions cannot read.
  static const schema = 1;

  CollectionReference<Map<String, Object?>> get _teams => _db.collection('teams');
  CollectionReference<Map<String, Object?>> _joins(String teamId) => _teams.doc(teamId).collection('joins');

  @override
  Future<void> publishTeam(Team team, Scorer owner) => _teams.doc(team.id).set({
        ...team.toJson(),
        'playerIds': [for (final p in team.players) p.id],
        'joinCode': joinCodeOf(team.id),
        'ownerUid': owner.uid,
        'ownerName': owner.name,
        'schema': schema,
        'savedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> unpublishTeam(String teamId) => _teams.doc(teamId).delete();

  @override
  Future<PublishedTeam?> teamByCode(String code) async {
    final query = await _teams.where('joinCode', isEqualTo: code).limit(1).get();
    return query.docs.isEmpty ? null : _tryParse(query.docs.first.id, query.docs.first.data());
  }

  @override
  Future<List<PublishedTeam>> teamsOfPlayer(String playerId) async {
    final query = await _teams.where('playerIds', arrayContains: playerId).limit(50).get();
    return [for (final doc in query.docs) ?_tryParse(doc.id, doc.data())];
  }

  @override
  Stream<List<JoinRequest>> joins(String teamId) => _joins(teamId).snapshots().map((query) => [
        for (final doc in query.docs)
          JoinRequest(playerId: doc.id, name: doc.data()['name'] as String? ?? 'A player'),
      ]);

  @override
  Future<void> requestJoin(String teamId, {required String playerId, required String name}) =>
      _joins(teamId).doc(playerId).set({'playerId': playerId, 'name': name, 'at': FieldValue.serverTimestamp()});

  @override
  Future<void> dismissJoin(String teamId, String playerId) => _joins(teamId).doc(playerId).delete();

  static PublishedTeam? _tryParse(String id, Map<String, Object?> data) {
    try {
      return parsePublishedTeam(data);
    } on Object catch (e) {
      debugPrint('Skipping shared team $id that cannot be read: $e');
      return null;
    }
  }
}

/// Reads a shared team. Throws on one this app cannot read.
PublishedTeam parsePublishedTeam(Map<String, Object?> data) {
  final schema = data['schema'];
  if (schema is int && schema > FirestoreCloudTeams.schema) {
    throw const FormatException('This team was saved by a newer version of BNP Scorer.');
  }
  return PublishedTeam(
    team: Team.fromJson(data),
    ownerUid: data['ownerUid']! as String,
    ownerName: data['ownerName'] as String? ?? 'A captain',
  );
}
