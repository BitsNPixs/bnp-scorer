import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The BNP Scorer logo, after the owner's sketch: a cricket ball in the
/// BitsNPixs green, with the company logo's thin geometric b and p drawn
/// across it, the p's stem running out of the ball. On night surfaces the b
/// is night, a cut-out of the ball, and the p chalk.
///
/// The art is on a 108-unit canvas, Android's adaptive-icon grid, and keeps
/// everything that matters inside the central 72-unit safe zone
/// ([logoSafeZone]). [LogoMark] shows the ball in the app;
/// `tool/generate_app_icon_test.dart` writes the icon, splash and website
/// files from the same [paintLogo].

/// Which parts to draw; Android's adaptive icon wants them as separate images.
enum LogoLayer { background, foreground, monochrome, full }

/// Side of the drawing grid.
const logoCanvas = 108.0;

/// The part of the grid the mark stays inside.
const logoSafeZone = Rect.fromLTWH(18, 18, 72, 72);

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

void paintLogo(Canvas canvas, double unit, LogoLayer layer, {Rect? crop}) {
  canvas.save();
  if (crop != null) canvas.translate(-crop.left * unit, -crop.top * unit);
  canvas.scale(unit);
  const canvasRect = Rect.fromLTWH(0, 0, logoCanvas, logoCanvas);

  if (layer == LogoLayer.background || layer == LogoLayer.full) {
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

  if (layer != LogoLayer.background) {
    final ball = Rect.fromCircle(center: _ballCenter, radius: _ballRadius);
    if (layer == LogoLayer.monochrome) {
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

/// The ball alone, [size] wide, for the app's own headers.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: const _LogoPainter()),
  );
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  void paint(Canvas canvas, Size size) =>
      paintLogo(canvas, size.width / logoSafeZone.width, LogoLayer.foreground, crop: logoSafeZone);

  @override
  bool shouldRepaint(_LogoPainter old) => false;
}
