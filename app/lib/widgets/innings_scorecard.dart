import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import 'result_hero.dart';
import 'surface_panel.dart';

/// One innings of the scorecard: the match summary, batting, the fall of
/// wickets and bowling.
class InningsScorecard extends StatelessWidget {
  const InningsScorecard({super.key, required this.state, required this.innings});

  final MatchState state;
  final InningsState innings;

  @override
  Widget build(BuildContext context) {
    final setup = state.setup;
    final inn = innings;
    final sections = <Widget>[
      ResultHero(state: state, focusInnings: inn.number),
      _BattingCard(setup: setup, innings: inn),
      if (inn.fallOfWickets.isNotEmpty) _WicketTimeline(setup: setup, innings: inn),
      if (inn.bowlers.isNotEmpty) _BowlingCard(setup: setup, innings: inn),
    ];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => EntranceFade(index: i, child: sections[i]),
    );
  }
}

/// Column widths, each sized to its widest real value, so the name column
/// keeps the rest: R, B, 4s, 6s, SR and O, M, R, W, Econ.
const _battingWidths = [40.0, 34.0, 34.0, 34.0, 46.0];
const _bowlingWidths = [36.0, 30.0, 36.0, 34.0, 44.0];

/// Table cards use a little less padding than other panels, for the same reason.
const _tablePadding = EdgeInsets.fromLTRB(14, 16, 14, 16);

/// Inner padding of bowling rows, which can carry a highlight.
const _rowInset = 8.0;

/// The highest score in the innings, which sets the length of every run bar.
int _topRuns(InningsState inn) => inn.batters.fold(0, (top, b) => b.runs > top ? b.runs : top);

class _BattingCard extends StatelessWidget {
  const _BattingCard({required this.setup, required this.innings});

  final MatchSetup setup;
  final InningsState innings;

  @override
  Widget build(BuildContext context) {
    final inn = innings;
    final scheme = Theme.of(context).colorScheme;
    final top = _topRuns(inn);
    final batted = {for (final b in inn.batters) b.playerId};
    final yetToBat = [
      for (final p in setup.teamById(inn.battingTeamId).players)
        if (!batted.contains(p.id)) p.name,
    ];
    final e = inn.extras;
    final extras = [
      if (e.wides > 0) ('wd', e.wides),
      if (e.noBalls > 0) ('nb', e.noBalls),
      if (e.byes > 0) ('b', e.byes),
      if (e.legByes > 0) ('lb', e.legByes),
    ];

    return SurfacePanel(
      padding: _tablePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            'Batting',
            trailing: Text(
              setup.teamById(inn.battingTeamId).name,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 10),
          const _TableHeader(first: 'Batter', columns: ['R', 'B', '4s', '6s', 'SR'], widths: _battingWidths),
          for (final b in inn.batters)
            _BatterRow(
              setup: setup,
              batter: b,
              atCrease: b.playerId == inn.strikerId || b.playerId == inn.nonStrikerId,
              topRuns: top,
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Extras', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Expanded(
                child: extras.isEmpty
                    ? Text(
                        'None',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (label, count) in extras) _MiniChip('$label $count', color: AppColors.extra),
                        ],
                      ),
              ),
              Text('${e.total}', style: scoreStyle(18, color: scheme.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          _TotalBand(innings: inn),
          if (yetToBat.isNotEmpty) ...[
            const SizedBox(height: 14),
            const SectionLabel('Yet to bat'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final name in yetToBat) _MiniChip(name)],
            ),
          ],
        ],
      ),
    );
  }
}

class _BatterRow extends StatelessWidget {
  const _BatterRow({required this.setup, required this.batter, required this.atCrease, required this.topRuns});

  final MatchSetup setup;
  final BatterScore batter;
  final bool atCrease;
  final int topRuns;

  @override
  Widget build(BuildContext context) {
    final b = batter;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final notOut = b.dismissal == null;
    final isTop = topRuns > 0 && b.runs == topRuns;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      taggedPlayerName(setup, b.playerId),
                      style: text.bodyMedium?.copyWith(fontWeight: atCrease || isTop ? FontWeight.w800 : FontWeight.w600),
                    ),
                    Text(
                      dismissalText(setup, b),
                      style: text.bodySmall?.copyWith(
                        color: notOut ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: notOut ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              _Cell(
                notOut ? '${b.runs}*' : '${b.runs}',
                width: _battingWidths[0],
                size: 18,
                weight: FontWeight.w800,
                color: isTop ? scheme.primary : null,
              ),
              _Cell('${b.balls}', width: _battingWidths[1]),
              _BadgeCell(b.fours, width: _battingWidths[2], color: AppColors.four),
              _BadgeCell(b.sixes, width: _battingWidths[3], color: AppColors.six),
              _Cell(b.strikeRate.toStringAsFixed(1), width: _battingWidths[4]),
            ],
          ),
          if (b.runs > 0) ...[
            const SizedBox(height: 6),
            _RunBar(share: b.runs / topRuns, lit: isTop),
          ],
        ],
      ),
    );
  }
}

/// A thin bar under a batter, its length their runs against the top score.
class _RunBar extends StatelessWidget {
  const _RunBar({required this.share, required this.lit});

  final double share;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 4,
        alignment: Alignment.centerLeft,
        color: scheme.surfaceContainerHigh,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduceMotion(context) ? share : 0, end: share.clamp(0, 1)),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: lit ? AppColors.neonGradient : null,
                color: lit ? null : scheme.primary.withValues(alpha: 0.35),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

/// The innings total on a floodlit band, so it is the first number seen.
class _TotalBand extends StatelessWidget {
  const _TotalBand({required this.innings});

