import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/live_match.dart';
import '../theme/app_theme.dart';
import '../ui/format.dart';
import '../widgets/surface_panel.dart';

class ScorecardScreen extends ConsumerWidget {
  const ScorecardScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(liveMatchProvider(matchId));
    return match.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$error'))),
      data: (live) {
        final state = live.state;
        final setup = state.setup;
        return DefaultTabController(
          length: state.innings.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Scorecard'),
              bottom: TabBar(
                tabs: [
                  for (final inn in state.innings)
                    Tab(text: '${setup.teamById(inn.battingTeamId).name} ${scoreLine(inn)}'),
                ],
              ),
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    matchStatus(state),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final inn in state.innings) _InningsCard(setup: setup, innings: inn),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InningsCard extends StatelessWidget {
  const _InningsCard({required this.setup, required this.innings});

  final MatchSetup setup;
  final InningsState innings;

  @override
  Widget build(BuildContext context) {
    final inn = innings;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final batted = {for (final b in inn.batters) b.playerId};
    final yetToBat = [
      for (final p in setup.teamById(inn.battingTeamId).players)
        if (!batted.contains(p.id)) p.name,
    ];
    final e = inn.extras;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SurfacePanel(
          child: Column(
            children: [
              const _TableHeader(first: 'Batter', columns: ['R', 'B', '4s', '6s', 'SR']),
              for (final b in inn.batters)
                _TableRow(
                  first: taggedPlayerName(setup, b.playerId),
                  subtitle: dismissalText(setup, b),
                  highlight: b.playerId == inn.strikerId || b.playerId == inn.nonStrikerId,
                  columns: [
                    '${b.runs}',
                    '${b.balls}',
                    '${b.fours}',
                    '${b.sixes}',
                    b.strikeRate.toStringAsFixed(1),
                  ],
                ),
              const Divider(height: 24),
              _SummaryLine(
                label: 'Extras',
                value: '${e.total}',
                detail: 'wd ${e.wides}, nb ${e.noBalls}, b ${e.byes}, lb ${e.legByes}',
              ),
              const SizedBox(height: 8),
              _SummaryLine(
                label: 'Total',
                value: scoreLine(inn),
                detail: '${inn.oversText} ov · RR ${inn.runRate.toStringAsFixed(2)}',
                bold: true,
              ),
              if (yetToBat.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Yet to bat: ${yetToBat.join(', ')}',
                    style: text.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (inn.fallOfWickets.isNotEmpty) ...[
          const SizedBox(height: 12),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Fall of wickets'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in inn.fallOfWickets)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${f.runs}-${f.wicketNumber} ${playerName(setup, f.batterId)}, '
                          '${formatOvers(f.legalBalls, inn.ballsPerOver)} ov',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (inn.bowlers.isNotEmpty) ...[
          const SizedBox(height: 12),
          SurfacePanel(
            child: Column(
              children: [
                const _TableHeader(first: 'Bowler', columns: ['O', 'M', 'R', 'W', 'Econ']),
                for (final f in inn.bowlers)
                  _TableRow(
                    first: playerName(setup, f.playerId),
                    subtitle: f.wides + f.noBalls > 0 ? 'wd ${f.wides} · nb ${f.noBalls}' : null,
                    highlight: f.playerId == inn.bowlerId,
                    columns: [
                      f.overs(inn.ballsPerOver),
                      '${f.maidens}',
                      '${f.runs}',
                      '${f.wickets}',
                      f.economy(inn.ballsPerOver).toStringAsFixed(1),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

const _columnWidth = 44.0;

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.first, required this.columns});

  final String first;
  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(first.toUpperCase(), style: style)),
          for (final c in columns)
            SizedBox(width: _columnWidth, child: Text(c, textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.first,
    required this.columns,
    this.subtitle,
    this.highlight = false,
  });

  final String first;
  final String? subtitle;
  final List<String> columns;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  first,
                  style: text.bodyMedium?.copyWith(
                    fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          for (var i = 0; i < columns.length; i++)
            SizedBox(
              width: _columnWidth,
              child: Text(
                columns[i],
                textAlign: TextAlign.end,
                style: scoreStyle(
                  14,
                  color: scheme.onSurface,
                  weight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    required this.detail,
    this.bold = false,
  });

  final String label;
  final String value;
  final String detail;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(label, style: text.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            detail,
            style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Text(value, style: scoreStyle(bold ? 18 : 14, color: Theme.of(context).colorScheme.onSurface)),
      ],
    );
  }
}
