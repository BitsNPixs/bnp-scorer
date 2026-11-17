import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../ui/format.dart';
import '../ui/motion.dart';
import 'innings_scorecard.dart';
import 'match_charts.dart';
import 'match_result_tab.dart';
import 'overs_timeline.dart';
import 'stadium_effects.dart';

/// The frame of a match screen: the teams as the title, then tabs for Live (or
/// Result once it is over), each innings, Overs and Charts, with confetti on a
/// win. The scorer's screen and the read-only view of a published match both
/// use it, so the two always look alike.
class MatchTabsView extends StatelessWidget {
  const MatchTabsView({
    super.key,
    required this.state,
    required this.liveTab,
    this.actions = const [],
    this.lockSwipeWhileLive = false,
  });

  final MatchState state;

  /// The first tab while the match is on. A finished match shows its result
  /// there instead.
  final Widget liveTab;
  final List<Widget> actions;

  /// While scoring, a hurried drag on the pad must not flip tabs. Tapping a
  /// tab still works, and swiping returns with the result.
  final bool lockSwipeWhileLive;

  @override
  Widget build(BuildContext context) {
    final setup = state.setup;
    final tabs = [
      if (state.isCompleted) 'Result' else 'Live',
      for (final innings in state.innings) '${setup.teamById(innings.battingTeamId).name} ${scoreLine(innings)}',
      'Overs',
      'Charts',
    ];

    return DefaultTabController(
      // A new innings adds a tab, which needs a fresh controller.
      key: ValueKey(tabs.length),
      length: tabs.length,
      child: Builder(
        builder: (context) {
          void jumpTo(int tab) => DefaultTabController.of(context).animateTo(tab);
          void openInnings(int index) => jumpTo(1 + index);
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              scrolledUnderElevation: 0,
              title: Text(
                '${setup.teamA.name} vs ${setup.teamB.name}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              actions: actions,
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                // Keeps the first pill off the screen edge. Compact, so the
                // Live tab keeps as much room as it can.
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                tabs: [for (final t in tabs) Tab(height: 38, text: t)],
              ),
            ),
            body: _ResultCelebration(
              state: state,
              child: TabBarView(
                physics: lockSwipeWhileLive && !state.isCompleted ? const NeverScrollableScrollPhysics() : null,
                children: [
                  Floodlight(
                    child: state.isCompleted
                        ? MatchResultTab(
                            state: state,
                            onInnings: openInnings,
                            onOvers: () => jumpTo(tabs.length - 2),
                            onCharts: () => jumpTo(tabs.length - 1),
                          )
                        : liveTab,
                  ),
                  for (final innings in state.innings)
                    InningsScorecard(state: state, innings: innings, onInnings: openInnings),
                  OversTimeline(state: state),
                  MatchCharts(state: state),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Confetti the moment a match is won.
class _ResultCelebration extends StatefulWidget {
  const _ResultCelebration({required this.state, required this.child});

  final MatchState state;
  final Widget child;

  @override
  State<_ResultCelebration> createState() => _ResultCelebrationState();
}

class _ResultCelebrationState extends State<_ResultCelebration> {
  /// Bumped per celebration, so a second win (after an undo) replays it.
  int _bursts = 0;

  @override
  void didUpdateWidget(_ResultCelebration old) {
    super.didUpdateWidget(old);
    final justWon = !old.state.isCompleted &&
        widget.state.isCompleted &&
        widget.state.result?.winnerTeamId != null;
    if (justWon && !reduceMotion(context)) setState(() => _bursts++);
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          widget.child,
          if (_bursts > 0) Positioned.fill(child: ConfettiBurst(key: ValueKey(_bursts))),
        ],
      );
}
