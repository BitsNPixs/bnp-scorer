// Draws the BNP Scorer logo as the app icon, the notification icon, the
// splash mark and the website's icons, and writes them into the Android project and site/img.
// Not part of the test suite (it lives outside test/). Regenerate after
// changing the art with:
//
//   cd app && flutter test tool/generate_app_icon_test.dart
//
// The art itself is `paintLogo` in lib/widgets/logo_mark.dart, which the app
// also uses for its headers; this file only picks sizes and layers and writes
// the files.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bnp_scorer/widgets/logo_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';

/// Android density buckets and their pixels per dp.
const _densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

/// Writes a PNG under the Android res folder, or wherever [path] points if it
/// starts with `../`.
Future<void> _write(String path, int size, void Function(Canvas canvas) draw, {double cornerRadius = 0}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (cornerRadius > 0) {
    canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Radius.circular(cornerRadius),
    ));
  }
  draw(canvas);
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path.startsWith('../') ? path : '$_res/$path')..createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path (${size}px)');
}

void main() {
  testWidgets('generate the app icon and splash', (tester) async {
    await tester.runAsync(() async {
      for (final MapEntry(key: bucket, value: px) in _densities.entries) {
        // Adaptive layers: 108 dp each.
        final layerSize = (108 * px).round();
        for (final (name, layer) in [
          ('ic_launcher_background', LogoLayer.background),
          ('ic_launcher_foreground', LogoLayer.foreground),
          ('ic_launcher_monochrome', LogoLayer.monochrome),
        ]) {
          await _write('mipmap-$bucket/$name.png', layerSize, (c) => paintLogo(c, px, layer));
        }
        // Notification icon (match reminders): 24 dp, the white ball with
        // its letters cut out, which Android tints with the brand green.
        final status = (24 * px).round();
        await _write(
          'drawable-$bucket/ic_stat_bnp.png',
          status,
          (c) => paintLogo(c, status / 72, LogoLayer.monochrome, crop: logoSafeZone),
        );
        // Older launchers: 48 dp, the safe zone only, with rounded corners.
        final legacy = (48 * px).round();
        await _write(
          'mipmap-$bucket/ic_launcher.png',
          legacy,
          (c) => paintLogo(c, legacy / 72, LogoLayer.full, crop: logoSafeZone),
          cornerRadius: legacy * 0.22,
        );
      }

      // The website: the ball alone for the favicon and the header mark
      // (icon-64) and the link preview (logo, tool/build_site_assets.py),
      // and on night with rounded corners for the touch icon (icon-512).
      for (final (name, size) in [('icon-64', 64), ('logo', 512)]) {
        await _write(
          '../site/img/$name.png',
          size,
          (c) => paintLogo(c, size / 72, LogoLayer.foreground, crop: logoSafeZone),
        );
      }
      await _write(
        '../site/img/icon-512.png',
        512,
        (c) => paintLogo(c, 512 / 72, LogoLayer.full, crop: logoSafeZone),
        cornerRadius: 512 * 0.22,
      );

      // Splash: Android 12+ shows a 288 dp icon whose middle 192 dp circle is
      // visible, which is exactly the safe zone scaled up. One xxxhdpi image.
      const splash = 288 * 4;
      await _write('drawable-xxxhdpi/splash_icon.png', splash, (c) => paintLogo(c, splash / 108, LogoLayer.foreground));
    });
  });
}
