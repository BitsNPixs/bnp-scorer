import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// The kinds of push a phone can choose, stored by name on its device
/// document, so the Functions send each only to phones that want it.
enum PushKind {
  follow('Matches you follow', 'Start, wickets, milestones and the result'),
  team('Team activity', 'Join requests, being accepted or added to a team'),
  cup('Cup updates', "Your team's next fixture, who goes through, the champion");

  const PushKind(this.title, this.detail);

  final String title;
  final String detail;
}

/// A push that arrived, as the app sees it: shown by the phone when the app
/// is in the background, handed to the app while it is open.
class PushNotice {
  const PushNotice({required this.title, required this.body, this.data = const {}});

  final String title;
  final String body;

  /// What a tap should open, as the Function set it (`kind`, ids).
  final Map<String, String> data;
}

/// Firebase Cloud Messaging, behind a boundary so screens can be tested
/// without it. No token exists until [enable]: a phone that never turns a
/// kind on is never registered with Google for push.
abstract interface class PushMessages {
  /// False on builds without the cloud, and on iOS until the app has an
  /// APNs key (the paid Apple developer account).
  bool get available;

  /// Starts push and returns this phone's token, or null if it cannot get
  /// one (offline, or Google Play services missing).
  Future<String?> enable();

  /// Stops push and forgets the token.
  Future<void> disable();

  /// New tokens after the first, which Google rotates now and then.
  Stream<String> get tokenRefreshes;

  /// Pushes that arrive while the app is open (the phone shows none then).
  Stream<PushNotice> get foreground;

  /// Pushes the user tapped while the app was in the background.
  Stream<PushNotice> get opened;

  /// The push that opened the app from closed, if one did.
  Future<PushNotice?> launchNotice();
}

/// Builds without push, and the default in tests.
class NoPushMessages implements PushMessages {
  const NoPushMessages();

  @override
  bool get available => false;

  @override
  Future<String?> enable() async => null;

  @override
  Future<void> disable() async {}

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Stream<PushNotice> get foreground => const Stream.empty();

  @override
  Stream<PushNotice> get opened => const Stream.empty();

  @override
  Future<PushNotice?> launchNotice() async => null;
}

class FirebasePushMessages implements PushMessages {
  FirebasePushMessages(this._messaging);

  final FirebaseMessaging _messaging;

  static PushNotice _notice(RemoteMessage message) => PushNotice(
        title: message.notification?.title ?? '',
        body: message.notification?.body ?? '',
        data: {for (final e in message.data.entries) e.key: '${e.value}'},
      );

  @override
  bool get available => true;

  @override
  Future<String?> enable() async {
    try {
      await _messaging.setAutoInitEnabled(true);
      return await _messaging.getToken();
    } on Object catch (e) {
      debugPrint('Could not start push: $e');
      return null;
    }
  }

  @override
  Future<void> disable() async {
    try {
      await _messaging.setAutoInitEnabled(false);
      await _messaging.deleteToken();
    } on Object catch (e) {
      debugPrint('Could not stop push: $e');
    }
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<PushNotice> get foreground => FirebaseMessaging.onMessage.map(_notice);

  @override
  Stream<PushNotice> get opened => FirebaseMessaging.onMessageOpenedApp.map(_notice);

  @override
  Future<PushNotice?> launchNotice() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _notice(message);
  }
}

/// One phone registered for push: `pushDevices/{id}` in Firestore, readable
/// and writable only by its owner (firestore.rules). The field names are a
/// storage format the Functions read: never rename them.
class PushDevice {
  const PushDevice({
    required this.id,
    required this.ownerUid,
    required this.token,
    required this.platform,
    required this.kinds,
  });

  /// This install's id (not the token, which rotates).
  final String id;
  final String ownerUid;
  final String token;

  /// `android` or `ios`.
  final String platform;
  final Set<PushKind> kinds;

  Map<String, Object?> toJson() => {
        'ownerUid': ownerUid,
        'token': token,
        'platform': platform,
        'kinds': {for (final k in PushKind.values) k.name: kinds.contains(k)},
      };
}

/// Where device registrations live, behind a boundary for tests.
abstract interface class PushDevices {
  Future<void> save(PushDevice device);

  Future<void> delete(String id);

  /// Asks the Functions to send this phone a test notification.
  Future<void> requestTest(String id);
}

class FirestorePushDevices implements PushDevices {
  FirestorePushDevices(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String id) => _db.collection('pushDevices').doc(id);

  @override
  Future<void> save(PushDevice device) =>
      _doc(device.id).set({...device.toJson(), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  @override
  Future<void> delete(String id) => _doc(id).delete();

  @override
  Future<void> requestTest(String id) => _doc(id).update({'testRequestedAt': FieldValue.serverTimestamp()});
}
