import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'accounts.dart';
import 'app_settings.dart';
import 'push_messages.dart';

/// Keeps this phone's `pushDevices` registration in step with who is signed
/// in and which pushes they want. Only a signed-in scorer is registered, so
/// the Functions can send to "the captain of this team" or "this player".
class PushRegistration {
  PushRegistration({required this.push, required this.devices, required this.settings, String? platform})
      : _platform = platform ?? (Platform.isIOS ? 'ios' : 'android');

  final PushMessages push;
  final PushDevices? devices;
  final AppSettings settings;
  final String _platform;

  bool get available => push.available && devices != null;

  /// Registers or updates this phone when [scorer] wants any of [kinds];
  /// otherwise removes it. Failures are logged, never thrown: push is extra,
  /// and the next change or launch tries again.
  Future<void> sync(Scorer? scorer, Set<PushKind> kinds) async {
    final devices = this.devices;
    if (!push.available || devices == null) return;
    if (scorer == null || kinds.isEmpty) {
      // Signed out, the registration was already removed by [forget]
      // (Firestore would refuse it now); with no kinds left, remove it.
      if (scorer != null) await forget();
      return;
    }
    final token = await push.enable();
    if (token == null) return;
    PushDevice device(String id) =>
        PushDevice(id: id, ownerUid: scorer.uid, token: token, platform: _platform, kinds: kinds);
    try {
      await devices.save(device(settings.deviceId));
    } on Object catch (e) {
      // A registration left by the last account on this phone (its removal
      // failed while signing out) is not ours to change: start a new one.
      debugPrint('Could not register for push, trying a new registration: $e');
      try {
        await devices.save(device(await settings.renewDeviceId()));
      } on Object catch (e) {
        debugPrint('Could not register for push: $e');
        return;
      }
    }
    await settings.setPushRegistered(true);
  }

  /// Removes this phone's registration and token. Call before signing out,
  /// while Firestore still knows who owns it, so the next person on this
  /// phone never gets the last one's notifications.
  Future<void> forget() async {
    final devices = this.devices;
    if (!push.available || devices == null || !settings.pushRegistered) return;
    try {
      await devices.delete(settings.deviceId);
      await settings.setPushRegistered(false);
    } on Object catch (e) {
      debugPrint('Could not remove the push registration: $e');
    }
    await push.disable();
  }

  /// Asks the Functions for a test push to this phone.
  Future<void> requestTest() => devices!.requestTest(settings.deviceId);
}
