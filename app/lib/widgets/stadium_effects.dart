import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A soft neon glow at the top of the screen, like floodlights over a ground.
class Floodlight extends StatelessWidget {
  const Floodlight({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.9, -1.1),
          radius: 1.1,
          colors: [
            AppColors.neon.withValues(alpha: isLight ? 0.16 : 0.12),
            AppColors.neon.withValues(alpha: 0),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// One shower of confetti in the scoring colours, played once when it
/// appears. Paints nothing once it has finished.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  static const duration = Duration(milliseconds: 2200);

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: ConfettiBurst.duration)..forward();

  // Seeded, so every burst falls the same way and tests are repeatable.
  final _pieces = _Piece.scatter(math.Random(7), 70);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _ConfettiPainter(_controller, _pieces),
            size: Size.infinite,
          ),
        ),
      );
}

class _Piece {
  const _Piece(this.x, this.delay, this.fall, this.sway, this.spin, this.size, this.color);

  /// Start across the width, 0 to 1.
  final double x;

  /// Fraction of the burst before this piece appears.
  final double delay;

  /// Screen heights fallen over the whole burst.
  final double fall;
  final double sway;
  final double spin;
  final double size;
  final Color color;

  static const _colors = [
    AppColors.neon,
    AppColors.four,
    AppColors.six,
    AppColors.wicket,
    AppColors.extra,
    Colors.white,
  ];

  static List<_Piece> scatter(math.Random random, int count) => [
        for (var i = 0; i < count; i++)
          _Piece(
            random.nextDouble(),
            random.nextDouble() * 0.25,
            0.9 + random.nextDouble() * 0.6,
            (random.nextDouble() - 0.5) * 0.12,
            (random.nextDouble() - 0.5) * 14,
            6 + random.nextDouble() * 6,
            _colors[i % _colors.length],
          ),
      ];
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress, this.pieces) : super(repaint: progress);

  final Animation<double> progress;
  final List<_Piece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t == 0 || t == 1) return;
    final paint = Paint();
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local == 0) continue;
      final opacity = local < 0.75 ? 1.0 : (1 - (local - 0.75) / 0.25);
      final dx = (p.x + math.sin(local * math.pi * 3 + p.x * 10) * p.sway) * size.width;
      final dy = (-0.1 + Curves.easeIn.transform(local) * p.fall) * size.height;
      paint.color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas
        ..save()
        ..translate(dx, dy)
        ..rotate(local * p.spin)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
            const Radius.circular(1.5),
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
