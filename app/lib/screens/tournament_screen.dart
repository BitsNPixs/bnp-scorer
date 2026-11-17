import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../state/upcoming.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import '../widgets/avatars.dart';
import '../widgets/prizes_tab.dart';
import '../widgets/stat_widgets.dart';
import '../widgets/surface_panel.dart';
import '../widgets/upcoming.dart';
import 'new_match_screen.dart';
import 'scoring_screen.dart';
import 'stats_screen.dart';
import 'watch_match_screen.dart';

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
    return TournamentView(progress: progress);
  }
}

/// One tournament's tabs. With an [organiser], it is someone else's published
/// tournament, watched: nothing can be started, set up or edited, and
/// payments are not there at all.
class TournamentView extends StatelessWidget {
  const TournamentView({super.key, required this.progress, this.organiser});

  final TournamentProgress progress;
  final String? organiser;

  @override
  Widget build(BuildContext context) {
    final watching = organiser != null;
    final book = progress.book;
    final tournament = progress.tournament;
    const noResults = StatsEmpty(message: 'Stats appear here once a match has finished.');
    // A cup has no table; a league without knockouts has no bracket.
    final hasTable = !tournament.isKnockout;
    final hasBracket = tournament.bracket.isNotEmpty;
    return DefaultTabController(
      length: 6 + (hasTable ? 1 : 0) + (hasBracket ? 1 : 0),
      child: Scaffold(
        appBar: AppBar(
          title: Text(tournament.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Matches'),
              if (hasBracket) const Tab(text: 'Bracket'),
              if (hasTable) const Tab(text: 'Table'),
              const Tab(text: 'Prizes'),
              const Tab(text: 'Batting'),
              const Tab(text: 'Bowling'),
              const Tab(text: 'MVP'),
              const Tab(text: 'Boundaries'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MatchesTab(progress: progress, organiser: organiser),
            if (hasBracket) _BracketTab(progress: progress, watching: watching),
            if (hasTable) _TableTab(progress: progress),
            PrizesTab(tournament: tournament, watching: watching),
            if (book.isEmpty) noResults else BattingTab(book: book),
            if (book.isEmpty) noResults else BowlingTab(book: book),
            if (book.isEmpty) noResults else MvpTab(book: book),
            if (book.isEmpty) noResults else BoundariesTab(book: book),
          ],
        ),
      ),
    );
  }
}

class _MatchesTab extends ConsumerWidget {
  const _MatchesTab({required this.progress, this.organiser});

  final TournamentProgress progress;

  /// Set when watching someone else's tournament.
  final String? organiser;

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

  /// "Set up the final: A v B", "Set up the quarter-finals", "Set up 3 games".
  String _nextRoundLabel() {
    final next = progress.nextRound;
    final tournament = progress.tournament;
    if (next.length == 1) {
      final game = next.single;
      final teams = '${tournament.teamById(game.teamAId).name} v ${tournament.teamById(game.teamBId).name}';
      if (game.isDecider) return 'Set up the Super Over: $teams';
      return game.id == finalFixtureId ? 'Set up the final: $teams' : 'Set up ${game.label}: $teams';
    }
    final rounds = {
      for (final f in next) tournament.bracket.where((g) => g.id == f.id).firstOrNull?.round,
    };
    if (rounds.length == 1 && rounds.single != null) {
      return 'Set up the ${_roundTitle(rounds.single!, next.length).toLowerCase()}';
    }
    return 'Set up ${next.length} games';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournament = progress.tournament;
    final champion = progress.championId;
    final watching = organiser != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (organiser case final name?) ...[
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Organised by $name. Results update as each match is scored.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (champion != null) ...[
          _ChampionBanner(
            name: tournament.teamById(champion).name,
            bestPlayer: progress.playerOfTheTournament?.name,
            prize: tournament.prizes.firstOrNull?.reward,
          ),
          const SizedBox(height: 12),
        ],
        if (!watching)
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
            watching: watching,
            onTap: () => _openFixture(context, ref, progress.tournament, item, watching: watching),
            // Time, ground and invite, until it starts.
            onLongPress: item.match == null && !watching
                ? () => showUpcomingSheet(context, ref, UpcomingMatch.fixture(tournament, item.fixture))
                : null,
          ),
          const SizedBox(height: 10),
        ],
        if (progress.nextRound.isNotEmpty && !watching)
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

/// "Quarter-finals", or "Final" and "Round of 16" as they are.
String _roundTitle(String round, int games) => games == 1 || round.startsWith('Round of') ? round : '${round}s';

/// Opens a fixture's match, or starts it through New match, filled in. When
/// [watching], a played match opens read-only and an unplayed one does nothing.
Future<void> _openFixture(
  BuildContext context,
  WidgetRef ref,
  Tournament tournament,
  FixtureProgress item, {
  bool watching = false,
}) async {
  final navigator = Navigator.of(context);
  final match = item.match;
  if (watching) {
    if (match != null) {
      await navigator.push(MaterialPageRoute<void>(builder: (_) => WatchMatchScreen(matchId: match.setup.id)));
    }
    return;
  }
  if (match != null) {
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => ScoringScreen(matchId: match.setup.id)),
    );
  } else {
    await startFixtureMatch(context, ref, tournament, item.fixture);
  }
  if (context.mounted) ref.invalidate(matchListProvider);
}

