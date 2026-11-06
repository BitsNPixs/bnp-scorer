import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import 'avatars.dart';

/// Large, thumb-friendly player pills. Used for openers, bowlers, new
/// batters and fielders so every picker looks and behaves the same.
class PlayerChoiceGrid extends StatelessWidget {
  const PlayerChoiceGrid({
    super.key,
    required this.players,
    required this.onSelected,
    this.selectedIds = const {},
    this.disabledIds = const {},
    this.subtitles = const {},
  });

  final List<Player> players;
  final ValueChanged<Player> onSelected;
  final Set<String> selectedIds;
  final Set<String> disabledIds;

  /// Optional second line per player id (figures, "Striker"...).
  final Map<String, String> subtitles;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final p in players)
            _PlayerPill(
              player: p,
              subtitle: subtitles[p.id],
              selected: selectedIds.contains(p.id),
              enabled: !disabledIds.contains(p.id),
              onTap: () => onSelected(p),
            ),
        ],
      );
}

class _PlayerPill extends StatelessWidget {
  const _PlayerPill({
    required this.player,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Player player;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerLowest,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayerAvatar(name: player.name, radius: 16),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      style: text.labelLarge?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: text.labelSmall?.copyWith(
                          color: fg.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
