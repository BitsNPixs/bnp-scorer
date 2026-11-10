import 'dart:math' as math;

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import '../widgets/app_bottom_bar.dart';
import '../widgets/avatars.dart';
import '../widgets/score_header.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/stadium_effects.dart';
import '../widgets/surface_panel.dart';
import 'new_match_screen.dart';
import 'scoring_screen.dart';
import 'stats_screen.dart';
import 'teams_screen.dart';
import 'tournaments_screen.dart';

const _allMatches = 'all';
const _friendlies = 'friendlies';

const _tabs = <BottomBarItem>[
  (icon: Icons.sports_cricket_outlined, selectedIcon: Icons.sports_cricket_rounded, label: 'Matches'),
  (icon: Icons.emoji_events_outlined, selectedIcon: Icons.emoji_events_rounded, label: 'Tournaments'),
  (icon: Icons.leaderboard_outlined, selectedIcon: Icons.leaderboard_rounded, label: 'Stats'),
  (icon: Icons.groups_outlined, selectedIcon: Icons.groups_rounded, label: 'Teams'),
];

/// The app's home: matches, tournaments, stats and teams behind a bottom bar,
/// with "new match" one tap away on every tab.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  /// Tabs are built on first visit, then kept, so each keeps its scroll
  /// position and nothing is loaded before it is wanted.
  final _visited = <int>{0};

  void _select(int tab) => setState(() {
    _tab = tab;
    _visited.add(tab);
  });

  Future<void> _newMatch() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NewMatchScreen()));
    if (!mounted) return;
    ref.invalidate(matchListProvider);
    _select(0);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      MatchesTab(onNewMatch: _newMatch),
      const TournamentsScreen(),
      const StatsScreen(),
      const TeamsScreen(),
    ];
    return PopScope(
      // Back goes to Matches first, then leaves the app.
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            for (var i = 0; i < pages.length; i++)
              _TabPage(active: i == _tab, child: _visited.contains(i) ? pages[i] : const SizedBox.shrink()),
          ],
        ),
        bottomNavigationBar: AppBottomBar(items: _tabs, selected: _tab, onSelected: _select, onCreate: _newMatch),
      ),
    );
  }
}

/// Fades a tab in each time it is chosen, without rebuilding what is inside.
class _TabPage extends StatefulWidget {
  const _TabPage({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 240), value: 1);

  @override
  void didUpdateWidget(_TabPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !reduceMotion(context)) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return TickerMode(
      enabled: widget.active,
      child: FadeTransition(
        opacity: curve,
        child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(curve), child: widget.child),
      ),
    );
  }
}

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
                    child: _SummaryTiles(matches: list, tournamentCount: tournaments.length),
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
          child: _MatchCard(summary: matches[i], tournamentName: tournamentNames[matches[i].record.id]),
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
          const Positioned(right: 6, bottom: 0, child: _StumpsArt()),
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

/// Stumps under floodlight, with a ball that rolls in when Home opens.
class _StumpsArt extends StatelessWidget {
  const _StumpsArt();

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: reduceMotion(context) ? 1 : 0, end: 1),
    duration: const Duration(milliseconds: 1100),
    curve: Curves.easeOutCubic,
    builder: (context, t, _) => CustomPaint(size: const Size(110, 150), painter: _StumpsPainter(t)),
  );
}

class _StumpsPainter extends CustomPainter {
  const _StumpsPainter(this.roll);

  /// 0 when the ball is off to the right, 1 when it rests by the stumps.
  final double roll;

  @override
  void paint(Canvas canvas, Size size) {
    final ground = size.height - 18;
    final glowRect = Rect.fromCircle(center: Offset(size.width * 0.6, ground), radius: 70);
    canvas.drawCircle(
      glowRect.center,
      70,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.neon.withValues(alpha: 0.30), AppColors.neon.withValues(alpha: 0)],
        ).createShader(glowRect),
    );
    canvas.drawLine(
      Offset(8, ground),
      Offset(size.width, ground),
      Paint()
        ..color = AppColors.neon.withValues(alpha: 0.5)
        ..strokeWidth = 2,
    );

    final stump = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Color(0xFFB9CFC4)],
      ).createShader(Rect.fromLTWH(0, ground - 86, size.width, 86));
    const stumpWidth = 7.0;
    final left = size.width * 0.6 - 18;
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(left + i * 15, ground - 84, stumpWidth, 84), const Radius.circular(3)),
        stump,
      );
    }
    final bail = Paint()..color = Colors.white;
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left - 1, ground - 90, 17, 4), const Radius.circular(2)), bail)
      ..drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(left + 15, ground - 90, 17, 4), const Radius.circular(2)),
        bail,
      );

    const radius = 12.0;
    final ball = Offset(left - 20 + (1 - roll) * 110, ground - radius - 1);
    final ballRect = Rect.fromCircle(center: ball, radius: radius);
    canvas.drawCircle(
      ball,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [Color(0xFFFF6B6B), Color(0xFFB3132B)],
        ).createShader(ballRect),
    );
    canvas
      ..save()
      ..translate(ball.dx, ball.dy)
      ..rotate(-(1 - roll) * math.pi * 4);
    final seam = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas
      ..drawArc(Rect.fromCircle(center: const Offset(-9, 0), radius: 9), -0.9, 1.8, false, seam)
      ..drawArc(Rect.fromCircle(center: const Offset(9, 0), radius: 9), math.pi - 0.9, 1.8, false, seam)
      ..restore();
  }

  @override
  bool shouldRepaint(_StumpsPainter old) => old.roll != roll;
}

/// Three glassy number tiles: played, live and tournaments.
class _SummaryTiles extends StatelessWidget {
  const _SummaryTiles({required this.matches, required this.tournamentCount});

  final List<MatchSummary> matches;
  final int tournamentCount;

  @override
  Widget build(BuildContext context) {
    final finished = matches.where((m) => m.state.isCompleted).length;
    final tiles = [
      (Icons.check_circle_rounded, '$finished', 'Played', AppColors.neonDeep),
      (Icons.sensors_rounded, '${matches.length - finished}', 'Live', AppColors.live),
      (Icons.emoji_events_rounded, '$tournamentCount', 'Tournaments', AppColors.four),
    ];
    return Row(
      children: [
        for (final (i, (icon, value, label, color)) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: EntranceFade(
              index: i + 1,
              child: _SummaryTile(icon: icon, value: value, label: label, color: color),
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.icon, required this.value, required this.label, required this.color});

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: cardShape(context, radius: 20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, maxLines: 1, style: scoreStyle(22, color: scheme.onSurface)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
              child: const Center(child: _StumpsArt()),
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

class _MatchCard extends ConsumerWidget {
  const _MatchCard({required this.summary, this.tournamentName});

  final MatchSummary summary;
  final String? tournamentName;

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
        onTap: () => _open(context, ref),
        onLongPress: () => _confirmDelete(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (live) const LivePill(onDark: false) else _Tag(label: 'RESULT', color: scheme.primary),
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
class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2),
    ),
  );
}

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
