import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/live_match.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import '../widgets/crease_panel.dart';
import '../widgets/innings_scorecard.dart';
import '../widgets/match_charts.dart';
import '../widgets/match_result_tab.dart';
import '../widgets/over_strip.dart';
import '../widgets/overs_timeline.dart';
import '../widgets/phase_panels.dart';
import '../widgets/score_header.dart';
import '../widgets/score_pad.dart';
import '../widgets/scoring_sheets.dart';
import '../widgets/share_scorecard_sheet.dart';
import '../widgets/stadium_effects.dart';
import '../widgets/wicket_sheet.dart';

class ScoringScreen extends ConsumerWidget {
  const ScoringScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(liveMatchProvider(matchId));
    return match.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not open this match.\n$error', textAlign: TextAlign.center),
          ),
        ),
      ),
      data: (live) => _ScoringView(matchId: matchId, live: live),
    );
  }
}

enum _MenuAction { changeBowler, retire, endInnings, abandon }

class _ScoringView extends ConsumerWidget {
  const _ScoringView({required this.matchId, required this.live});

  final String matchId;
  final LiveMatch live;

  LiveMatchNotifier _notifier(WidgetRef ref) =>
      ref.read(liveMatchProvider(matchId).notifier);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = live.state;
    final setup = state.setup;
    final inn = state.current;
    final phase = state.phase;
    final isLive = phase == MatchPhase.inPlay ||
        phase == MatchPhase.awaitingBowler ||
        phase == MatchPhase.awaitingBatter;
    final canSwap = (phase == MatchPhase.inPlay || phase == MatchPhase.awaitingBowler) &&
        inn.strikerId != null &&
        inn.nonStrikerId != null;

