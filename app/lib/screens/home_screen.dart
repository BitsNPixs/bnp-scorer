import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../widgets/avatars.dart';
import '../widgets/score_header.dart';
import 'backup_screen.dart';
import 'new_match_screen.dart';
import 'scoring_screen.dart';
import 'stats_screen.dart';
import 'teams_screen.dart';
import 'tournaments_screen.dart';

const _allMatches = 'all';
const _friendlies = 'friendlies';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// [_allMatches], [_friendlies] or a tournament id.
  String _filter = _allMatches;

  /// Which tournament each of its matches belongs to, for the delete warning.
  Map<String, String> _tournamentNames(List<TournamentProgress> tournaments) => {
        for (final p in tournaments)
          for (final f in p.tournament.fixtures) ?f.matchId: p.tournament.name,
      };

  /// The list for [_filter]. A deleted tournament falls back to all matches.
  List<MatchSummary> _filtered(List<MatchSummary> matches, List<TournamentProgress> tournaments) {
    Set<String> matchIdsOf(Iterable<TournamentProgress> list) => {
          for (final p in list)
            for (final f in p.tournament.fixtures) ?f.matchId,
        };
    if (_filter == _friendlies) {
      final inTournaments = matchIdsOf(tournaments);
      return matches.where((m) => !inTournaments.contains(m.record.id)).toList();
    }
    final chosen = tournaments.where((p) => p.tournament.id == _filter);
    if (chosen.isEmpty) return matches;
    final ids = matchIdsOf(chosen);
    return matches.where((m) => ids.contains(m.record.id)).toList();
  }

  Future<void> _newMatch(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NewMatchScreen()),
    );
    if (context.mounted) ref.invalidate(matchListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final matches = ref.watch(matchListProvider);
    final tournaments = ref.watch(tournamentsProvider).value ?? const <TournamentProgress>[];
    final hasMatches = matches.value?.isNotEmpty ?? false;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _BrandHeader()),
            if (tournaments.isNotEmpty)
              SliverToBoxAdapter(
                child: _MatchFilter(
                  selected: _filter,
                  tournaments: tournaments,
                  onSelected: (filter) => setState(() => _filter = filter),
                ),
              ),
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
                  : _MatchList(
                      matches: _filtered(list, tournaments),
                      tournamentNames: _tournamentNames(tournaments),
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

/// Chips that narrow the home list to one tournament, or to friendlies.
class _MatchFilter extends StatelessWidget {
  const _MatchFilter({
    required this.selected,
    required this.tournaments,
    required this.onSelected,
  });

  final String selected;
  final List<TournamentProgress> tournaments;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chip(String filter, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: selected == filter,
            onSelected: (_) => onSelected(filter),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          chip(_allMatches, 'All'),
          chip(_friendlies, 'Friendlies'),
          for (final p in tournaments) chip(p.tournament.id, p.tournament.name),
        ],
      ),
    );
  }
}

class _MatchList extends StatelessWidget {
  const _MatchList({required this.matches, required this.tournamentNames});

  final List<MatchSummary> matches;
  final Map<String, String> tournamentNames;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('No matches here yet.')),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      sliver: SliverList.separated(
        itemCount: matches.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _MatchCard(
          key: ValueKey(matches[i].record.id),
          summary: matches[i],
          tournamentName: tournamentNames[matches[i].record.id],
        ),
      ),
    );
  }
}

enum _MoreAction { teams, backup }

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  void _onMore(BuildContext context, _MoreAction action) {
    switch (action) {
      case _MoreAction.teams:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TeamsScreen()),
        );
      case _MoreAction.backup:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
        );
    }
  }

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
                tooltip: 'Tournaments',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TournamentsScreen()),
                ),
                icon: const Icon(Icons.emoji_events_rounded),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Score every ball. Own every game.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              PopupMenuButton<_MoreAction>(
                tooltip: 'More',
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (action) => _onMore(context, action),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _MoreAction.teams,
                    child: ListTile(leading: Icon(Icons.groups_rounded), title: Text('Teams')),
                  ),
                  PopupMenuItem(
                    value: _MoreAction.backup,
                    child: ListTile(leading: Icon(Icons.backup_rounded), title: Text('Backup')),
                  ),
                ],
              ),
            ],
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
  const _MatchCard({super.key, required this.summary, this.tournamentName});

  final MatchSummary summary;
  final String? tournamentName;

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
        content: Text(
          tournamentName == null
              ? 'The scorecard will be removed from this device.'
              : 'This is a $tournamentName match. Deleting it reopens its fixture and '
                  'changes the table and stats.',
        ),
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
                        shortDate(date),
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
