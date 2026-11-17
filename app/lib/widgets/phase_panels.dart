import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import 'player_choice_grid.dart';
import 'surface_panel.dart';

/// Title + prompt used by every phase panel.
class PanelHeading extends StatelessWidget {
  const PanelHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleLarge),
          if (subtitle != null)
            Text(
              subtitle!,
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Tap the striker, then the non-striker.
class OpenersPanel extends StatefulWidget {
  const OpenersPanel({
    super.key,
    required this.team,
    required this.onConfirm,
    this.title = 'Opening batters',
  });

  final Team team;
  final String title;
  final void Function(String strikerId, String nonStrikerId) onConfirm;

  @override
  State<OpenersPanel> createState() => _OpenersPanelState();
}

class _OpenersPanelState extends State<OpenersPanel> {
  String? _striker;
  String? _nonStriker;

  void _tap(Player p) => setState(() {
        if (p.id == _striker) {
          _striker = null;
        } else if (p.id == _nonStriker) {
          _nonStriker = null;
        } else if (_striker == null) {
          _striker = p.id;
        } else {
          _nonStriker = p.id;
        }
      });

  @override
  Widget build(BuildContext context) {
    final striker = _striker;
    final nonStriker = _nonStriker;
    final prompt = striker == null
        ? 'Tap the batter on strike'
        : nonStriker == null
            ? 'Now tap the non-striker'
            : 'Ready when you are';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeading(title: widget.title, subtitle: '${widget.team.name} · $prompt'),
        PlayerChoiceGrid(
          players: widget.team.players,
          selectedIds: {?striker, ?nonStriker},
          subtitles: {?striker: 'Striker', ?nonStriker: 'Non-striker'},
          onSelected: _tap,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: striker != null && nonStriker != null
              ? () => widget.onConfirm(striker, nonStriker)
              : null,
          child: const Text('Start innings'),
        ),
      ],
    );
  }
}

/// Pick the bowler. Ineligible bowlers are shown greyed out with a reason, and
/// a note explains any rule the engine set aside so someone can bowl.
class BowlerPanel extends StatelessWidget {
  const BowlerPanel({
    super.key,
    required this.state,
    required this.onSelected,
    this.title,
  });

  final MatchState state;
  final ValueChanged<String> onSelected;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final inn = state.current;
    final team = state.setup.teamById(inn.bowlingTeamId);
    final eligible = inn.eligibleBowlerIds.toSet();
    final relaxation = inn.bowlingRelaxation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeading(
          title: title ?? 'Over ${inn.completedOvers.length + 1}',
          subtitle: 'Who is bowling?',
        ),
        if (relaxation != BowlingRelaxation.none) ...[
          NoticeBanner(
            icon: Icons.rule_rounded,
            text: relaxation.message,
            background: AppColors.extra,
            foreground: Colors.white,
          ),
          const SizedBox(height: 12),
        ],
        PlayerChoiceGrid(
          players: team.players,
          disabledIds: {
            for (final p in team.players)
              if (!eligible.contains(p.id)) p.id,
          },
          subtitles: {
            for (final f in inn.bowlers) f.playerId: figures(f, inn.ballsPerOver),
            // Why a greyed-out bowler cannot bowl, in place of their figures.
            ...inn.bowlerBlockReasons,
          },
          onSelected: (p) => onSelected(p.id),
        ),
      ],
    );
  }
}

class BatterPanel extends StatelessWidget {
  const BatterPanel({super.key, required this.state, required this.onSelected});

  final MatchState state;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final inn = state.current;
    final team = state.setup.teamById(inn.battingTeamId);
    final available = inn.availableBatterIds.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeading(
          title: 'Next batter',
          subtitle: '${team.name} · ${inn.wickets} down',
        ),
        PlayerChoiceGrid(
          players: [
            for (final p in team.players)
              if (available.contains(p.id)) p,
          ],
          subtitles: {
            for (final b in inn.batters)
              if (b.isRetiredHurt) b.playerId: 'Retired hurt · ${b.runs} (${b.balls})',
          },
          onSelected: (p) => onSelected(p.id),
        ),
      ],
    );
  }
}

/// Between innings: first-innings summary, then the chasing openers.
class InningsBreakPanel extends StatelessWidget {
  const InningsBreakPanel({super.key, required this.state, required this.onOpeners});

  final MatchState state;
  final void Function(String strikerId, String nonStrikerId) onOpeners;

  @override
  Widget build(BuildContext context) {
    final first = state.innings.first;
    final chasing = state.setup.teamById(first.bowlingTeamId);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.neon.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.neon.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(Icons.flag_rounded, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Innings break · ${chasing.name} need ${first.runs + 1} '
                  'from ${first.maxOversText} overs',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        OpenersPanel(
          team: chasing,
          title: 'Chase openers',
          onConfirm: onOpeners,
        ),
      ],
    );
  }
}
