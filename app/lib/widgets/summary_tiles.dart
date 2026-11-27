import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:match_view/match_view.dart' show MatchNow;

import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/motion.dart';
import 'surface_panel.dart';

/// Three glassy number tiles: played, live and tournaments.
class SummaryTiles extends ConsumerWidget {
  const SummaryTiles({super.key, required this.matches, required this.tournamentCount});

  final List<MatchSummary> matches;
  final int tournamentCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final finished = matches.where((m) => m.state.isCompleted).length;
    // A match left unfinished hours ago counts as neither.
    final live = matches.where((m) => nowOf(m, now) == MatchNow.live).length;
    final tiles = [
      (Icons.check_circle_rounded, '$finished', 'Played', AppColors.neonDeep),
      (Icons.sensors_rounded, '$live', 'Live', AppColors.live),
      (Icons.emoji_events_rounded, '$tournamentCount', 'Tournaments', AppColors.four),
    ];
    return Row(
      children: [
        for (final (i, (icon, value, label, color)) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: EntranceFade(
              index: i + 1,
              child: _SummaryTile(icon: icon, value: value, label: label, color: color),
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.icon, required this.value, required this.label, required this.color});

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: cardShape(context, radius: 20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, maxLines: 1, style: scoreStyle(22, color: scheme.onSurface)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
