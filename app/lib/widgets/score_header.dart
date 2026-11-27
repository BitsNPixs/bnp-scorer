import 'dart:math' as math;

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import 'avatars.dart';

/// The hero card: big score on a floodlit pitch, an overs ring that fills as
/// the innings goes, and a burst of colour for every four, six and wicket.
class ScoreHeader extends StatefulWidget {
  const ScoreHeader({super.key, required this.state, this.stopped = false});

  final MatchState state;

  /// Nobody has scored this match for hours (`MatchNow.stopped`): it says
  /// STOPPED where a match in play says LIVE. Only a watcher is told so; the
  /// scorer's own screen is about to change that.
  final bool stopped;

  /// How long a FOUR!, SIX! or WICKET! burst stays on screen.
  static const burstDuration = Duration(milliseconds: 1100);

  @override
  State<ScoreHeader> createState() => _ScoreHeaderState();
}

class _ScoreHeaderState extends State<ScoreHeader> with SingleTickerProviderStateMixin {
  late final _burst = AnimationController(vsync: this, duration: ScoreHeader.burstDuration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() => _burstKind = null);
    });

  /// The ball being celebrated, while the burst plays.
  BallKind? _burstKind;

  static int _ballCount(InningsState inn) =>
      inn.completedOvers.fold<int>(0, (n, over) => n + over.length) + inn.currentOver.length;

  static BallSummary? _lastBall(InningsState inn) => inn.currentOver.isNotEmpty
      ? inn.currentOver.last
      : (inn.completedOvers.isNotEmpty && inn.completedOvers.last.isNotEmpty ? inn.completedOvers.last.last : null);

  @override
  void didUpdateWidget(ScoreHeader old) {
    super.didUpdateWidget(old);
    final before = old.state.current;
    final after = widget.state.current;
    // Only a ball just bowled celebrates: not an undo, a reload or a new innings.
    if (before.number != after.number || _ballCount(after) != _ballCount(before) + 1) return;
    final kind = _lastBall(after)?.kind;
    if (kind != BallKind.four && kind != BallKind.six && kind != BallKind.wicket) return;
    if (reduceMotion(context)) return;
    setState(() => _burstKind = kind);
    _burst.forward(from: 0);
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final inn = state.current;
    final team = state.setup.teamById(inn.battingTeamId);
    final text = Theme.of(context).textTheme;
    const muted = Color(0x99FFFFFF);
    final kind = _burstKind;

    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.neon.withValues(alpha: 0.18)),
        boxShadow: AppColors.glow(AppColors.night, strength: 0.3),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.8, -0.2),
                  radius: 0.9,
                  colors: [AppColors.neon.withValues(alpha: 0.14), AppColors.neon.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          const Positioned(
            left: -60,
            bottom: -70,
            child: CustomPaint(size: Size.square(190), painter: _BallSeamPainter()),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TeamBadge(name: team.name, logoUrl: team.logoUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                          Text(inningsLabel(inn.number), style: text.labelMedium?.copyWith(color: muted)),
                        ],
                      ),
                    ),
                    if (widget.stopped)
                      const StatusTag(label: 'STOPPED', color: muted)
                    else if (!state.isCompleted)
                      const LivePill(),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _RollingNumber(
                              value: '${inn.runs}',
                              style: scoreStyle(76, color: Colors.white, weight: FontWeight.w800),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6, left: 2),
                              child: _RollingNumber(
                                value: '/${inn.wickets}',
                                style: scoreStyle(40, color: AppColors.neon),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _OversRing(innings: inn),
                  ],
                ),
                const SizedBox(height: 16),
                _StatsRow(innings: inn),
                if (inn.target != null && !inn.isComplete) ...[const SizedBox(height: 12), _ChasePill(innings: inn)],
              ],
            ),
          ),
          if (kind != null)
            Positioned.fill(
              child: _Burst(kind: kind, progress: _burst),
            ),
        ],
      ),
    );

    // A wicket shakes the scoreboard.
    return AnimatedBuilder(
      animation: _burst,
      child: card,
      builder: (context, child) {
        if (kind != BallKind.wicket) return child!;
        final t = _burst.value.clamp(0.0, 0.4) / 0.4;
        return Transform.translate(offset: Offset(math.sin(t * math.pi * 6) * 7 * (1 - t), 0), child: child);
      },
    );
  }
}

/// A number that rolls up into place when it changes, like a scoreboard.
class _RollingNumber extends StatelessWidget {
  const _RollingNumber({required this.value, required this.style});

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 280),
    switchInCurve: Curves.easeOutBack,
    switchOutCurve: Curves.easeIn,
    transitionBuilder: (child, animation) {
      final incoming = child.key == ValueKey(value);
      final slide = Tween(
        begin: incoming ? const Offset(0, 0.6) : const Offset(0, -0.6),
        end: Offset.zero,
      ).animate(animation);
      return ClipRect(
        child: SlideTransition(
          position: slide,
          child: FadeTransition(opacity: animation, child: child),
        ),
      );
    },
    child: Text(value, key: ValueKey(value), style: style),
  );
}

