import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloud_cups.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/motion.dart';
import '../widgets/match_card.dart';
import '../widgets/scoring_sheets.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/stadium_effects.dart';
import '../widgets/stumps_art.dart';
import '../widgets/summary_tiles.dart';
import '../widgets/surface_panel.dart';
import '../widgets/upcoming.dart';
import 'watch_match_screen.dart';
import 'watch_tournament_screen.dart';

const _allMatches = 'all';
const _friendlies = 'friendlies';

/// Every match on the device, newest first, with a filter per tournament. In a
/// cloud build, a switch at the top also shows everyone's published matches.
class MatchesTab extends ConsumerStatefulWidget {
  const MatchesTab({super.key, required this.onNewMatch});

  final VoidCallback onNewMatch;

  @override
  ConsumerState<MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends ConsumerState<MatchesTab> {
  /// [_allMatches], [_friendlies] or a tournament id.
  String _filter = _allMatches;

  /// Showing everyone's published matches instead of this phone's.
  bool _everyone = false;

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
    final hasCloud = ref.watch(cloudMatchesProvider) != null;
    final everyone = hasCloud && _everyone;
    final upcoming = ref.watch(upcomingProvider).value ?? const [];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Floodlight(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _HomeHeader()),
              if (hasCloud)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: OptionChips<bool>(
                      options: const [false, true],
                      labelOf: (e) => e ? 'Everyone' : 'My matches',
                      selected: everyone,
                      color: Theme.of(context).colorScheme.primary,
                      onSelected: (e) => setState(() => _everyone = e),
                    ),
                  ),
                ),
              if (everyone) ...const [
                _EveryoneUpcoming(),
                _EveryoneCups(),
                SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, 4), child: SectionTitle('Live and recent')),
                ),
                _EveryoneList(),
              ] else ...[
                if (upcoming.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 10), child: SectionTitle('Upcoming')),
                  ),
                  SliverToBoxAdapter(child: UpcomingStrip(matches: upcoming)),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ],
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

/// Everyone's upcoming fixtures and friendlies. Nothing when there are none.
class _EveryoneUpcoming extends ConsumerWidget {
  const _EveryoneUpcoming();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(publicUpcomingProvider);
    if (upcoming.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, 10), child: SectionTitle('Upcoming')),
          UpcomingStrip(matches: upcoming, watching: true),
        ],
      ),
    );
  }
}

/// Everyone's published tournaments, newest first. Nothing when there are none.
class _EveryoneCups extends ConsumerWidget {
  const _EveryoneCups();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cups = ref.watch(publicTournamentsProvider).value ?? const [];
    if (cups.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 10), child: SectionTitle('Cups')),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: cups.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _CupCard(published: cups[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CupCard extends StatelessWidget {
  const _CupCard({required this.published});

  final PublishedTournament published;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tournament = published.tournament;
    final format = tournament.isKnockout
        ? 'Knockout cup'
        : (tournament.groups.length == 2 ? 'Two groups' : 'League');
    return SizedBox(
      width: 240,
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: cardShape(context, radius: 20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => WatchTournamentScreen(tournamentId: tournament.id)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_rounded, color: AppColors.four, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tournament.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${tournament.teams.length} teams · $format',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      Text(
                        'By ${published.ownerName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Everyone's published matches, newest first, updating live. Tapping one
/// watches it.
class _EveryoneList extends ConsumerWidget {
  const _EveryoneList();

  static const emptyMessage = 'No public matches yet.\nSign in from Settings, and the matches you score '
      'show up here for everyone.';
  static const errorMessage = 'Could not load public matches. Check your connection and try again.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(publicMatchesProvider);
    Widget message(String text) => SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(text, textAlign: TextAlign.center))),
    );
    return matches.when(
      loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
      error: (_, _) => message(errorMessage),
      data: (list) => list.isEmpty
          ? message(emptyMessage)
          : SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final published = list[i].match;
                  return EntranceFade(
                    key: ValueKey('public-${published.record.id}'),
                    index: i,
                    child: MatchCard(
                      summary: (record: published.record, state: list[i].state),
                      scoredBy: published.ownerName,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => WatchMatchScreen(matchId: published.record.id)),
                      ),
                    ),
                  );
                },
              ),
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
