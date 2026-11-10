import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/motion.dart';
import '../widgets/match_card.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/stadium_effects.dart';
import '../widgets/stumps_art.dart';
import '../widgets/summary_tiles.dart';
import '../widgets/surface_panel.dart';

const _allMatches = 'all';
const _friendlies = 'friendlies';

/// Every match on the device, newest first, with a filter per tournament.
class MatchesTab extends ConsumerStatefulWidget {
  const MatchesTab({super.key, required this.onNewMatch});

  final VoidCallback onNewMatch;

  @override
  ConsumerState<MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends ConsumerState<MatchesTab> {
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

  @override
  Widget build(BuildContext context) {
    final matches = ref.watch(matchListProvider);
    final tournaments = ref.watch(tournamentsProvider).value ?? const <TournamentProgress>[];
    final list = matches.value ?? const <MatchSummary>[];
    final isLight = Theme.of(context).brightness == Brightness.light;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Floodlight(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _HomeHeader()),
              if (list.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: EntranceFade(child: _HeroCard(onStart: widget.onNewMatch)),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: SummaryTiles(matches: list, tournamentCount: tournaments.length),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.fromLTRB(20, 22, 20, 4), child: SectionTitle('Matches')),
                ),
              ],
              if (tournaments.isNotEmpty && list.isNotEmpty)
                SliverToBoxAdapter(
                  child: _MatchFilter(
                    selected: _filter,
                    tournaments: tournaments,
                    onSelected: (filter) => setState(() => _filter = filter),
                  ),
                ),
              matches.when(
                loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
                error: (error, _) => SliverFillRemaining(
                  child: Center(child: Text('Could not load matches.\n$error', textAlign: TextAlign.center)),
                ),
                data: (all) => all.isEmpty
                    ? SliverFillRemaining(hasScrollBody: false, child: _EmptyState(onStart: widget.onNewMatch))
                    : _MatchList(matches: _filtered(all, tournaments), tournamentNames: _tournamentNames(tournaments)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chips that narrow the home list to one tournament, or to friendlies.
class _MatchFilter extends StatelessWidget {
  const _MatchFilter({required this.selected, required this.tournaments, required this.onSelected});

  final String selected;
  final List<TournamentProgress> tournaments;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chip(String filter, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(label: Text(label), selected: selected == filter, onSelected: (_) => onSelected(filter)),
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
      return const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No matches here yet.')));
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      sliver: SliverList.separated(
        itemCount: matches.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => EntranceFade(
          key: ValueKey(matches[i].record.id),
          index: i,
          child: MatchCard(summary: matches[i], tournamentName: tournamentNames[matches[i].record.id]),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.neon.withValues(alpha: 0.35)),
              boxShadow: AppColors.glow(AppColors.neon, strength: 0.25, blur: 16),
            ),
            child: const Icon(Icons.sports_cricket_rounded, color: AppColors.neon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BNP SCORER',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.display(
                    TextStyle(
                      fontSize: 28,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 0.5,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Score every ball. Own every game.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Settings',
            onPressed: () => showSettingsSheet(context),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
    );
  }
}

/// The floodlit welcome card, with a big way into a new match.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final title = AppFonts.display(
      const TextStyle(
        fontSize: 30,
        height: 1.05,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        color: Colors.white,
      ),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.neon.withValues(alpha: 0.18)),
        boxShadow: AppColors.glow(AppColors.night, strength: 0.25),
      ),
      child: Stack(
        children: [
          const Positioned(right: 6, bottom: 0, child: StumpsArt()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 112, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MATCH DAY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.neon,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Every ball.\nEvery '),
                      TextSpan(
                        text: 'run.',
                        style: title.copyWith(color: AppColors.neon),
                      ),
                    ],
                  ),
                  style: title,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Scores ball by ball, even offline.',
                  style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                _NeonPillButton(label: 'New match', onTap: onStart),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Neon stadium button with an arrow, the hero card's call to action.
class _NeonPillButton extends StatelessWidget {
  const _NeonPillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: AppColors.neonGradient,
      borderRadius: BorderRadius.circular(99),
      boxShadow: AppColors.glow(AppColors.neon, strength: 0.35, blur: 18),
    ),
    child: Material(
      type: MaterialType.transparency,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.night, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              const CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.night,
                child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.neon),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
          PopIn(
            duration: const Duration(milliseconds: 900),
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.neon.withValues(alpha: 0.3), width: 2),
                boxShadow: AppColors.glow(AppColors.neon, strength: 0.3, blur: 40),
              ),
              child: const Center(child: StumpsArt()),
            ),
          ),
          const SizedBox(height: 32),
          Text('No matches yet', style: text.headlineSmall),
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