/// Overs bowled as a neon ring, like a dial filling up through the innings.
class _OversRing extends StatelessWidget {
  const _OversRing({required this.innings});

  final InningsState innings;

  static const _size = 100.0;

  @override
  Widget build(BuildContext context) {
    final inn = innings;
    final progress = inn.maxBalls == 0 ? 0.0 : (inn.legalBalls / inn.maxBalls).clamp(0.0, 1.0);
    const muted = Color(0x99FFFFFF);
    return SizedBox.square(
      dimension: _size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress),
        duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => CustomPaint(painter: _RingPainter(value), child: child),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'OVERS',
                    style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.4, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(inn.oversText, style: scoreStyle(28, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('of ${inn.maxOversText}', style: const TextStyle(color: muted, fontSize: 10)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress);

  final double progress;

  static const _stroke = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - _stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke,
    );
    if (progress <= 0) return;
    const start = -math.pi / 2;
    final sweep = math.pi * 2 * progress;
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          transform: const GradientRotation(start),
          colors: const [AppColors.neonDeep, AppColors.neon, Color(0xFFB8FFE0)],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _stroke,
    );
    final knob = center + Offset(math.cos(start + sweep), math.sin(start + sweep)) * radius;
    canvas
      ..drawCircle(knob, 9, Paint()..color = AppColors.neon.withValues(alpha: 0.30))
      ..drawCircle(knob, 5.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// FOUR!, SIX! or WICKET! springing out over the scoreboard.
class _Burst extends StatelessWidget {
  const _Burst({required this.kind, required this.progress});

  final BallKind kind;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      BallKind.four => ('FOUR!', AppColors.four),
      BallKind.six => ('SIX!', AppColors.six),
      _ => ('WICKET!', AppColors.wicket),
    };
    final scale = CurvedAnimation(
      parent: progress,
      curve: const Interval(0, 0.5, curve: Curves.elasticOut),
    );
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, child) {
          final t = progress.value;
          // In fast, hold, then fade over the last third.
          final opacity = t < 0.66 ? 1.0 : (1 - (t - 0.66) / 0.34).clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.4 + t * 0.8,
                  colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0)],
                ),
              ),
              child: Center(
                child: Transform.rotate(
                  angle: -0.08,
                  child: Transform.scale(scale: 0.3 + scale.value * 0.7, child: child),
                ),
              ),
            ),
          );
        },
        child: Text(
          label,
          style: AppFonts.display(
            TextStyle(
              fontSize: 64,
              height: 1,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: Colors.white,
              letterSpacing: 1,
              shadows: [
                Shadow(color: color, blurRadius: 24),
                Shadow(color: color, blurRadius: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.innings});

  final InningsState innings;

  @override
  Widget build(BuildContext context) {
    final inn = innings;
    final stats = <(String, String)>[
      ('CRR', inn.runRate.toStringAsFixed(2)),
      if (inn.target != null) ...[
        ('TARGET', '${inn.target}'),
        ('RRR', inn.requiredRunRate?.toStringAsFixed(2) ?? '—'),
      ] else
        ('PROJECTED', '${(inn.runRate * inn.maxBalls / inn.ballsPerOver).round()}'),
      ('EXTRAS', '${inn.extras.total}'),
    ];
    return Row(
      children: [
        for (final (i, (label, value)) in stats.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: const Color(0x99FFFFFF), letterSpacing: 1.2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, maxLines: 1, style: scoreStyle(20, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChasePill extends StatelessWidget {
  const _ChasePill({required this.innings});

  final InningsState innings;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.neon.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.neon.withValues(alpha: 0.4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.flag_rounded, size: 18, color: AppColors.neon),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Need ${plural(innings.runsNeeded!, 'run')} from '
            '${plural(innings.ballsRemaining, 'ball')}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.neon, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

/// A small rounded status word: RESULT, STOPPED.
class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2),
    ),
  );
}

/// Pulsing "LIVE" badge.
class LivePill extends StatefulWidget {
  const LivePill({super.key, this.onDark = true});

  final bool onDark;

  @override
  State<LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<LivePill> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.live.withValues(alpha: widget.onDark ? 0.18 : 0.12),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AppColors.live.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween(begin: 0.25, end: 1.0).animate(_controller),
          child: const CircleAvatar(radius: 4, backgroundColor: AppColors.live),
        ),
        const SizedBox(width: 6),
        Text(
          'LIVE',
          style: TextStyle(
            color: widget.onDark ? Colors.white : AppColors.live,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 1.2,
          ),
        ),
      ],
    ),
  );
}

/// A faint cricket ball with its seam, as a background flourish.
class _BallSeamPainter extends CustomPainter {
  const _BallSeamPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius - 18, paint..strokeWidth = 1);
    final seam = Rect.fromCircle(center: center, radius: radius * 0.72);
    paint.strokeWidth = 3;
    canvas.drawArc(seam.shift(Offset(-radius * 0.55, 0)), -math.pi / 3, math.pi * 2 / 3, false, paint);
    canvas.drawArc(seam.shift(Offset(radius * 0.55, 0)), math.pi * 2 / 3, math.pi * 2 / 3, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
