// Draws the BNP Scorer logo as the app icon, the splash mark and the
// website's icons, and writes them into the Android project and site/img.
// Not part of the test suite (it lives outside test/). Regenerate after
// changing the art with:
//
//   cd app && flutter test tool/generate_app_icon_test.dart
//
// The art is on a 108-unit canvas, Android's adaptive-icon grid, and keeps
// everything that matters inside the central 72-unit safe zone.
//
// The logo: "bnp" in lowercase, as the Bits N Pixs logo writes its name, with
// the company's green n between a light grey b and a chalk p (the logo's two
// greys, lifted for a night background), over a red cricket-ball seam.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';
const _family = 'BnpIconFace';

/// Android density buckets and their pixels per dp.
const _densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

/// Which layers of the art to draw.
enum _Layer { background, foreground, monochrome, full }

void _paint(Canvas canvas, double unit, _Layer layer, {Rect? crop}) {
  canvas.save();
  if (crop != null) canvas.translate(-crop.left * unit, -crop.top * unit);
  canvas.scale(unit);
  const canvasRect = Rect.fromLTWH(0, 0, 108, 108);

  if (layer == _Layer.background || layer == _Layer.full) {
    canvas.drawRect(
      canvasRect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.7,
          colors: [AppColors.nightRaised, AppColors.night],
        ).createShader(canvasRect),
    );
  }

  if (layer != _Layer.background) {
    final mono = layer == _Layer.monochrome;
    final seamColor = mono ? Colors.white : AppColors.wicket;
    // The ball's seam: an arc of a big ball below the letters, tilted up to
    // the right like a swinging delivery, with stitches on both sides.
    canvas.save();
    canvas.translate(54, 83);
    canvas.rotate(-7 * math.pi / 180);
    final ball = Rect.fromCircle(center: const Offset(0, -96), radius: 96);
    const sweep = 0.42; // radians each side of straight down
    canvas.drawArc(
      ball,
      math.pi / 2 - sweep,
      2 * sweep,
      false,
      Paint()
        ..color = seamColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    final stitch = Paint()
      ..color = seamColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final side in [-4.0, 4.0]) {
      final row = Path()..addArc(ball.inflate(side), math.pi / 2 - sweep * 0.94, 2 * sweep * 0.94);
      for (final metric in row.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 4.5) {
          canvas.drawPath(metric.extractPath(d, math.min(d + 1.6, metric.length)), stitch);
        }
      }
    }
    canvas.restore();

    // "bnp", lowercase like the Bits N Pixs logo, with its green n. The b is
    // the logo's lighter grey and the p its charcoal, both lifted for night.
    TextSpan letter(String text, Color color) => TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: _family,
        fontSize: 38,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1,
        color: mono ? Colors.white : color,
      ),
    );
    final letters = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(children: [
        letter('b', const Color(0xFFC9D1CC)),
        letter('n', AppColors.brandGreen),
        letter('p', const Color(0xFFF2F7F4)),
      ]),
    )..layout();
    // Centred on x 54, baseline at y 61.
    final baseline = letters.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    letters.paint(canvas, Offset(54 - letters.width / 2, 61 - baseline));
  }
  canvas.restore();
}

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
      final font = File('${AppFonts.assetFolder}/Inter-ExtraBold.ttf').readAsBytesSync();
      await (FontLoader(_family)..addFont(Future.value(ByteData.sublistView(font)))).load();

      for (final MapEntry(key: bucket, value: px) in _densities.entries) {
        // Adaptive layers: 108 dp each.
        final layerSize = (108 * px).round();
        for (final (name, layer) in [
          ('ic_launcher_background', _Layer.background),
          ('ic_launcher_foreground', _Layer.foreground),
          ('ic_launcher_monochrome', _Layer.monochrome),
        ]) {
          await _write('mipmap-$bucket/$name.png', layerSize, (c) => _paint(c, px, layer));
        }
        // Older launchers: 48 dp, the safe zone only, with rounded corners.
        final legacy = (48 * px).round();
        await _write(
          'mipmap-$bucket/ic_launcher.png',
          legacy,
          (c) => _paint(c, legacy / 72, _Layer.full, crop: const Rect.fromLTWH(18, 18, 72, 72)),
          cornerRadius: legacy * 0.22,
        );
      }

      // The website: a favicon and a touch icon, the same mark with rounded
      // corners, which the link preview (tool/build_site_assets.py) reuses.
      for (final size in [64, 512]) {
        await _write(
          '../site/img/icon-$size.png',
          size,
          (c) => _paint(c, size / 72, _Layer.full, crop: const Rect.fromLTWH(18, 18, 72, 72)),
          cornerRadius: size * 0.22,
        );
      }

      // Splash: Android 12+ shows a 288 dp icon whose middle 192 dp circle is
      // visible, which is exactly the safe zone scaled up. One xxxhdpi image.
      const splash = 288 * 4;
      await _write('drawable-xxxhdpi/splash_icon.png', splash, (c) => _paint(c, splash / 108, _Layer.foreground));
    });
  });
}
