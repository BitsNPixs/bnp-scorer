import 'dart:math' as math;

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import 'avatars.dart';

/// The hero card: big animated score on a floodlit navy gradient.
class ScoreHeader extends StatelessWidget {
  const ScoreHeader({super.key, required this.state});

  final MatchState state;

  @override
  Widget build(BuildContext context) {
    final inn = state.current;
    final team = state.setup.teamById(inn.battingTeamId);
    final text = Theme.of(context).textTheme;
    const muted = Color(0x99FFFFFF);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -48,
            top: -48,
            child: CustomPaint(size: Size.square(190), painter: _BallSeamPainter()),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TeamBadge(name: team.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            inningsLabel(inn.number),
                            style: text.labelMedium?.copyWith(color: muted),
                          ),
                        ],
                      ),
                    ),
                    if (!state.isCompleted) const LivePill(),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation.drive(
                          Tween(begin: 0.7, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)),
                        ),
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Text(
                        '${inn.runs}',
                        key: ValueKey(inn.runs),
                        style: scoreStyle(64, color: Colors.white),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6, left: 2),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        child: Text(
                          '/${inn.wickets}',
                          key: ValueKey(inn.wickets),
                          style: scoreStyle(36, color: AppColors.lime),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'OVERS',
                          style: text.labelSmall?.copyWith(color: muted, letterSpacing: 1.4),
                        ),
                        const SizedBox(height: 4),
                        Text(inn.oversText, style: scoreStyle(28, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(
                          'of ${inn.maxOversText}',
                          style: text.labelSmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _StatsRow(innings: inn),
                if (inn.target != null && !inn.isComplete) ...[
                  const SizedBox(height: 14),
                  _ChasePill(innings: inn),
                ],
              ],
            ),
          ),
        ],
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
        for (final (label, value) in stats)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0x99FFFFFF),
                        letterSpacing: 1.2,
                      ),
                ),
                const SizedBox(height: 4),
                Text(value, style: scoreStyle(18, color: Colors.white)),
              ],
            ),
          ),
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
          color: AppColors.lime.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.lime.withValues(alpha: 0.4)),
        ),
        child: Text(
          'Need ${plural(innings.runsNeeded!, 'run')} from '
          '${plural(innings.ballsRemaining, 'ball')}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.lime,
                fontWeight: FontWeight.w700,
              ),
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
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

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
      ..color = Colors.white.withValues(alpha: 0.07)
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
