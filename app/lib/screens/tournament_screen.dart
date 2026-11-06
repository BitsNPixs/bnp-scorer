import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../widgets/stat_widgets.dart';
import '../widgets/surface_panel.dart';
import 'new_match_screen.dart';
import 'scoring_screen.dart';
import 'stats_screen.dart';

class TournamentScreen extends ConsumerWidget {
  const TournamentScreen({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(tournamentsProvider);
    final progress =
        tournaments.value?.where((p) => p.tournament.id == tournamentId).firstOrNull;
    if (progress == null) {
      return Scaffold(
        appBar: AppBar(),
        body: tournaments.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const StatsEmpty(message: 'This tournament is no longer here.'),
      );
    }
    final book = progress.book;
    const noResults = StatsEmpty(message: 'Stats appear here once a match has finished.');
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(progress.tournament.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Matches'),
              Tab(text: 'Table'),
              Tab(text: 'Batting'),
              Tab(text: 'Bowling'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MatchesTab(progress: progress),
            _TableTab(progress: progress),
            if (book.isEmpty) noResults else BattingTab(book: book),
            if (book.isEmpty) noResults else BowlingTab(book: book),
          ],
        ),
      ),
    );
  }
}

class _MatchesTab extends ConsumerWidget {
  const _MatchesTab({required this.progress});

  final TournamentProgress progress;

  Future<void> _open(BuildContext context, WidgetRef ref, FixtureProgress item) async {
    final navigator = Navigator.of(context);
    final match = item.match;
    if (match != null) {
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => ScoringScreen(matchId: match.setup.id)),
      );
    } else {
      await _startFixture(context, ref, item.fixture);
    }
    if (context.mounted) ref.invalidate(matchListProvider);
  }

  /// Fills the setup from the latest saved squads, falling back to the squad
  /// the tournament started with if a team has since been deleted.
  Future<void> _startFixture(BuildContext context, WidgetRef ref, Fixture fixture) async {
    final tournament = progress.tournament;
    final navigator = Navigator.of(context);
    final saved = await ref.read(teamRepositoryProvider).loadAll();
    Team latest(String id) =>
        saved.where((t) => t.id == id).firstOrNull ?? tournament.teamById(id);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => NewMatchScreen(
          fixture: FixtureMatch(
            tournament: tournament,
            fixture: fixture,
            home: latest(fixture.teamAId),
            away: latest(fixture.teamBId),
          ),
        ),
      ),
    );
  }

  Future<void> _scheduleNextRound(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(tournamentRepositoryProvider);
    try {
      await repository.save(progress.tournament.withFixtures(progress.nextRound));
    } on Object catch (e) {
      if (context.mounted) showMessage(context, 'Could not add the next round: $e', isError: true);
      return;
    }
    if (context.mounted) ref.invalidate(tournamentsProvider);
  }

  Future<void> _correct(BuildContext context, WidgetRef ref, List<Fixture> fixtures) async {
    final repository = ref.read(tournamentRepositoryProvider);
    try {
      await repository.save(progress.tournament.withCorrected(fixtures));
    } on Object catch (e) {
      if (context.mounted) showMessage(context, 'Could not update it: $e', isError: true);
      return;
    }
    if (context.mounted) ref.invalidate(tournamentsProvider);
  }

  String _nextRoundLabel() {
    final next = progress.nextRound;
    final first = next.first;
    if (next.length > 1) return 'Set up the semi-finals';
    final tournament = progress.tournament;
    final teams = '${tournament.teamById(first.teamAId).name} v '
        '${tournament.teamById(first.teamBId).name}';
    return first.isDecider ? 'Tied: set up the Super Over, $teams' : 'Set up the final: $teams';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournament = progress.tournament;
    final champion = progress.championId;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (champion != null) ...[
          _ChampionBanner(name: tournament.teamById(champion).name),
          const SizedBox(height: 12),
        ],
        for (final fixture in progress.outdated) ...[
          _OutdatedFixture(
            fixture: fixture,
            tournament: tournament,
            started: progress.fixtures.any(
              (f) => f.fixture.id == fixture.id && f.match != null,
            ),
            onUpdate: () => _correct(context, ref, [fixture]),
          ),
          const SizedBox(height: 12),
        ],
        for (final item in progress.fixtures) ...[
          _FixtureCard(
            item: item,
            tournament: tournament,
            onTap: () => _open(context, ref, item),
          ),
          const SizedBox(height: 10),
        ],
        if (progress.nextRound.isNotEmpty)
          FilledButton.icon(
            onPressed: () => _scheduleNextRound(context, ref),
            icon: const Icon(Icons.emoji_events_rounded),
            label: Text(
              _nextRoundLabel(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

/// A knockout game whose teams no longer follow from the results. Until it
/// starts it can be corrected. Once played, only its scorer can decide.
class _OutdatedFixture extends StatelessWidget {
  const _OutdatedFixture({
    required this.fixture,
    required this.tournament,
    required this.started,
    required this.onUpdate,
  });

  final Fixture fixture;
  final Tournament tournament;
  final bool started;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final teams = '${tournament.teamById(fixture.teamAId).name} v '
        '${tournament.teamById(fixture.teamBId).name}';
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Results changed'),
          const SizedBox(height: 6),
          Text(
            started
                ? '${fixture.label} was played by different teams. It should now be '
                    '$teams. Delete that match from Home to replay it.'
                : '${fixture.label} should now be $teams.',
          ),
          if (!started) ...[
            const SizedBox(height: 10),
            FilledButton(onPressed: onUpdate, child: Text('Update ${fixture.label}')),
          ],
        ],
      ),
    );
  }
}

class _TableTab extends StatelessWidget {
  const _TableTab({required this.progress});

  final TournamentProgress progress;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final group in progress.tables) ...[
            if (group.name case final name?) ...[
              SectionLabel(name),
              const SizedBox(height: 8),
            ],
            for (var i = 0; i < group.teams.length; i++) ...[
              teamRow(context, i + 1, group.teams[i]),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
          ],
        ],
      );
}

class _ChampionBanner extends StatelessWidget {
  const _ChampionBanner({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            const Icon(Icons.emoji_events_rounded, size: 40, color: AppColors.lime),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CHAMPIONS', style: TextStyle(color: Colors.white70, letterSpacing: 1.4)),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: scoreStyle(26, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _FixtureCard extends StatelessWidget {
  const _FixtureCard({required this.item, required this.tournament, required this.onTap});

  final FixtureProgress item;
  final Tournament tournament;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fixture = item.fixture;
    final match = item.match;
    final teamA = tournament.teamById(fixture.teamAId).name;
    final teamB = tournament.teamById(fixture.teamBId).name;

    return SurfacePanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionLabel(fixture.label),
              const SizedBox(height: 6),
              Text(
                '$teamA v $teamB',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                match == null ? 'Tap to start' : matchStatus(match),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: item.isFinished ? scheme.primary : scheme.onSurfaceVariant,
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