/// Every knockout game, round by round, with the teams known so far and who
/// went through. A game that is set up opens like it does on Matches.
class _BracketTab extends ConsumerWidget {
  const _BracketTab({required this.progress, required this.watching});

  final TournamentProgress progress;
  final bool watching;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournament = progress.tournament;
    final rounds = <String, List<BracketGame>>{};
    for (final game in tournament.bracket) {
      (rounds[game.round] ??= []).add(game);
    }
    final opening = tournament.bracket.first.round;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        for (final MapEntry(key: round, value: games) in rounds.entries) ...[
          SectionTitle(_roundTitle(round, games.length)),
          const SizedBox(height: 10),
          for (final game in games) ...[
            _BracketGameCard(
              game: game,
              progress: progress,
              // In a cup, a team drawn straight into a later round had a bye.
              byeRound: tournament.isKnockout && round != opening,
              watching: watching,
              onOpen: (item) => _openFixture(context, ref, tournament, item, watching: watching),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _BracketGameCard extends StatelessWidget {
  const _BracketGameCard({
    required this.game,
    required this.progress,
    required this.byeRound,
    required this.onOpen,
    this.watching = false,
  });

  final BracketGame game;
  final TournamentProgress progress;
  final bool byeRound;
  final bool watching;
  final ValueChanged<FixtureProgress> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final tournament = progress.tournament;
    final item = progress.fixtures.where((f) => f.fixture.id == game.id).firstOrNull;
    final (teamA, teamB) = progress.bracketTeams[game.id] ?? (null, null);
    final winner = progress.winners[game.id];
    final match = item?.match;
    final date = item?.fixture.scheduledAt;
    final status = switch (item) {
      null when teamA != null && teamB != null => watching ? 'Teams known' : 'Ready: set up on Matches',
      null => null,
      _ when winner != null => null,
      _ when match == null => date == null ? (watching ? 'Not started' : 'Tap to start') : fixtureDate(date),
      _ when item.isFinished => 'Super Over to come',
      _ => 'Live',
    };
    final isFinal = game.id == finalFixtureId;

    Widget side(BracketSide from, String? teamId) {
      final known = teamId != null;
      final won = known && winner == teamId;
      final lost = known && winner != null && !won;
      final name = known ? tournament.teamById(teamId).name : tournament.sideName(from);
      return Row(
        children: [
          if (known)
            TeamBadge(name: name, size: 28)
          else
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant),
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyLarge?.copyWith(
                fontWeight: won ? FontWeight.w800 : FontWeight.w600,
                fontStyle: known ? null : FontStyle.italic,
                color: won ? scheme.primary : (known && !lost ? null : scheme.onSurfaceVariant),
              ),
            ),
          ),
          if (byeRound && from is DrawnTeam) ...[
            const SizedBox(width: 8),
            Text('bye', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          if (won) ...[
            const SizedBox(width: 8),
            Icon(
              isFinal ? Icons.emoji_events_rounded : Icons.check_circle_rounded,
              size: 20,
              color: isFinal ? AppColors.four : scheme.primary,
            ),
          ],
        ],
      );
    }

    return SurfacePanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: item == null ? null : () => onOpen(item),
        child: Container(
          decoration: isFinal
              ? const BoxDecoration(border: Border(left: BorderSide(color: AppColors.four, width: 4)))
              : null,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: SectionLabel(game.label)),
                  if (status != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(
                          color: status == 'Live' ? scheme.primary : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              side(game.a, teamA),
              const SizedBox(height: 8),
              side(game.b, teamB),
            ],
          ),
        ),
      ),
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
  const _ChampionBanner({required this.name, this.bestPlayer, this.prize});

  final String name;
  final String? bestPlayer;

  /// The first prize, which is the winner's.
  final String? prize;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.four.withValues(alpha: 0.45)),
          boxShadow: AppColors.glow(AppColors.four, strength: 0.18, blur: 24),
        ),
        child: Row(
          children: [
            const PopIn(child: Icon(Icons.emoji_events_rounded, size: 44, color: AppColors.four)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CHAMPIONS',
                    style: TextStyle(color: AppColors.four, letterSpacing: 2, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: scoreStyle(26, color: Colors.white),
                  ),
                  if (prize case final prize?) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Wins $prize',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.four, fontWeight: FontWeight.w800),
                    ),
                  ],
                  if (bestPlayer case final player?) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Player of the Tournament: $player',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

class _FixtureCard extends StatelessWidget {
  const _FixtureCard({
    required this.item,
    required this.tournament,
    required this.onTap,
    required this.onLongPress,
    this.watching = false,
  });

  final bool watching;
  final FixtureProgress item;
  final Tournament tournament;
  final VoidCallback onTap;

  /// Sets the time and ground, or sends an invite.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fixture = item.fixture;
    final match = item.match;
    final teamA = tournament.teamById(fixture.teamAId).name;
    final teamB = tournament.teamById(fixture.teamBId).name;
    final date = fixture.scheduledAt;
    final when = [if (date != null) fixtureDate(date), ?fixture.venue].join(' · ');

    return SurfacePanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: SectionLabel(fixture.label)),
                  if (when.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        when,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$teamA v $teamB',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                match == null ? (watching ? 'Not started' : 'Tap to start') : matchStatus(match),
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
