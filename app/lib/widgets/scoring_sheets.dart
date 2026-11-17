import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Asks "how many runs?" with big round buttons. Returns null if dismissed.
Future<int?> showRunsSheet(
  BuildContext context, {
  required String title,
  required List<int> options,
  String? subtitle,
  Color color = AppColors.extra,
}) =>
    showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SheetBody(
        title: title,
        subtitle: subtitle,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final o in options)
              RoundOption(
                label: '$o',
                color: color,
                onTap: () => Navigator.of(context).pop(o),
              ),
          ],
        ),
      ),
    );

/// Asks where a shot went. Returns null when skipped or dismissed.
Future<ShotZone?> showShotSheet(BuildContext context) => showModalBottomSheet<ShotZone>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        Widget option(ShotZone zone) => Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: OutlinedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(zone),
                  child: Text(zone.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            );
        Widget row(ShotZone offSide, ShotZone legSide) =>
            Row(children: [option(offSide), option(legSide)]);
        return SheetBody(
          title: 'Where did it go?',
          subtitle: 'Off side on the left, leg side on the right.',
          child: Column(
            children: [
              row(ShotZone.thirdMan, ShotZone.fineLeg),
              row(ShotZone.point, ShotZone.squareLeg),
              row(ShotZone.cover, ShotZone.midwicket),
              row(ShotZone.midOff, ShotZone.midOn),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Skip'),
              ),
            ],
          ),
        );
      },
    );

/// Where the runs off a no-ball came from.
enum NoBallRuns {
  bat('Off the bat'),
  byes('Byes'),
  legByes('Leg byes');

  const NoBallRuns(this.label);
  final String label;
}

typedef NoBallInput = ({int runs, NoBallRuns from});

/// No-ball: runs off the bat (default), byes or leg byes.
Future<NoBallInput?> showNoBallSheet(BuildContext context) =>
    showModalBottomSheet<NoBallInput>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => const _NoBallSheet(),
    );

class _NoBallSheet extends StatefulWidget {
  const _NoBallSheet();

  @override
  State<_NoBallSheet> createState() => _NoBallSheetState();
}

class _NoBallSheetState extends State<_NoBallSheet> {
  NoBallRuns _from = NoBallRuns.bat;

  @override
  Widget build(BuildContext context) {
    final options = _from == NoBallRuns.bat ? const [0, 1, 2, 3, 4, 6] : const [1, 2, 3, 4];
    return SheetBody(
      title: 'No-ball',
      subtitle: 'Next ball is a free hit (if enabled). How many runs were scored?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OptionChips<NoBallRuns>(
            options: NoBallRuns.values,
            labelOf: (o) => o.label,
            selected: _from,
            color: AppColors.extra,
            onSelected: (o) => setState(() => _from = o),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final r in options)
                RoundOption(
                  label: '$r',
                  color: AppColors.extra,
                  onTap: () => Navigator.of(context).pop((runs: r, from: _from)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One choice from a few labelled options, as chips that wrap onto a new line
/// instead of clipping on narrow phones or with large text.
class OptionChips<T> extends StatelessWidget {
  const OptionChips({
    super.key,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final List<T> options;
  final String Function(T option) labelOf;
  final T? selected;

  /// Fill of the selected chip.
  final Color color;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : AppColors.night;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(labelOf(o)),
            selected: selected == o,
            selectedColor: color,
            checkmarkColor: onColor,
            labelStyle: TextStyle(
              color: selected == o ? onColor : null,
              fontWeight: FontWeight.w600,
            ),
            onSelected: (_) => onSelected(o),
          ),
      ],
    );
  }
}

/// Common padding and title block for bottom sheets.
class SheetBody extends StatelessWidget {
  const SheetBody({super.key, required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class RoundOption extends StatelessWidget {
  const RoundOption({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool selected;

  /// Text that reads on [color] when selected: white on dark fills, night on
  /// bright ones such as neon.
  Color get _onColor =>
      ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : AppColors.night;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? color : color.withValues(alpha: 0.16),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 64,
            child: Center(
              child: Text(
                label,
                style: scoreStyle(26, color: selected ? _onColor : color),
              ),
            ),
          ),
        ),
      );
}
