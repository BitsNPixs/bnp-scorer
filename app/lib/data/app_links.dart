import 'dart:async';

import 'package:flutter/services.dart';

import 'cloud_teams.dart';

/// Links that open the app: a team invite from the website's join page.
/// Behind a boundary so screens can be tested without the platform.
abstract interface class AppLinks {
  /// The link the app was opened with, once; null when opened normally.
  Future<Uri?> initialLink();

  /// Links that arrive while the app is open.
  Stream<Uri> get links;
}

class PlatformAppLinks implements AppLinks {
  PlatformAppLinks() {
    _channel.setMethodCallHandler((call) async {
      final link = call.arguments;
      if (call.method == 'link' && link is String) {
        final uri = Uri.tryParse(link);
        if (uri != null) _links.add(uri);
      }
    });
  }

  static const _channel = MethodChannel('com.bitsnpixs.bnp_scorer/links');
  final _links = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> initialLink() async {
    try {
      final link = await _channel.invokeMethod<String>('initialLink');
      return link == null ? null : Uri.tryParse(link);
    } on MissingPluginException {
      return null; // no bridge on this platform (iOS for now)
    }
  }

  @override
  Stream<Uri> get links => _links.stream;
}

/// The join code in an invite link (`bnpscorer://join?code=ABC234`), or null
/// for any other link.
String? joinCodeFromLink(Uri link) {
  if (link.scheme != 'bnpscorer' || link.host != 'join') return null;
  final code = link.queryParameters['code'];
  return code == null ? null : normalizeJoinCode(code);
}
