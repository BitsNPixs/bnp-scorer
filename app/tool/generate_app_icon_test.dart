// Draws the BNP Scorer app icon and splash and writes them into the Android
// project. Not part of the test suite (it lives outside test/). Regenerate
// after changing the art with:
//
//   cd app && flutter test tool/generate_app_icon_test.dart
//
// The art is on a 108-unit canvas, Android's adaptive-icon grid, and keeps
// everything that matters inside the central 72-unit safe zone.
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
    final seam = Path()
      ..moveTo(28, 70)
      ..quadraticBezierTo(54, 82, 80, 66);
    canvas.drawPath(
      seam,
      Paint()
        ..color = seamColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    // The stitches: short dashes along a second curve.
    final stitches = Path()
      ..moveTo(30, 74)
      ..quadraticBezierTo(54, 85, 80, 70);
    final stitch = Paint()
      ..color = seamColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final metric in stitches.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 4.5) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 1.5, metric.length)), stitch);
      }
    }

    final letters = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: 'BNP',
        style: TextStyle(
          fontFamily: _family,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          letterSpacing: 0.5,
          height: 1,
          foreground: Paint()
            ..shader = mono
                ? null
                : AppColors.neonGradient.createShader(const Rect.fromLTWH(28, 30, 52, 34))
            ..color = Colors.white,
        ),
      ),
    )..layout();
    // Centred on x 54, baseline at y 63, as in the approved preview.
    final baseline = letters.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    letters.paint(canvas, Offset(54 - letters.width / 2, 63 - baseline));
  }
  canvas.restore();
}

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
  final file = File('$_res/$path')..createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path (${size}px)');
}

void main() {
  testWidgets('generate the app icon and splash', (tester) async {
    await tester.runAsync(() async {
      final font = File('${AppFonts.assetFolder}/BarlowCondensed-BlackItalic.ttf').readAsBytesSync();
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

      // Splash: Android 12+ shows a 288 dp icon whose middle 192 dp circle is
      // visible, which is exactly the safe zone scaled up. One xxxhdpi image.
      const splash = 288 * 4;
      await _write('drawable-xxxhdpi/splash_icon.png', splash, (c) => _paint(c, splash / 108, _Layer.foreground));
    });
  });
}
