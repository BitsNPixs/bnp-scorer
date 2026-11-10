import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import 'surface_panel.dart';

/// Colour-coded balls of the current over, with empty slots still to come.
class OverStrip extends StatelessWidget {
  const OverStrip({super.key, required this.state});

  final MatchState state;

  @override
  Widget build(BuildContext context) {
    final inn = state.current;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final showingLast = inn.currentOver.isEmpty && inn.completedOvers.isNotEmpty;
    final balls = showingLast ? inn.completedOvers.last : inn.currentOver;
    final legal = balls.where((b) => b.isLegal).length;
    final remaining = showingLast ? 0 : inn.ballsPerOver - legal;
    final bowlerId = inn.bowlerId ?? (showingLast ? inn.lastOverBowlerId : null);
    final overNumber = inn.completedOvers.length + (showingLast ? 0 : 1);

    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SectionLabel(showingLast ? 'Last over' : 'Over $overNumber'),
              const Spacer(),
              if (bowlerId != null)
                Flexible(
                  child: Text(
                    playerName(state.setup, bowlerId),
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < balls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey('${inn.number}-$overNumber-$i'),
                      tween: Tween(begin: 0.3, end: 1),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: BallChip(ball: balls[i]),
                    ),
                  ),
                for (var i = 0; i < remaining; i++)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: _EmptyBall(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BallChip extends StatelessWidget {
  const BallChip({super.key, required this.ball, this.size = 40});

  final BallSummary ball;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (ball.kind) {
      BallKind.dot => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
      BallKind.runs => (scheme.primary, scheme.onPrimary),
      BallKind.four => (AppColors.four, AppColors.night),
      BallKind.six => (AppColors.six, Colors.white),
      BallKind.extra => (AppColors.extra, Colors.white),
      BallKind.wicket => (AppColors.wicket, Colors.white),
    };
    final label = ball.kind == BallKind.dot ? '•' : ball.label;
    return Container(
      constraints: BoxConstraints(minWidth: size),
      height: size,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      // Sized to the label, so a chip in a Wrap does not fill the whole line.
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: scoreStyle(label.length > 3 ? 12 : 15, color: fg),
        ),
      ),
    );
  }
}

class _EmptyBall extends StatelessWidget {
  const _EmptyBall();

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1.5,
          ),
        ),
      );
}
