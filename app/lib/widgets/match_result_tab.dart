import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import 'avatars.dart';
import 'result_hero.dart';
import 'surface_panel.dart';

/// The first tab of a finished match: the result, the stars of the match, and
/// a way into each of the other tabs. Everything here is tappable.
class MatchResultTab extends StatelessWidget {
  const MatchResultTab({
    super.key,
    required this.state,
    required this.onInnings,
    required this.onOvers,
    required this.onCharts,
  });

  final MatchState state;

  /// Opens the scorecard of the innings at this index in [MatchState.innings].
  final ValueChanged<int> onInnings;
  final VoidCallback onOvers;
  final VoidCallback onCharts;

  @override
  Widget build(BuildContext context) {
    final batting = _topBatter(state);
    final bowling = _bestBowler(state);
    final sections = <Widget>[
      ResultHero(state: state, onInningsTap: onInnings),
      if (batting != null || bowling != null) ...[
        const SectionTitle('Stars of the match'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (batting != null)
              Expanded(
                child: _StarCard(
                  label: 'TOP BATTER',
                  icon: Icons.sports_cricket_rounded,
                  color: AppColors.four,
                  name: playerName(state.setup, batting.score.playerId),
                  team: state.setup.teamById(state.innings[batting.innings].battingTeamId).name,
                  figure: '${batting.score.runs}${batting.score.dismissal == null ? '*' : ''}',
                  detail: '${plural(batting.score.balls, 'ball')} · ${batting.score.fours}×4 ${batting.score.sixes}×6',
                  onTap: () => onInnings(batting.innings),
                ),
              ),
            if (batting != null && bowling != null) const SizedBox(width: 12),
            if (bowling != null)
              Expanded(
                child: _StarCard(
                  label: 'BEST BOWLER',
                  icon: Icons.sports_baseball_rounded,
                  color: AppColors.wicket,
                  name: playerName(state.setup, bowling.figures.playerId),
                  team: state.setup.teamById(state.innings[bowling.innings].bowlingTeamId).name,
                  figure: '${bowling.figures.wickets}/${bowling.figures.runs}',
                  detail: '${bowling.figures.overs(state.innings[bowling.innings].ballsPerOver)} overs',
                  onTap: () => onInnings(bowling.innings),
                ),
              ),
          ],
        ),
      ],
      const SectionTitle('Dig deeper'),
      Row(
        children: [
          Expanded(
            child: _JumpTile(
              icon: Icons.table_chart_rounded,
              title: 'Scorecard',
              subtitle: 'Bat & ball',
              onTap: () => onInnings(0),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _JumpTile(icon: Icons.timeline_rounded, title: 'Overs', subtitle: 'Every ball', onTap: onOvers),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _JumpTile(icon: Icons.insights_rounded, title: 'Charts', subtitle: 'Runs & race', onTap: onCharts),
          ),
        ],
      ),
    ];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: sections.length,
      separatorBuilder: (_, i) => SizedBox(height: sections[i] is SectionTitle ? 10 : 18),
      itemBuilder: (_, i) => EntranceFade(index: i, child: sections[i]),
    );
  }
}

/// Most runs in the match, then fewest balls. Null before anyone scores.
({int innings, BatterScore score})? _topBatter(MatchState state) {
  ({int innings, BatterScore score})? best;
  for (final (i, inn) in state.innings.indexed) {
    for (final b in inn.batters) {
      if (b.runs == 0) continue;
      final current = best?.score;
      if (current == null || b.runs > current.runs || (b.runs == current.runs && b.balls < current.balls)) {
        best = (innings: i, score: b);
      }
    }
  }
  return best;
}

/// Most wickets in the match, then fewest runs. Null until a wicket falls to a bowler.
({int innings, BowlerFigures figures})? _bestBowler(MatchState state) {
  ({int innings, BowlerFigures figures})? best;
  for (final (i, inn) in state.innings.indexed) {
    for (final f in inn.bowlers) {
      if (f.wickets == 0) continue;
      final current = best?.figures;
      if (current == null || f.wickets > current.wickets || (f.wickets == current.wickets && f.runs < current.runs)) {
        best = (innings: i, figures: f);
      }
    }
  }
  return best;
}

class _StarCard extends StatelessWidget {
  const _StarCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.name,
    required this.team,
    required this.figure,
    required this.detail,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String name;
  final String team;
  final String figure;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: cardShape(context, radius: 22, accent: color.withValues(alpha: 0.45)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -18,
              top: -18,
              child: Icon(icon, size: 84, color: color.withValues(alpha: 0.10)),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 14, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PlayerAvatar(name: name, radius: 20),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
                  ),
                  Text(
                    team,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(figure, style: scoreStyle(34, color: scheme.onSurface, weight: FontWeight.w800)),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                    ],
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
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

/// A square shortcut into another tab.
class _JumpTile extends StatelessWidget {
  const _JumpTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: cardShape(context, radius: 20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: scheme.primary),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