    void act(String? error) => reportResult(context, error);

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
              actions: [
                IconButton(
                  tooltip: 'Undo last action',
                  onPressed: live.canUndo ? () => _undo(context, ref) : null,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: 'Share',
                  onPressed: () => showShareScorecardSheet(context, state),
                  icon: const Icon(Icons.share_rounded),
                ),
                PopupMenuButton<_MenuAction>(
                  enabled: phase != MatchPhase.completed,
                  onSelected: (action) => _onMenu(context, ref, action),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _MenuAction.changeBowler,
                      enabled: phase == MatchPhase.inPlay,
                      child: const ListTile(
                        leading: Icon(Icons.sports_baseball_outlined),
                        title: Text('Change bowler'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _MenuAction.retire,
                      enabled: isLive && phase != MatchPhase.awaitingBatter,
                      child: const ListTile(
                        leading: Icon(Icons.personal_injury_outlined),
                        title: Text('Retire batter'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _MenuAction.endInnings,
                      enabled: isLive,
                      child: const ListTile(
                        leading: Icon(Icons.flag_outlined),
                        title: Text('End innings'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _MenuAction.abandon,
                      child: ListTile(
                        leading: Icon(Icons.umbrella_outlined),
                        title: Text('Abandon match'),
                      ),
                    ),
                  ],
                ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                // Keeps the first pill off the screen edge. Compact, so the
                // Live tab keeps as much room as it can for scoring.
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                tabs: [for (final t in tabs) Tab(height: 38, text: t)],
              ),
            ),
            body: _ResultCelebration(
              state: state,
              child: TabBarView(
                // While scoring, a hurried drag on the pad must not flip tabs.
                // Tapping a tab still works; swiping returns with the result.
                physics: state.isCompleted ? null : const NeverScrollableScrollPhysics(),
                children: [
                  Floodlight(
                    child: state.isCompleted
                        ? MatchResultTab(
                            state: state,
                            onInnings: openInnings,
                            onOvers: () => jumpTo(tabs.length - 2),
                            onCharts: () => jumpTo(tabs.length - 1),
                          )
                        : _liveTab(context, ref, act: act, canSwap: canSwap),
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

  /// Scoring: the score, this over, the batters and bowler, and the panel for
  /// the next action.
  Widget _liveTab(
    BuildContext context,
    WidgetRef ref, {
    required void Function(String? error) act,
    required bool canSwap,
  }) {
    final state = live.state;
    final setup = state.setup;
    final inn = state.current;
    final phase = state.phase;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              ScoreHeader(state: state),
              if (live.saveFailed) ...[
                const SizedBox(height: 12),
                const _Banner(
                  icon: Icons.cloud_off_rounded,
                  text: 'Could not save the last change. It will be saved with the next one.',
                  background: AppColors.wicket,
                  foreground: Colors.white,
                ),
              ],
              if (inn.isFreeHit) ...[
                const SizedBox(height: 12),
                const _Banner(
                  icon: Icons.bolt_rounded,
                  text: 'FREE HIT · only a run out counts',
                  background: AppColors.neon,
                  foreground: AppColors.night,
                ),
              ],
              const SizedBox(height: 12),
              OverStrip(state: state),
              const SizedBox(height: 12),
              CreasePanel(
                state: state,
                onSwapStrike: canSwap ? () => act(_notifier(ref).swapStrike()) : null,
              ),
            ],
          ),
        ),
        _BottomPanel(
          child: KeyedSubtree(
            key: ValueKey('${phase.name}-${inn.number}'),
            child: switch (phase) {
              MatchPhase.awaitingOpeners => OpenersPanel(
                  team: setup.teamById(inn.battingTeamId),
                  onConfirm: (s, ns) => act(_notifier(ref).openers(s, ns)),
                ),
              MatchPhase.awaitingBowler => BowlerPanel(
                  state: state,
                  onSelected: (id) => act(_notifier(ref).bowler(id)),
                ),
              MatchPhase.awaitingBatter => BatterPanel(
                  state: state,
                  onSelected: (id) => act(_notifier(ref).newBatter(id)),
                ),
              MatchPhase.inningsBreak => InningsBreakPanel(
                  state: state,
                  onOpeners: (s, ns) => act(_notifier(ref).openers(s, ns)),
                ),
              // A finished match shows MatchResultTab instead of this tab.
              MatchPhase.completed => const SizedBox.shrink(),
              MatchPhase.inPlay => ScorePad(
                  canUndo: live.canUndo,
                  onUndo: () => _undo(context, ref),
                  onRuns: (r, {required boundary}) => _scoreRuns(context, ref, r, boundary: boundary),
                  onMoreRuns: () => _moreRuns(context, ref),
                  onWide: () => _wide(context, ref),
                  onNoBall: () => _noBall(context, ref),
                  onBye: () => _byes(context, ref, ExtraType.bye),
                  onLegBye: () => _byes(context, ref, ExtraType.legBye),
                  onWicket: () => _wicket(context, ref),
                ),
            },
          ),
        ),
      ],
    );
  }

  void _undo(BuildContext context, WidgetRef ref) {
    if (_notifier(ref).undo()) {
      HapticFeedback.lightImpact();
      showMessage(context, 'Last action undone');
    }
  }

  Future<void> _moreRuns(BuildContext context, WidgetRef ref) async {
    final runs = await showRunsSheet(
      context,
      title: 'Runs completed',
      subtitle: 'All run or overthrows, without a boundary.',
      options: const [4, 5, 6, 7],
      color: Theme.of(context).colorScheme.primary,
    );
    if (runs == null || !context.mounted) return;
    await _scoreRuns(context, ref, runs, boundary: false);
  }

  /// With shot tracking on, asks where it went. Skipping still scores the ball.
  Future<void> _scoreRuns(BuildContext context, WidgetRef ref, int runs, {required bool boundary}) async {
    ShotZone? zone;
    if (live.setup.rules.trackShots && runs > 0) {
      zone = await showShotSheet(context);
      if (!context.mounted) return;
    }
    reportResult(
      context,
      _notifier(ref).ball(runsOffBat: runs, boundary: boundary, shotZone: zone),
    );
  }

  Future<void> _wide(BuildContext context, WidgetRef ref) async {
    final runs = await showRunsSheet(
      context,
      title: 'Wide',
      subtitle: 'Extra runs taken? Pick 4 if it went to the boundary.',
      options: const [0, 1, 2, 3, 4],
    );
    if (runs == null || !context.mounted) return;
    reportResult(context, _notifier(ref).ball(extra: ExtraType.wide, extraRuns: runs));
  }

  Future<void> _noBall(BuildContext context, WidgetRef ref) async {
    final input = await showNoBallSheet(context);
    if (input == null || !context.mounted) return;
    final notifier = _notifier(ref);
    reportResult(
      context,
      input.byes
          ? notifier.ball(extra: ExtraType.noBall, extraRuns: input.runs)
          : notifier.ball(
              extra: ExtraType.noBall,
              runsOffBat: input.runs,
              boundary: input.runs == 4 || input.runs == 6,
            ),
    );
  }

  Future<void> _byes(BuildContext context, WidgetRef ref, ExtraType type) async {
    final runs = await showRunsSheet(
      context,
      title: type == ExtraType.bye ? 'Byes' : 'Leg byes',
      options: const [1, 2, 3, 4],
    );
    if (runs == null || !context.mounted) return;
    reportResult(context, _notifier(ref).ball(extra: type, extraRuns: runs));
  }

  Future<void> _wicket(BuildContext context, WidgetRef ref) async {
    final input = await showWicketSheet(context, live.state);
    if (input == null || !context.mounted) return;
    reportResult(
      context,
      _notifier(ref).ball(
        extra: input.delivery,
        runsOffBat: input.runsOffBat,
        extraRuns: input.extraRuns,
        wicket: input.wicket,
      ),
    );
  }

  Future<void> _confirmAbandon(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abandon this match?'),
        content: const Text(
          'It ends with no result and each team gets a point. Undo brings it back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Abandon'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    reportResult(context, _notifier(ref).abandon('Abandoned'));
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref, _MenuAction action) async {
    final state = live.state;
    final inn = state.current;
    switch (action) {
      case _MenuAction.abandon:
        await _confirmAbandon(context, ref);
      case _MenuAction.changeBowler:
        final id = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          useSafeArea: true,
          isScrollControlled: true,
          builder: (sheetContext) => SheetBody(
            title: 'Change bowler',
            subtitle: 'The new bowler finishes this over.',
            child: BowlerPanel(
              state: state,
              title: 'Replacement',
              onSelected: (bowlerId) => Navigator.of(sheetContext).pop(bowlerId),
            ),
          ),
        );
        if (id == null || !context.mounted) return;
        reportResult(context, _notifier(ref).bowler(id));
      case _MenuAction.retire:
        final choice = await showModalBottomSheet<(String, bool)>(
          context: context,
          showDragHandle: true,
          useSafeArea: true,
          builder: (sheetContext) => SheetBody(
            title: 'Retire batter',
            subtitle: 'Retired hurt can come back later. Retired out counts as a wicket.',
            child: Column(
              children: [
                for (final batterId in [inn.strikerId, inn.nonStrikerId].whereType<String>())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            playerName(state.setup, batterId),
                            style: Theme.of(sheetContext).textTheme.titleMedium,
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop((batterId, true)),
                          child: const Text('Hurt'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop((batterId, false)),
                          child: const Text('Out'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
        if (choice == null || !context.mounted) return;
        reportResult(context, _notifier(ref).retire(choice.$1, hurt: choice.$2));
      case _MenuAction.endInnings:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('End this innings?'),
            content: const Text(
              'Use this for declarations, rain or bad light. You can undo it afterwards.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('End innings'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
        reportResult(context, _notifier(ref).closeInnings('Closed by scorer'));
    }
  }
}

/// Throws confetti when the match is won while the scorer watches. Opening a
/// finished match does not.
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

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
              ),
            ),
          ],
        ),
      );
}
