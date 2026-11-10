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

typedef NoBallInput = ({int runs, bool byes});

/// No-ball: runs off the bat (default) or byes.
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
  bool _byes = false;

  @override
  Widget build(BuildContext context) {
    final options = _byes ? const [1, 2, 3, 4] : const [0, 1, 2, 3, 4, 6];
    return SheetBody(
      title: 'No-ball',
      subtitle: 'Next ball is a free hit (if enabled). How many runs were scored?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Off the bat')),
              ButtonSegment(value: true, label: Text('Byes')),
            ],
            selected: {_byes},
            onSelectionChanged: (s) => setState(() => _byes = s.first),
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
                  onTap: () => Navigator.of(context).pop((runs: r, byes: _byes)),
                ),
            ],
          ),
        ],
      ),
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
