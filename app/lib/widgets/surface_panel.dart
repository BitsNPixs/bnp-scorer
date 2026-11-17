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

/// A coloured strip with an icon and a line or two of text: a failed save, a
/// free hit, a rule set aside.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
              ),
            ),
          ],
        ),
      );
}
