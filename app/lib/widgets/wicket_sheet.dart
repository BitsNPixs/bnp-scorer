import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/format.dart';
import 'player_choice_grid.dart';
import 'scoring_sheets.dart';
import 'surface_panel.dart';

class WicketInput {
  const WicketInput({
    required this.type,
    required this.delivery,
    required this.batterOutId,
    required this.runs,
    this.fielderId,
    this.end,
  });

  final DismissalType type;

  /// Legal ball, wide, no-ball, bye or leg bye.
  final ExtraType delivery;
  final String batterOutId;

  /// Runs completed before the dismissal (run outs only).
  final int runs;
  final String? fielderId;

  /// Run outs: where the wicket was put down.
  final CreaseEnd? end;

  Wicket get wicket => Wicket(type: type, batterOutId: batterOutId, fielderId: fielderId, end: end);

  bool get _runsOffBat => delivery == ExtraType.none || delivery == ExtraType.noBall;

  /// Runs off the bat; on a wide, bye or leg bye, completed runs are extras.
  int get runsOffBat => _runsOffBat ? runs : 0;
  int get extraRuns => _runsOffBat ? 0 : runs;
}

const _deliveries = {
  ExtraType.none: 'Legal',
  ExtraType.wide: 'Wide',
  ExtraType.noBall: 'No-ball',
  ExtraType.bye: 'Bye',
  ExtraType.legBye: 'Leg bye',
};

/// [preview] returns the match as it would be after the wicket, or null if
/// it is not allowed; the sheet uses it to say who faces next.
Future<WicketInput?> showWicketSheet(
  BuildContext context,
  MatchState state, {
  required MatchState? Function(WicketInput input) preview,
}) =>
    showModalBottomSheet<WicketInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _WicketSheet(state: state, preview: preview),
    );

const _fielderTypes = {
  DismissalType.caught,
  DismissalType.runOut,
  DismissalType.stumped,
};

class _WicketSheet extends StatefulWidget {
  const _WicketSheet({required this.state, required this.preview});

  final MatchState state;
  final MatchState? Function(WicketInput input) preview;

  @override
  State<_WicketSheet> createState() => _WicketSheetState();
}

class _WicketSheetState extends State<_WicketSheet> {
  ExtraType _delivery = ExtraType.none;
  DismissalType? _type;
  late String _outId = widget.state.current.strikerId!;
  int _runs = 0;
  String? _fielderId;

  /// Set once the scorer picks an end; until then it follows [_likelyEnd].
  CreaseEnd? _end;

  /// Most run outs happen at the end the batter was running to: the far end
  /// from where they stood after the runs completed.
  CreaseEnd _likelyEnd(InningsState inn, String outId, int runs) {
    final atStrikerEnd = (outId == inn.strikerId) != runs.isOdd;
    return atStrikerEnd ? CreaseEnd.bowler : CreaseEnd.striker;
  }

  /// "Next ball: Arun faces", from the engine, or null if the innings ends or
  /// the ball is not allowed.
  String? _nextBall(WicketInput input) {
    final after = widget.preview(input);
    if (after == null || after.phase == MatchPhase.completed || after.current.isComplete) return null;
    final striker = after.current.strikerId;
    return striker == null ? 'Next ball: the new batter faces' : 'Next ball: ${playerName(after.setup, striker)} faces';
  }

