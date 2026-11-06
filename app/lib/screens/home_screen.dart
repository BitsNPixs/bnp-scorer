import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../widgets/avatars.dart';
import '../widgets/score_header.dart';
import 'new_match_screen.dart';
import 'scoring_screen.dart';
import 'stats_screen.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _newMatch(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NewMatchScreen()),
    );
    if (context.mounted) ref.invalidate(matchListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(matchListProvider);
    final hasMatches = matches.value?.isNotEmpty ?? false;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _BrandHeader()),
            matches.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SliverFillRemaining(
                child: Center(child: Text('Could not load matches.\n$error', textAlign: TextAlign.center)),
              ),
              data: (list) => list.isEmpty
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(onStart: () => _newMatch(context, ref)),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      sliver: SliverList.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _MatchCard(
                          key: ValueKey(list[i].record.id),
                          summary: list[i],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: hasMatches
          ? FloatingActionButton.extended(
              onPressed: () => _newMatch(context, ref),
              backgroundColor: AppColors.lime,
              foregroundColor: AppColors.ink,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New match', style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.sports_cricket_rounded, color: AppColors.lime),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'BNP Scorer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: scoreStyle(28, color: scheme.onSurface, weight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Stats',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const StatsScreen()),
                ),
                icon: const Icon(Icons.leaderboard_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Score every ball. Own every game.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.inkRaised.withValues(alpha: 0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: -0.5,
                  child: const Icon(Icons.sports_cricket_rounded, size: 84, color: AppColors.lime),
                ),
                const Positioned(
                  right: 36,
                  bottom: 38,
                  child: CircleAvatar(radius: 12, backgroundColor: AppColors.wicket),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text('No matches yet', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Set up two teams and start scoring in under a minute. Works without internet.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start your first match'),
          ),
        ],
      ),
    );
  }
}

class _MatchCard extends ConsumerWidget {
  const _MatchCard({super.key, required this.summary});

  final MatchSummary summary;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ScoringScreen(matchId: summary.record.id)),
    );
    if (context.mounted) ref.invalidate(matchListProvider);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this match?'),
        content: const Text('The scorecard will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.wicket,
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
      final emphasise = winner == team.id ||
          (!state.isCompleted && state.current.battingTeamId == team.id);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            PlayerAvatar(name: team.name, radius: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                team.name,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(
                  fontWeight: emphasise ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            if (inn != null) ...[
              Text(
                scoreLine(inn),
                style: scoreStyle(
                  18,
                  color: scheme.onSurface,
                  weight: emphasise ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
              Text(' (${inn.oversText})', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ] else
              Text('Yet to bat', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context, ref),
        onLongPress: () => _confirmDelete(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (state.isCompleted)
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 16, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text('Result', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    )
                  else
                    const LivePill(onDark: false),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        '${date.day} ${_months[date.month - 1]}',
                        '${setup.rules.oversPerInnings} ov',
                        ?setup.venue,
                      ].join(' · '),
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
              const SizedBox(height: 8),
              Text(
                matchStatus(state),
                style: text.bodySmall?.copyWith(
                  color: state.isCompleted ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
