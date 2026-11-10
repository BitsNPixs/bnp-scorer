import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/format.dart';
import '../widgets/stat_widgets.dart';
import '../widgets/surface_panel.dart';
import 'stats_screen.dart';

const _topPlayers = 3;

class TeamStatsScreen extends ConsumerWidget {
  const TeamStatsScreen({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(statsProvider).value;
    final team = book?.teams.where((t) => t.teamId == teamId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(team?.name ?? 'Team', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: book == null || team == null
          ? const StatsEmpty(message: 'No stats for this team yet.')
          : _TeamStats(book: book, team: team),
    );
  }
}

class _TeamStats extends StatelessWidget {
  const _TeamStats({required this.book, required this.team});

  final StatsBook book;
  final TeamStats team;

  @override
  Widget build(BuildContext context) {
    final batters = book.batters.where((p) => p.teamId == team.teamId).take(_topPlayers).toList();
    final bowlers = book.bowlers.where((p) => p.teamId == team.teamId).take(_topPlayers).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StatGrid(
          title: 'All matches',
          stats: [
            ('Played', '${team.played}'),
            ('Won', '${team.won}'),
            ('Lost', '${team.lost}'),
            ('Tied', '${team.tied}'),
            ('No result', '${team.noResults}'),
            ('Points', '${team.points}'),
            ('Net run rate', signedDecimal(team.netRunRate)),
          ],
        ),
        const SizedBox(height: 12),
        StatGrid(
          title: 'Runs',
          stats: [
            ('Scored', '${team.runsFor}'),
            ('Conceded', '${team.runsAgainst}'),
            ('Highest', '${team.highest}'),
            ('Lowest', '${team.lowest}'),
          ],
        ),
        const SizedBox(height: 12),
        SurfacePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Form'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final outcome in team.form) _FormChip(outcome)],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionLabel('Top batters'),
        const SizedBox(height: 8),
        for (var i = 0; i < batters.length; i++) ...[
          battingRow(context, i + 1, batters[i]),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        const SectionLabel('Top bowlers'),
        const SizedBox(height: 8),
        for (var i = 0; i < bowlers.length; i++) ...[
          bowlingRow(context, i + 1, bowlers[i]),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _FormChip extends StatelessWidget {
  const _FormChip(this.outcome);

  final MatchOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (outcome) {
      MatchOutcome.won => ('W', AppColors.neon),
      MatchOutcome.lost => ('L', AppColors.wicket),
      MatchOutcome.tied => ('T', AppColors.extra),
      MatchOutcome.noResult => ('N', AppColors.extra),
    };
    return CircleAvatar(
      radius: 18,
      backgroundColor: color,
      child: Text(
        label,
        style: scoreStyle(14, color: outcome == MatchOutcome.won ? AppColors.night : Colors.white),
      ),
    );
  }
}
