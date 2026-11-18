import 'dart:io';
import 'dart:typed_data';

import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';
const _densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

/// Width and height from a PNG's header.
(int, int) _pngSize(String path) {
  final bytes = File(path.startsWith('../') ? path : '$_res/$path').readAsBytesSync();
  expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10], reason: '$path is not a PNG');
  final header = ByteData.sublistView(bytes, 16, 24);
  return (header.getUint32(0), header.getUint32(4));
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('app icon', () {
    test('every density has the legacy icon and the three adaptive layers, at the right size', () {
      for (final MapEntry(key: bucket, value: px) in _densities.entries) {
        final legacy = (48 * px).round();
        expect(_pngSize('mipmap-$bucket/ic_launcher.png'), (legacy, legacy), reason: bucket);
        final layer = (108 * px).round();
        for (final name in ['ic_launcher_background', 'ic_launcher_foreground', 'ic_launcher_monochrome']) {
          expect(_pngSize('mipmap-$bucket/$name.png'), (layer, layer), reason: '$bucket $name');
        }
      }
    });

    test('the website gets the same mark as its favicon and touch icon', () {
      for (final size in [64, 512]) {
        expect(_pngSize('../site/img/icon-$size.png'), (size, size), reason: 'icon-$size');
      }
      for (final page in ['index', 'privacy']) {
        final html = _read('../site/$page.html');
        expect(html, contains('<link rel="icon" href="img/icon-64.png"'), reason: page);
        expect(html, contains('<link rel="apple-touch-icon" href="img/icon-512.png"'), reason: page);
        expect(html, contains('<img class="mark" src="img/icon-64.png"'), reason: page);
      }
    });

    test('the manifest uses the adaptive icon, which names all three layers', () {
      expect(_read('android/app/src/main/AndroidManifest.xml'), contains('android:icon="@mipmap/ic_launcher"'));
      final adaptive = _read('$_res/mipmap-anydpi-v26/ic_launcher.xml');
      for (final layer in ['background', 'foreground', 'monochrome']) {
        expect(adaptive, contains('android:drawable="@mipmap/ic_launcher_$layer"'), reason: layer);
      }
    });
  });

  group('splash', () {
    test('the splash image is the 288 dp size Android 12 expects', () {
      expect(_pngSize('drawable-xxxhdpi/splash_icon.png'), (288 * 4, 288 * 4));
    });

    test('its background is the app night colour', () {
      final hex = AppColors.night.toARGB32().toRadixString(16).substring(2).toUpperCase();
      expect(_read('$_res/values/colors.xml'), contains('<color name="splash_background">#$hex</color>'));
    });

    test('every launch screen shows the mark on night, in light and dark', () {
      for (final path in ['drawable/launch_background.xml', 'drawable-v21/launch_background.xml']) {
        final xml = _read('$_res/$path');
        expect(xml, contains('@color/splash_background'), reason: path);
        expect(xml, contains('@drawable/splash_icon'), reason: path);
      }
      for (final path in ['values-v31/styles.xml', 'values-night-v31/styles.xml']) {
        final xml = _read('$_res/$path');
        expect(xml, contains('android:windowSplashScreenBackground">@color/splash_background'), reason: path);
        expect(xml, contains('android:windowSplashScreenAnimatedIcon">@drawable/splash_icon'), reason: path);
        expect(xml, contains('<style name="NormalTheme"'), reason: '$path must keep NormalTheme');
      }
    });
  });
}
