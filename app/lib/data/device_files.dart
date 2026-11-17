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
    return utf8.decode(await files.first.readAsBytes());
  }
}
