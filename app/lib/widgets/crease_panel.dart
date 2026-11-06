import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import 'avatars.dart';
import 'surface_panel.dart';

/// Who is batting, who is bowling, and the current partnership.
class CreasePanel extends StatelessWidget {
  const CreasePanel({super.key, required this.state, this.onSwapStrike});

  final MatchState state;
  final VoidCallback? onSwapStrike;

  @override
  Widget build(BuildContext context) {
    final inn = state.current;
    final setup = state.setup;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final bowlerId = inn.bowlerId;
    final bowler = inn.bowler(bowlerId);
    final lone = inn.strikerId != null &&
        inn.nonStrikerId == null &&
        inn.availableBatterIds.isEmpty;

    return SurfacePanel(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const SectionLabel('At the crease'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Partnership ${inn.partnershipRuns} (${inn.partnershipBalls})',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                if (onSwapStrike != null)
                  IconButton(
                    tooltip: 'Swap strike',
                    visualDensity: VisualDensity.compact,
                    onPressed: onSwapStrike,
                    icon: const Icon(Icons.swap_vert_rounded),
                  ),
              ],
            ),
          ),
          _BatterRow(setup: setup, innings: inn, playerId: inn.strikerId, onStrike: true),
          if (!lone)
            _BatterRow(setup: setup, innings: inn, playerId: inn.nonStrikerId, onStrike: false)
          else
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Last man standing', style: text.labelMedium),
            ),
          const Divider(height: 20, indent: 8, endIndent: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Icons.sports_baseball_rounded, size: 20, color: AppColors.wicket.withValues(alpha: 0.9)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    bowlerId == null ? 'Bowler to be chosen' : playerName(setup, bowlerId),
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (bowler != null) ...[
                  Flexible(
                    child: Text(
                      figures(bowler, inn.ballsPerOver),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: scoreStyle(16, color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Econ ${bowler.economy(inn.ballsPerOver).toStringAsFixed(1)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatterRow extends StatelessWidget {
  const _BatterRow({
    required this.setup,
    required this.innings,
    required this.playerId,
    required this.onStrike,
  });

  final MatchSetup setup;
  final InningsState innings;
  final String? playerId;
  final bool onStrike;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final id = playerId;
    final score = innings.batter(id);

    if (id == null || score == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.hourglass_empty_rounded, color: scheme.onSurfaceVariant, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Waiting for the next batter',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final name = playerName(setup, id);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: onStrike ? scheme.primary.withValues(alpha: 0.07) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          PlayerAvatar(name: name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          fontWeight: onStrike ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (onStrike) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.sports_cricket_rounded, size: 16, color: scheme.primary),
                    ],
                  ],
                ),
                Text(
                  '4s ${score.fours} · 6s ${score.sixes} · SR ${score.strikeRate.toStringAsFixed(1)}',
                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text('${score.runs}', style: scoreStyle(26, color: scheme.onSurface)),
          Text(
            ' (${score.balls})',
            style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
