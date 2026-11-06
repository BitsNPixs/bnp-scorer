import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'surface_panel.dart';

const _overPresets = [5, 6, 8, 10, 12, 15, 20];
const _maxOvers = 50;

/// Overs per innings, by stepper or preset.
class OversPicker extends StatelessWidget {
  const OversPicker({super.key, required this.overs, required this.onChanged});

  final int overs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SurfacePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Overs per innings'),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: overs > 1 ? () => onChanged(overs - 1) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Expanded(
                  child: Text(
                    '$overs',
                    textAlign: TextAlign.center,
                    style: scoreStyle(40, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: overs < _maxOvers ? () => onChanged(overs + 1) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in _overPresets)
                  ChoiceChip(
                    label: Text('$o'),
                    selected: overs == o,
                    onSelected: (_) => onChanged(o),
                  ),
              ],
            ),
          ],
        ),
      );
}