  @override
  Widget build(BuildContext context) {
    final inn = widget.state.current;
    final setup = widget.state.setup;
    final allowed = [
      for (final t in DismissalType.values)
        if (allowedDismissals(_delivery, freeHit: inn.isFreeHit).contains(t)) t,
    ];
    final type = allowed.contains(_type) ? _type : null;
    final canPickBatter = type != null && type.canDismissNonStriker && inn.nonStrikerId != null;
    final outId = canPickBatter ? _outId : inn.strikerId!;
    final runsAllowed = type == DismissalType.runOut || type == DismissalType.obstructingTheField;
    // A bye needs a run; a run out with none completed is off a legal ball.
    final byes = _delivery == ExtraType.bye || _delivery == ExtraType.legBye;
    final runOptions = byes ? const [1, 2, 3] : const [0, 1, 2, 3];
    final runs = runOptions.contains(_runs) ? _runs : runOptions.first;
    final runOut = type == DismissalType.runOut;
    final end = runOut ? _end ?? _likelyEnd(inn, outId, runs) : null;
    WicketInput input(DismissalType type) => WicketInput(
          type: type,
          delivery: _delivery,
          batterOutId: outId,
          runs: runsAllowed ? runs : 0,
          fielderId: _fielderTypes.contains(type) ? _fielderId : null,
          end: end,
        );
    final nextBall = type == null ? null : _nextBall(input(type));
    final fielders = setup.teamById(inn.bowlingTeamId).players;

    return SheetBody(
      title: 'Wicket',
      subtitle: inn.isFreeHit ? 'Free hit: only a run out is possible.' : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Delivery'),
          const SizedBox(height: 8),
          OptionChips<ExtraType>(
            options: _deliveries.keys.toList(),
            labelOf: (d) => _deliveries[d]!,
            selected: _delivery,
            color: Theme.of(context).colorScheme.primary,
            onSelected: (d) => setState(() => _delivery = d),
          ),
          const SizedBox(height: 20),
          const SectionLabel('How out'),
          const SizedBox(height: 8),
          OptionChips<DismissalType>(
            options: allowed,
            labelOf: (t) => t.label,
            selected: type,
            color: AppColors.wicket,
            onSelected: (t) => setState(() => _type = t),
          ),
          if (canPickBatter) ...[
            const SizedBox(height: 20),
            const SectionLabel("Who's out"),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: inn.strikerId!,
                  label: Text(playerName(setup, inn.strikerId), overflow: TextOverflow.ellipsis),
                ),
                ButtonSegment(
                  value: inn.nonStrikerId!,
                  label: Text(playerName(setup, inn.nonStrikerId), overflow: TextOverflow.ellipsis),
                ),
              ],
              selected: {outId},
              onSelectionChanged: (s) => setState(() => _outId = s.first),
            ),
          ],
          if (runsAllowed) ...[
            const SizedBox(height: 20),
            const SectionLabel('Runs completed'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                for (final r in runOptions)
                  RoundOption(
                    label: '$r',
                    color: Theme.of(context).colorScheme.primary,
                    selected: runs == r,
                    onTap: () => setState(() => _runs = r),
                  ),
              ],
            ),
          ],
          if (runOut) ...[
            const SizedBox(height: 20),
            const SectionLabel('Run out at'),
            const SizedBox(height: 8),
            OptionChips<CreaseEnd>(
              options: CreaseEnd.values,
              labelOf: (e) => e.label,
              selected: end,
              color: Theme.of(context).colorScheme.primary,
              onSelected: (e) => setState(() => _end = e),
            ),
          ],
          if (nextBall != null) ...[
            const SizedBox(height: 12),
            Text(
              nextBall,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
          if (type != null && _fielderTypes.contains(type)) ...[
            const SizedBox(height: 20),
            SectionLabel(type == DismissalType.stumped ? 'Wicket-keeper (optional)' : 'Fielder (optional)'),
            const SizedBox(height: 8),
            PlayerChoiceGrid(
              players: fielders,
              selectedIds: {?_fielderId},
              onSelected: (p) => setState(
                () => _fielderId = _fielderId == p.id ? null : p.id,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.wicket,
              foregroundColor: Colors.white,
            ),
            onPressed: type == null
                ? null
                : () => Navigator.of(context).pop(input(type)),
            child: Text(type == null ? 'Choose how they were out' : 'Confirm wicket'),
          ),
        ],
      ),
    );
  }
}