  final InningsState innings;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.neon.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(
                      color: AppColors.neon,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${innings.oversText} ov · RR ${innings.runRate.toStringAsFixed(2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Text(scoreLine(innings), style: scoreStyle(34, color: Colors.white, weight: FontWeight.w800)),
          ],
        ),
      );
}

/// Each wicket as a red marker on a line, in the order they fell.
class _WicketTimeline extends StatelessWidget {
  const _WicketTimeline({required this.setup, required this.innings});

  final MatchSetup setup;
  final InningsState innings;

  static const nodeWidth = 104.0;

  @override
  Widget build(BuildContext context) {
    final inn = innings;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final wickets = inn.fallOfWickets;
    return SurfacePanel(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Fall of wickets'),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < wickets.length; i++)
                  SizedBox(
                    width: nodeWidth,
                    child: Column(
                      children: [
                        Text('${wickets[i].runs}-${wickets[i].wicketNumber}',
                            style: scoreStyle(20, color: scheme.onSurface, weight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 16,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // The line runs between markers, not past the ends.
                              Row(
                                children: [
                                  Expanded(child: _line(scheme, visible: i > 0)),
                                  Expanded(child: _line(scheme, visible: i < wickets.length - 1)),
                                ],
                              ),
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: AppColors.wicket,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: scheme.surfaceContainerLowest, width: 2.5),
                                  boxShadow: AppColors.glow(AppColors.wicket, strength: 0.35, blur: 8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            playerName(setup, wickets[i].batterId),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '${formatOvers(wickets[i].legalBalls, inn.ballsPerOver)} ov',
                          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(ColorScheme scheme, {required bool visible}) =>
      Container(height: 2, color: visible ? AppColors.wicket.withValues(alpha: 0.4) : Colors.transparent);
}

class _BowlingCard extends StatelessWidget {
  const _BowlingCard({required this.setup, required this.innings});

  final MatchSetup setup;
  final InningsState innings;

  /// Most wickets, then fewest runs. Null until someone has a wicket.
  String? get _bestId {
    BowlerFigures? best;
    for (final f in innings.bowlers) {
      if (f.wickets == 0) continue;
      if (best == null || f.wickets > best.wickets || (f.wickets == best.wickets && f.runs < best.runs)) best = f;
    }
    return best?.playerId;
  }

  @override
  Widget build(BuildContext context) {
    final inn = innings;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final bestId = _bestId;
    return SurfacePanel(
      padding: _tablePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            'Bowling',
            trailing: Text(
              setup.teamById(inn.bowlingTeamId).name,
              style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 10),
          const _TableHeader(
            first: 'Bowler',
            columns: ['O', 'M', 'R', 'W', 'Econ'],
            widths: _bowlingWidths,
            inset: _rowInset,
          ),
          for (final f in inn.bowlers)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: _rowInset),
              decoration: BoxDecoration(
                color: f.playerId == bestId ? scheme.primary.withValues(alpha: 0.10) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: f.playerId == bestId ? Border.all(color: scheme.primary.withValues(alpha: 0.35)) : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playerName(setup, f.playerId),
                          style: text.bodyMedium?.copyWith(
                            fontWeight: f.playerId == bestId || f.playerId == inn.bowlerId
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                        if (f.playerId == bestId)
                          Text(
                            'Best figures',
                            style: text.bodySmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
                          )
                        else if (f.wides + f.noBalls > 0)
                          Text(
                            'wd ${f.wides} · nb ${f.noBalls}',
                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  _Cell(f.overs(inn.ballsPerOver), width: _bowlingWidths[0]),
                  _Cell('${f.maidens}', width: _bowlingWidths[1]),
                  _Cell('${f.runs}', width: _bowlingWidths[2]),
                  _BadgeCell(f.wickets, width: _bowlingWidths[3], color: AppColors.wicket, size: 16),
                  _Cell(f.economy(inn.ballsPerOver).toStringAsFixed(1), width: _bowlingWidths[4]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.first, required this.columns, required this.widths, this.inset = 0});

  final String first;
  final List<String> columns;
  final List<double> widths;

  /// Matches rows that are padded inside a highlight, so columns line up.
  final double inset;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        );
    return Container(
      padding: EdgeInsets.fromLTRB(inset, 0, inset, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(first.toUpperCase(), style: style)),
          for (var i = 0; i < columns.length; i++)
            SizedBox(width: widths[i], child: Text(columns[i], textAlign: TextAlign.end, style: style)),
        ],
      ),
    );
  }
}

/// A right-aligned number in a table column.
class _Cell extends StatelessWidget {
  const _Cell(this.value, {required this.width, this.size = 15, this.weight = FontWeight.w600, this.color});

  final String value;
  final double width;
  final double size;
  final FontWeight weight;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Text(
          value,
          textAlign: TextAlign.end,
          maxLines: 1,
          style: scoreStyle(size, color: color ?? Theme.of(context).colorScheme.onSurface, weight: weight),
        ),
      );
}

/// A count that stands out when it is not zero: boundaries and wickets.
class _BadgeCell extends StatelessWidget {
  const _BadgeCell(this.count, {required this.width, required this.color, this.size = 15});

  final int count;
  final double width;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (count == 0) {
      return _Cell('0', width: width, size: size, weight: FontWeight.w500, color: scheme.onSurfaceVariant);
    }
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(minWidth: 26),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            maxLines: 1,
            style: scoreStyle(size, color: scheme.onSurface, weight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

/// A small rounded label: an extras count or a name still to bat.
class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label, {this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tint == null ? scheme.surfaceContainer : tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
