import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// The phone's share sheet and file picker, behind one boundary so screens can
/// be tested without them.
abstract interface class DeviceFiles {
  Future<void> shareImage(Uint8List png, {required String caption});

  Future<void> shareTextFile(String name, String contents);

  /// Plain text, for a message in WhatsApp or an email.
  Future<void> shareText(String text, {required String subject});

  /// The contents of a file the user picks, or null if they cancel.
  Future<String?> pickTextFile();
}

class PlatformDeviceFiles implements DeviceFiles {
  const PlatformDeviceFiles();

  @override
  Future<void> shareImage(Uint8List png, {required String caption}) async {
    await SharePlus.instance.share(ShareParams(
      text: caption,
      files: [XFile.fromData(png, mimeType: 'image/png')],
      fileNameOverrides: const ['scorecard.png'],
    ));
  }

  @override
  Future<void> shareTextFile(String name, String contents) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(utf8.encode(contents), mimeType: 'application/json')],
      fileNameOverrides: [name],
    ));
  }

  @override
  Future<void> shareText(String text, {required String subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  @override
  Future<String?> pickTextFile() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return null;
    return decodeTextFile(await files.first.readAsBytes());
  }
}

/// A file's text: UTF-8, as backups and "CSV UTF-8" are written, or else
/// Windows-1252 (read as Latin-1), which plain "CSV" from Excel on Windows
/// uses. Never throws, so a file that is not text at all reaches the caller,
/// which can say what is wrong with it.
String decodeTextFile(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}
