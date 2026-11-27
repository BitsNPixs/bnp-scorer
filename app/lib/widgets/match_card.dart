import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:match_view/match_view.dart' show MatchNow;

import '../screens/scoring_screen.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import 'avatars.dart';
import 'score_header.dart';
import 'surface_panel.dart';

/// One match on the home list: tap to open it, long-press to delete it.
class MatchCard extends ConsumerWidget {
  const MatchCard({super.key, required this.summary, this.tournamentName, this.scoredBy, this.onTap});

  final MatchSummary summary;
  final String? tournamentName;

  /// Who scores a published match, shown under its status.
  final String? scoredBy;

  /// Replaces opening the match for scoring, e.g. with watching someone
  /// else's match. Such a card cannot be deleted with a long press.
  final VoidCallback? onTap;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ScoringScreen(matchId: summary.record.id)));
    if (context.mounted) ref.invalidate(matchListProvider);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this match?'),
        content: Text(
          tournamentName == null
              ? 'The scorecard will be removed from this device.'
              : 'This is a $tournamentName match. Deleting it reopens its fixture and '
                    'changes the table and stats.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.wicket,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final repository = ref.read(matchRepositoryProvider);
    await repository.delete(summary.record.id);
    if (!context.mounted) return;
    ref.invalidate(matchListProvider);
    showMessage(context, 'Match deleted');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = summary.state;
    final setup = state.setup;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final date = summary.record.createdAt.toLocal();
    final winner = state.result?.winnerTeamId;
    final live = !state.isCompleted;
    // Left unfinished hours ago: still laid out as a match in play, but not
    // called live.
    final stopped = nowOf(summary, ref.watch(clockProvider)()) == MatchNow.stopped;
    final current = state.current;

    InningsState? inningsOf(String teamId) {
      for (final inn in state.innings) {
        if (inn.battingTeamId == teamId && (inn.legalBalls > 0 || inn.runs > 0 || inn.isComplete)) {
          return inn;
        }
      }
      return null;
    }

    Widget teamLine(Team team) {
      final inn = inningsOf(team.id);
      final emphasise = winner == team.id || (live && current.battingTeamId == team.id);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            PlayerAvatar(name: team.name, radius: 15),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(fontWeight: emphasise ? FontWeight.w800 : FontWeight.w500),
                    ),
                  ),
                  if (winner == team.id) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.emoji_events_rounded, size: 16, color: AppColors.four),
                  ],
                ],
              ),
            ),
            if (inn != null) ...[
              Text(
                scoreLine(inn),
                style: scoreStyle(
                  22,
                  color: emphasise ? scheme.onSurface : scheme.onSurfaceVariant,
                  weight: emphasise ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              Text(' (${inn.oversText})', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ] else
              Text('Yet to bat', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final card = Material(
      color: scheme.surfaceContainerLowest,
      shape: cardShape(context, accent: live ? scheme.primary.withValues(alpha: 0.55) : null),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => _open(context, ref),
        onLongPress: onTap == null ? () => _confirmDelete(context, ref) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (stopped)
                    StatusTag(label: 'STOPPED', color: scheme.onSurfaceVariant)
                  else if (live)
                    const LivePill(onDark: false)
                  else
                    StatusTag(label: 'RESULT', color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [shortDate(date), '${setup.rules.oversPerInnings} ov', ?setup.venue].join(' · '),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              teamLine(setup.teamA),
              teamLine(setup.teamB),
              if (live && current.maxBalls > 0) ...[
                const SizedBox(height: 10),
                _OversProgress(value: current.legalBalls / current.maxBalls),
              ],
              const SizedBox(height: 10),
              Text(
                matchStatus(state),
                style: text.bodySmall?.copyWith(
                  color: state.isCompleted ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (scoredBy case final scorer?) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.sports_cricket_rounded, size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Scored by $scorer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!live) return card;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.glow(scheme.primary, strength: 0.14, blur: 22),
      ),
      child: card,
    );
  }
}

/// A small outlined label, e.g. "RESULT".
/// How much of the current innings is gone, filling as it loads.
class _OversProgress extends StatelessWidget {
  const _OversProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(99),
    child: Container(
      height: 6,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      alignment: Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduceMotion(context) ? value : 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => FractionallySizedBox(
          widthFactor: v,
          child: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.neonGradient),
            child: SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
}
