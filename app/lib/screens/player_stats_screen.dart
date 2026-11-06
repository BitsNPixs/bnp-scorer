import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../ui/format.dart';
import '../widgets/avatars.dart';
import '../widgets/stat_widgets.dart';
import '../widgets/surface_panel.dart';

class PlayerStatsScreen extends ConsumerWidget {
  const PlayerStatsScreen({super.key, required this.playerId});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(statsProvider).value;
    final player = book?.players.where((p) => p.playerId == playerId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(player?.name ?? 'Player', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: player == null
          ? const StatsEmpty(message: 'No stats for this player yet.')
          : _PlayerStats(player: player),
    );
  }
}

class _PlayerStats extends StatelessWidget {
  const _PlayerStats({required this.player});

  final PlayerStats player;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final batting = player.batting;
    final bowling = player.bowling;
    final fielding = player.fielding;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SurfacePanel(
          child: Row(
            children: [
              PlayerAvatar(name: player.name, radius: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${player.teamName} · ${plural(player.matches, 'match')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StatGrid(
          title: 'Batting',
          stats: [
            ('Runs', '${batting.runs}'),
            ('Innings', '${batting.innings}'),
            ('Not outs', '${batting.notOuts}'),
            ('Highest', highScoreText(batting.high)),
            ('Average', decimal(batting.average)),
            ('Strike rate', decimal(batting.strikeRate)),
            ('Balls', '${batting.balls}'),
            ('Fours', '${batting.fours}'),
            ('Sixes', '${batting.sixes}'),
            ('Fifties', '${batting.fifties}'),
            ('Hundreds', '${batting.hundreds}'),
          ],
        ),
        const SizedBox(height: 12),
        StatGrid(
          title: 'Bowling',
          stats: [
            ('Wickets', '${bowling.wickets}'),
            ('Innings', '${bowling.innings}'),
            ('Overs', bowling.oversText),
            ('Runs', '${bowling.runs}'),
            ('Best', bestBowlingText(bowling.best)),
            ('Economy', decimal(bowling.economy)),
            ('Average', decimal(bowling.average)),
            ('Strike rate', decimal(bowling.strikeRate)),
            ('Maidens', '${bowling.maidens}'),
            ('Dot balls', '${bowling.dots}'),
            ('Wides', '${bowling.wides}'),
            ('No-balls', '${bowling.noBalls}'),
          ],
        ),
        const SizedBox(height: 12),
        StatGrid(
          title: 'Fielding',
          stats: [
            ('Catches', '${fielding.catches}'),
            ('Stumpings', '${fielding.stumpings}'),
            ('Run outs', '${fielding.runOuts}'),
          ],
        ),
      ],
    );
  }
}
