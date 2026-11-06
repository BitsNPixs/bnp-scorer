import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import 'over_strip.dart';
import 'stat_widgets.dart';
import 'surface_panel.dart';

const _overColumnWidth = 64.0;
const _runsColumnWidth = 36.0;
const _chipSize = 30.0;

/// Every over of an innings, newest first: the score it ended on, who bowled to
/// whom, and each ball.
class OversTimeline extends StatefulWidget {
  const OversTimeline({super.key, required this.state});

  final MatchState state;

  @override
  State<OversTimeline> createState() => _OversTimelineState();
}

class _OversTimelineState extends State<OversTimeline> {
  /// Null follows the innings in progress.
  int? _inningsIndex;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final setup = state.setup;
    final innings = state.innings;
    final index = _inningsIndex ?? innings.length - 1;
    final overs = innings[index].overs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (innings.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < innings.length; i++)
                  ChoiceChip(
                    label: Text(setup.teamById(innings[i].battingTeamId).name),
                    selected: i == index,
                    onSelected: (_) => setState(() => _inningsIndex = i),
                  ),
              ],
            ),
          ),
        Expanded(
          child: overs.isEmpty
              ? const StatsEmpty(message: 'No balls bowled yet.')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: overs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final number = overs.length - i;
                    return _OverRow(setup: setup, number: number, over: overs[number - 1]);
                  },
                ),
        ),
      ],
    );
  }
}

class _OverRow extends StatelessWidget {
  const _OverRow({required this.setup, required this.number, required this.over});

  final MatchSetup setup;
  final int number;
  final OverSummary over;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return SurfacePanel(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _overColumnWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ov $number',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text('${over.scoreAfter}-${over.wicketsAfter}', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(overHeadline(setup, over), maxLines: 2, overflow: TextOverflow.ellipsis, style: muted),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final ball in over.balls) BallChip(ball: ball, size: _chipSize),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: _runsColumnWidth,
            child: Text(
              '${over.runs}',
              textAlign: TextAlign.end,
              style: scoreStyle(20, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
