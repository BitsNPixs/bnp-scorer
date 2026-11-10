import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/live_match.dart';
import '../ui/format.dart';
import '../widgets/innings_scorecard.dart';
import '../widgets/match_charts.dart';
import '../widgets/overs_timeline.dart';
import '../widgets/share_scorecard_sheet.dart';

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
          length: state.innings.length + 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Scorecard'),
              actions: [
                IconButton(
                  tooltip: 'Share',
                  onPressed: () => showShareScorecardSheet(context, state),
                  icon: const Icon(Icons.share_rounded),
                ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                // Keeps the first pill off the screen edge.
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                tabs: [
                  for (final inn in state.innings)
                    Tab(text: '${setup.teamById(inn.battingTeamId).name} ${scoreLine(inn)}'),
                  const Tab(text: 'Overs'),
                  const Tab(text: 'Charts'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                for (final inn in state.innings) InningsScorecard(state: state, innings: inn),
                OversTimeline(state: state),
                MatchCharts(state: state),
              ],
            ),
          ),
        );
      },
    );
  }
}
