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
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stats'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Teams'),
              Tab(text: 'Batting'),
              Tab(text: 'Bowling'),
              Tab(text: 'MVP'),
              Tab(text: 'Boundaries'),
            ],
          ),
        ),
        body: stats.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Could not load stats.\n$error', textAlign: TextAlign.center)),
          data: (book) => book.isEmpty
              ? const StatsEmpty(message: 'Stats appear here once a match has finished.')
              : TabBarView(
                  children: [
                    TeamsTab(teams: book.teams),
                    BattingTab(book: book),
                    BowlingTab(book: book),
                    MvpTab(book: book),
                    BoundariesTab(book: book),
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

class TeamsTab extends StatelessWidget {
  const TeamsTab({super.key, required this.teams});

  final List<TeamStats> teams;

  @override
  Widget build(BuildContext context) => _RankedList(
        rows: [
          for (var i = 0; i < teams.length; i++) teamRow(context, i + 1, teams[i]),
        ],
      );
}

/// The ranked table line, shared with tournament tables.
LeaderRow teamRow(BuildContext context, int rank, TeamStats team) => LeaderRow(
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

class BattingTab extends StatelessWidget {
  const BattingTab({super.key, required this.book});

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

class MvpTab extends StatelessWidget {
  const MvpTab({super.key, required this.book});

  final StatsBook book;

  @override
  Widget build(BuildContext context) {
    final players = book.mvp;
    return _RankedList(
      rows: [
        for (var i = 0; i < players.length; i++)
          LeaderRow(
            rank: i + 1,
            leading: PlayerAvatar(name: players[i].name),
            title: players[i].name,
            subtitle: '${players[i].teamName} · '
                '${players[i].playerOfMatchAwards} Player of the Match',
            value: '${players[i].mvpPoints}',
            valueLabel: 'pts',
            onTap: () => openPlayer(context, players[i].playerId),
          ),
      ],
    );
  }
}

class BoundariesTab extends StatelessWidget {
  const BoundariesTab({super.key, required this.book});

  final StatsBook book;

  @override
  Widget build(BuildContext context) {
    final hitters = book.boundaryHitters;
    if (hitters.isEmpty) return const StatsEmpty(message: 'No boundaries hit yet.');
    return _RankedList(
      rows: [
        for (var i = 0; i < hitters.length; i++)
          LeaderRow(
            rank: i + 1,
            leading: PlayerAvatar(name: hitters[i].name),
            title: hitters[i].name,
            subtitle: '${hitters[i].teamName} · 4s ${hitters[i].batting.fours} · '
                '6s ${hitters[i].batting.sixes}',
            value: '${hitters[i].batting.fours + hitters[i].batting.sixes}',
            valueLabel: 'hits',
            onTap: () => openPlayer(context, hitters[i].playerId),
          ),
      ],
    );
  }
}

class BowlingTab extends StatelessWidget {
  const BowlingTab({super.key, required this.book});

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
