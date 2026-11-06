import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../ui/format.dart';
import '../widgets/avatars.dart';
import '../widgets/stat_widgets.dart';
import 'player_stats_screen.dart';
import 'team_stats_screen.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stats'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Teams'), Tab(text: 'Batting'), Tab(text: 'Bowling')],
          ),
        ),
        body: stats.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Could not load stats.\n$error', textAlign: TextAlign.center)),
          data: (book) => book.isEmpty
              ? const StatsEmpty(message: 'Stats appear here once a match has finished.')
              : TabBarView(
                  children: [
                    _TeamsTab(book: book),
                    _BattingTab(book: book),
                    _BowlingTab(book: book),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RankedList extends StatelessWidget {
  const _RankedList({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => rows[i],
      );
}

void openPlayer(BuildContext context, String playerId) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerStatsScreen(playerId: playerId)),
    );

class _TeamsTab extends StatelessWidget {
  const _TeamsTab({required this.book});

  final StatsBook book;

  @override
  Widget build(BuildContext context) => _RankedList(
        rows: [
          for (var i = 0; i < book.teams.length; i++)
            _teamRow(context, i + 1, book.teams[i]),
        ],
      );

  Widget _teamRow(BuildContext context, int rank, TeamStats team) => LeaderRow(
        rank: rank,
        leading: TeamBadge(name: team.name, size: 36),
        title: team.name,
        subtitle: 'P ${team.played} · W ${team.won} · L ${team.lost} · '
            'NRR ${signedDecimal(team.netRunRate)}',
        value: '${team.points}',
        valueLabel: 'pts',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => TeamStatsScreen(teamId: team.teamId)),
        ),
      );
}

/// The ranked batting line, shared with the team screen.
LeaderRow battingRow(BuildContext context, int rank, PlayerStats player) => LeaderRow(
      rank: rank,
      leading: PlayerAvatar(name: player.name),
      title: player.name,
      subtitle: '${player.teamName} · HS ${highScoreText(player.batting.high)} · '
          'SR ${decimal(player.batting.strikeRate, 1)}',
      value: '${player.batting.runs}',
      valueLabel: 'runs',
      onTap: () => openPlayer(context, player.playerId),
    );

/// The ranked bowling line, shared with the team screen.
LeaderRow bowlingRow(BuildContext context, int rank, PlayerStats player) => LeaderRow(
      rank: rank,
      leading: PlayerAvatar(name: player.name),
      title: player.name,
      subtitle: '${player.teamName} · BB ${bestBowlingText(player.bowling.best)} · '
          'Econ ${decimal(player.bowling.economy)}',
      value: '${player.bowling.wickets}',
      valueLabel: 'wkts',
      onTap: () => openPlayer(context, player.playerId),
    );

class _BattingTab extends StatelessWidget {
  const _BattingTab({required this.book});

  final StatsBook book;

  @override
  Widget build(BuildContext context) {
    final batters = book.batters;
    return _RankedList(
      rows: [
        for (var i = 0; i < batters.length; i++) battingRow(context, i + 1, batters[i]),
      ],
    );
  }
}

class _BowlingTab extends StatelessWidget {
  const _BowlingTab({required this.book});

  final StatsBook book;

  @override
  Widget build(BuildContext context) {
    final bowlers = book.bowlers;
    return _RankedList(
      rows: [
        for (var i = 0; i < bowlers.length; i++) bowlingRow(context, i + 1, bowlers[i]),
      ],
    );
  }
}
