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
// The logo, after the owner's sketch (bnp-logo-idea.png in the repo root):
// a cricket ball in the Bits N Pixs green, with the company logo's thin
// geometric b and p drawn across it, the p's stem running out of the ball.
// On night surfaces the b is night, a cut-out of the ball, and the p chalk.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';

/// Android density buckets and their pixels per dp.
const _densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};

/// Which layers of the art to draw.
enum _Layer { background, foreground, monochrome, full }

/// The ball: centre and radius on the 108 grid, inside the 72-unit safe zone
/// with room below for the p's stem.
const _ballCenter = Offset(54, 50);
const _ballRadius = 31.0;

/// Stroke of the monoline letters, as thin as still reads at 48 dp.
const _stroke = 4.6;

/// The b: a stem on the left of a round bowl, in the ball's upper left.
Path _letterB() {
  const bowl = Offset(43, 49);
  const r = 11.5;
  return Path()
    ..moveTo(bowl.dx - r, 34)
    ..lineTo(bowl.dx - r, bowl.dy)
    ..addOval(Rect.fromCircle(center: bowl, radius: r));
}

/// The p: a round bowl in the ball's lower right with a long stem that runs
/// out of the ball, as in the sketch.
Path _letterP() {
  const bowl = Offset(68, 53);
  const r = 11.5;
  return Path()
    ..addOval(Rect.fromCircle(center: bowl, radius: r))
    ..moveTo(bowl.dx - r, bowl.dy)
    ..lineTo(bowl.dx - r, 86);
}

Paint _line(Color color, {BlendMode blend = BlendMode.srcOver}) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = _stroke
  ..strokeCap = StrokeCap.round
  ..blendMode = blend;

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
    final ball = Rect.fromCircle(center: _ballCenter, radius: _ballRadius);
    if (layer == _Layer.monochrome) {
      // Themed icons: a white ball with the letters punched out of it, and
      // the p's stem white where it leaves the ball.
      canvas.drawOval(ball, Paint()..color = Colors.white);
      canvas.drawPath(_letterB(), _line(Colors.white, blend: BlendMode.clear));
      canvas.drawPath(_letterP(), _line(Colors.white, blend: BlendMode.clear));
      canvas.save();
      canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(canvasRect), Path()..addOval(ball)));
      canvas.drawPath(_letterP(), _line(Colors.white));
      canvas.restore();
    } else {
      // A lit sphere in the company green: light from the top left, a darker
      // rim at the bottom right.
      canvas.drawOval(
        ball,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.4, -0.45),
            radius: 1.05,
            colors: [Color(0xFF9BD95A), AppColors.brandGreen, Color(0xFF497F1C)],
            stops: [0, 0.55, 1],
          ).createShader(ball),
      );
      // The seam: a great circle seen at a tilt, stitched on both sides, in
      // a deeper green so it shapes the ball without fighting the letters.
      canvas.save();
      canvas.clipPath(Path()..addOval(ball));
      canvas.translate(_ballCenter.dx, _ballCenter.dy);
      canvas.rotate(-38 * math.pi / 180);
      final stitch = Paint()
        ..color = const Color(0xFF2F5C10).withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      for (final side in [-2.6, 2.6]) {
        final row = Path()
          ..addArc(Rect.fromCenter(center: Offset.zero, width: 2 * (_ballRadius + 6), height: 2 * (9 + side)), 0, math.pi);
        for (final metric in row.computeMetrics()) {
          for (var d = 0.0; d < metric.length; d += 4.2) {
            canvas.drawPath(metric.extractPath(d, math.min(d + 1.8, metric.length)), stitch);
          }
        }
      }
      canvas.restore();
      // The letters: the b in night, as if cut out of the ball, and the p in
      // chalk, its stem running down out of the ball onto the night.
      canvas.drawPath(_letterB(), _line(AppColors.night));
      canvas.drawPath(_letterP(), _line(const Color(0xFFF6FAF7)));
    }
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

      // The website: the ball alone for the favicon and the header mark
      // (icon-64) and the link preview (logo, tool/build_site_assets.py),
      // and on night with rounded corners for the touch icon (icon-512).
      for (final (name, size) in [('icon-64', 64), ('logo', 512)]) {
        await _write(
          '../site/img/$name.png',
          size,
          (c) => _paint(c, size / 72, _Layer.foreground, crop: const Rect.fromLTWH(18, 18, 72, 72)),
        );
      }
      await _write(
        '../site/img/icon-512.png',
        512,
        (c) => _paint(c, 512 / 72, _Layer.full, crop: const Rect.fromLTWH(18, 18, 72, 72)),
        cornerRadius: 512 * 0.22,
      );

      // Splash: Android 12+ shows a 288 dp icon whose middle 192 dp circle is
      // visible, which is exactly the safe zone scaled up. One xxxhdpi image.
      const splash = 288 * 4;
      await _write('drawable-xxxhdpi/splash_icon.png', splash, (c) => _paint(c, splash / 108, _Layer.foreground));
    });
  });
}
