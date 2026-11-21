import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'accounts.dart';

/// The photos Worker (`cloud/photos-worker`): player photos and team logos
/// in Cloudflare R2. Empty turns photos off, as in builds before it is
/// deployed.
const photosBaseUrl = String.fromEnvironment('BNP_PHOTOS_URL');

/// Thrown when a photo cannot be uploaded or removed. The message is written
/// for players.
class PhotoException implements Exception {
  const PhotoException(this.message);

  final String message;

  @override
  String toString() => 'PhotoException: $message';
}

/// Uploads and removes the signed-in player's photos. Each account can only
/// write its own (the Worker checks the sign-in token).
abstract interface class PhotoStore {
  /// Replaces the player's photo; returns its new address.
  Future<String> uploadAvatar(Uint8List image);

  Future<void> removeAvatar();
}

class HttpPhotoStore implements PhotoStore {
  HttpPhotoStore(this._accounts, {String baseUrl = photosBaseUrl, HttpClient? client})
      : _base = Uri.parse(baseUrl),
        _client = client ?? HttpClient();

  final Accounts _accounts;
  final Uri _base;
  final HttpClient _client;

  static const _timeout = Duration(seconds: 20);

  @override
  Future<String> uploadAvatar(Uint8List image) async {
    final body = await _send('PUT', '/v1/avatar', image);
    final url = body['url'];
    if (url is! String) throw const PhotoException('The photo did not save. Try again.');
    return url;
  }

  @override
  Future<void> removeAvatar() async => _send('DELETE', '/v1/avatar', null);

  Future<Map<String, Object?>> _send(String method, String path, Uint8List? image) async {
    final token = await _accounts.idToken();
    if (token == null) throw const PhotoException('Sign in first.');
    try {
      final request = await _client.openUrl(method, _base.resolve(path)).timeout(_timeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (image != null) {
        request.headers.contentType = ContentType('application', 'octet-stream');
        request.contentLength = image.length;
        request.add(image);
      }
      final response = await request.close().timeout(_timeout);
      final text = await response.transform(utf8.decoder).join().timeout(_timeout);
      final decoded = text.isEmpty ? <String, Object?>{} : jsonDecode(text);
      final body = decoded is Map<String, Object?> ? decoded : <String, Object?>{};
      if (response.statusCode != 200) {
        throw PhotoException(body['error'] as String? ?? 'The photo did not save (${response.statusCode}).');
      }
      return body;
    } on SocketException {
      throw const PhotoException('No internet. Connect and try again.');
    } on HttpException {
      throw const PhotoException('No internet. Connect and try again.');
    } on FormatException {
      throw const PhotoException('The photo service answered oddly. Try again.');
    } on Exception catch (e) {
      if (e is PhotoException) rethrow;
      throw const PhotoException('The photo service did not answer. Try again.');
    }
  }
}

/// The phone's photo picker, behind a boundary so screens can be tested
/// without it.
abstract interface class DevicePhotos {
  /// A photo the player picks, shrunk to at most 512 px, or null when they
  /// back out.
  Future<Uint8List?> pickPhoto();
}

class PlatformDevicePhotos implements DevicePhotos {
  const PlatformDevicePhotos();

  @override
  Future<Uint8List?> pickPhoto() async {
    // Shrunk on the phone: about 50 KB, so uploads are quick and storage stays tiny.
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }
}
