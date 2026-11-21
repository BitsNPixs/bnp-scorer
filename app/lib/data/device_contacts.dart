import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// One contact the user tapped in the phone's contact picker.
class PickedContact {
  const PickedContact({required this.name, required this.number});

  final String name;

  /// As stored in the contact, spaces and all; normalise before use.
  final String number;
}

/// Thrown when the picker cannot open or read the contact. The message is
/// written for scorers.
class DeviceContactsException implements Exception {
  const DeviceContactsException(this.message);

  final String message;

  @override
  String toString() => 'DeviceContactsException: $message';
}

/// The phone's own contact picker, behind a boundary so screens can be tested
/// without it. The app sees only the contact the user taps; it never reads
/// the contact list and asks for no permission.
abstract interface class DeviceContacts {
  /// False where the picker is not built (iOS for now).
  bool get available;

  /// The tapped contact, or null when the user backs out.
  Future<PickedContact?> pickContact();
}

class PlatformDeviceContacts implements DeviceContacts {
  const PlatformDeviceContacts();

  static const _channel = MethodChannel('com.bitsnpixs.bnp_scorer/contacts');

  @override
  bool get available => Platform.isAndroid;

  @override
  Future<PickedContact?> pickContact() async {
    try {
      final picked = await _channel.invokeMapMethod<String, Object?>('pickContact');
      if (picked == null) return null;
      return PickedContact(
        name: (picked['name'] as String?)?.trim() ?? '',
        number: picked['number'] as String? ?? '',
      );
    } on PlatformException catch (e) {
      throw DeviceContactsException('Could not open your contacts (${e.message ?? e.code}).');
    } on MissingPluginException {
      throw const DeviceContactsException('Picking a contact is not available on this phone.');
    }
  }
}
