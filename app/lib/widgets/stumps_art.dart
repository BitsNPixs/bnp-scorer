import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/motion.dart';

/// Stumps under floodlight, with a ball that rolls in when it first appears.
class StumpsArt extends StatelessWidget {
  const StumpsArt({super.key});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: reduceMotion(context) ? 1 : 0, end: 1),
    duration: const Duration(milliseconds: 1100),
    curve: Curves.easeOutCubic,
    builder: (context, t, _) => CustomPaint(size: const Size(110, 150), painter: _StumpsPainter(t)),
  );
}

class _StumpsPainter extends CustomPainter {
  const _StumpsPainter(this.roll);

  /// 0 when the ball is off to the right, 1 when it rests by the stumps.
  final double roll;

  @override
  void paint(Canvas canvas, Size size) {
    final ground = size.height - 18;
    final glowRect = Rect.fromCircle(center: Offset(size.width * 0.6, ground), radius: 70);
    canvas.drawCircle(
      glowRect.center,
      70,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.neon.withValues(alpha: 0.30), AppColors.neon.withValues(alpha: 0)],
        ).createShader(glowRect),
    );
    canvas.drawLine(
      Offset(8, ground),
      Offset(size.width, ground),
      Paint()
        ..color = AppColors.neon.withValues(alpha: 0.5)
        ..strokeWidth = 2,
    );

    final stump = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Color(0xFFB9CFC4)],
      ).createShader(Rect.fromLTWH(0, ground - 86, size.width, 86));
    const stumpWidth = 7.0;
    final left = size.width * 0.6 - 18;
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(left + i * 15, ground - 84, stumpWidth, 84), const Radius.circular(3)),
        stump,
      );
    }
    final bail = Paint()..color = Colors.white;
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left - 1, ground - 90, 17, 4), const Radius.circular(2)), bail)
      ..drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(left + 15, ground - 90, 17, 4), const Radius.circular(2)),
        bail,
      );

    const radius = 12.0;
    final ball = Offset(left - 20 + (1 - roll) * 110, ground - radius - 1);
    final ballRect = Rect.fromCircle(center: ball, radius: radius);
    canvas.drawCircle(
      ball,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [Color(0xFFFF6B6B), Color(0xFFB3132B)],
        ).createShader(ballRect),
    );
    canvas
      ..save()
      ..translate(ball.dx, ball.dy)
      ..rotate(-(1 - roll) * math.pi * 4);
    final seam = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas
      ..drawArc(Rect.fromCircle(center: const Offset(-9, 0), radius: 9), -0.9, 1.8, false, seam)
      ..drawArc(Rect.fromCircle(center: const Offset(9, 0), radius: 9), math.pi - 0.9, 1.8, false, seam)
      ..restore();
  }

  @override
  bool shouldRepaint(_StumpsPainter old) => old.roll != roll;
}
