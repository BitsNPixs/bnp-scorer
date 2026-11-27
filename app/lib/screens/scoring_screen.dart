import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/live_match.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../widgets/crease_panel.dart';
import '../widgets/match_tabs_view.dart';
import '../widgets/over_strip.dart';
import '../widgets/phase_panels.dart';
import '../widgets/score_header.dart';
import '../widgets/score_pad.dart';
import '../widgets/scoring_sheets.dart';
import '../widgets/share_scorecard_sheet.dart';
import '../widgets/surface_panel.dart';
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
    final inn = state.current;
    final phase = state.phase;
    final isLive = phase == MatchPhase.inPlay ||
        phase == MatchPhase.awaitingBowler ||
        phase == MatchPhase.awaitingBatter;
    final canSwap = (phase == MatchPhase.inPlay || phase == MatchPhase.awaitingBowler) &&
        inn.strikerId != null &&
        inn.nonStrikerId != null;

    void act(String? error) => reportResult(context, error);

    return MatchTabsView(
      state: state,
      lockSwipeWhileLive: true,
      actions: [
        IconButton(
          tooltip: 'Undo last action',
          onPressed: live.canUndo ? () => _undo(context, ref) : null,
          icon: const Icon(Icons.undo_rounded),
        ),
        IconButton(
          tooltip: 'Share',
          // A match this scorer published has a page on the website.
          onPressed: () => showShareScorecardSheet(
            context,
            state,
            publishedMatchId: live.record.publishedBy == null ? null : live.record.id,
          ),
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
      liveTab: _liveTab(context, ref, act: act, canSwap: canSwap),
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
                const NoticeBanner(
                  icon: Icons.cloud_off_rounded,
                  text: 'Could not save the last change. It will be saved with the next one.',
                  background: AppColors.wicket,
                  foreground: Colors.white,
                ),
              ],
              if (inn.isFreeHit) ...[
                const SizedBox(height: 12),
                const NoticeBanner(
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
      switch (input.from) {
        NoBallRuns.bat => notifier.ball(
            extra: ExtraType.noBall,
            runsOffBat: input.runs,
            boundary: input.runs == 4 || input.runs == 6,
          ),
        NoBallRuns.byes => notifier.ball(extra: ExtraType.noBall, extraRuns: input.runs),
        NoBallRuns.legByes =>
          notifier.ball(extra: ExtraType.noBall, extraRuns: input.runs, legByes: true),
      },
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
    final notifier = _notifier(ref);
    final input = await showWicketSheet(
      context,
      live.state,
      preview: (i) => notifier.previewWicketBall(
        extra: i.delivery,
        runsOffBat: i.runsOffBat,
        extraRuns: i.extraRuns,
        wicket: i.wicket,
      ),
    );
    if (input == null || !context.mounted) return;
    reportResult(
      context,
      notifier.ball(
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
