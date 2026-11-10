import 'package:flutter/material.dart';

/// The card shape every surface shares: rounded, with a hairline edge that
/// gives the dark theme its glassy look. [accent] draws the edge in that
/// colour instead, e.g. neon for a live match.
ShapeBorder cardShape(BuildContext context, {double radius = 24, Color? accent}) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        color: accent ?? Theme.of(context).colorScheme.outlineVariant,
        width: accent == null ? 1 : 1.5,
      ),
    );

/// Rounded card surface shared by the scoring, setup and scorecard screens.
class SurfacePanel extends StatelessWidget {
  const SurfacePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        // A Material (not a decorated Container) so ink splashes from list
        // tiles and buttons inside the panel are visible.
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          shape: cardShape(context),
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: padding, child: child),
        ),
      );
}

/// A section heading in the scoreboard face, with an optional action on the
/// right, e.g. "Matches" above the match list.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          ?trailing,
        ],
      );
}

/// Small caps section label, e.g. "OVER 4".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
      );
}
