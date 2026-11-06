import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The ball-by-ball keypad. Every common outcome is one tap; rarer ones
/// (extras with runs, wickets) open a short sheet.
class ScorePad extends StatelessWidget {
  const ScorePad({
    super.key,
    required this.onRuns,
    required this.onMoreRuns,
    required this.onWide,
    required this.onNoBall,
    required this.onBye,
    required this.onLegBye,
    required this.onWicket,
    required this.onUndo,
    required this.canUndo,
  });

  /// Runs off the bat; [boundary] is true for the 4 and 6 keys.
  final void Function(int runs, {required bool boundary}) onRuns;
  final VoidCallback onMoreRuns;
  final VoidCallback onWide;
  final VoidCallback onNoBall;
  final VoidCallback onBye;
  final VoidCallback onLegBye;
  final VoidCallback onWicket;
  final VoidCallback onUndo;
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final neutralBg = scheme.surfaceContainer;
    final neutralFg = scheme.onSurface;

    Widget run(int r) => PadButton(
          label: '$r',
          background: neutralBg,
          foreground: neutralFg,
          onTap: () {
            HapticFeedback.selectionClick();
            onRuns(r, boundary: false);
          },
        );

    Widget extra(String label, VoidCallback onTap) => PadButton(
          label: label,
          small: true,
          background: AppColors.extra.withValues(alpha: 0.14),
          foreground: AppColors.extra,
          onTap: onTap,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row([run(0), run(1), run(2),
          PadButton(
            label: '3',
            caption: 'hold: 5+',
            background: neutralBg,
            foreground: neutralFg,
            onTap: () {
              HapticFeedback.selectionClick();
              onRuns(3, boundary: false);
            },
            onLongPress: onMoreRuns,
          ),
        ]),
        _row([
          PadButton(
            label: '4',
            caption: 'FOUR',
            background: AppColors.four,
            foreground: AppColors.ink,
            onTap: () {
              HapticFeedback.mediumImpact();
              onRuns(4, boundary: true);
            },
          ),
          PadButton(
            label: '6',
            caption: 'SIX',
            background: AppColors.six,
            foreground: Colors.white,
            onTap: () {
              HapticFeedback.heavyImpact();
              onRuns(6, boundary: true);
            },
          ),
          extra('WD', onWide),
          extra('NB', onNoBall),
        ]),
        _row([
          extra('BYE', onBye),
          extra('LB', onLegBye),
          PadButton(
            label: 'OUT',
            small: true,
            background: AppColors.wicket,
            foreground: Colors.white,
            onTap: () {
              HapticFeedback.heavyImpact();
              onWicket();
            },
          ),
          PadButton(
            icon: Icons.undo_rounded,
            label: 'Undo',
            small: true,
            background: neutralBg,
            foreground: canUndo ? neutralFg : neutralFg.withValues(alpha: 0.3),
            onTap: canUndo ? onUndo : null,
          ),
        ]),
      ],
    );
  }

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ],
        ),
      );
}

/// A big key that squishes slightly when pressed.
class PadButton extends StatefulWidget {
  const PadButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.onLongPress,
    this.caption,
    this.icon,
    this.small = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? caption;
  final IconData? icon;

  /// Text keys (WD, OUT...) use a smaller label than digits.
  final bool small;

  @override
  State<PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<PadButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.caption ?? widget.label,
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1,
        duration: const Duration(milliseconds: 90),
        child: Material(
          color: widget.background,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHighlightChanged: enabled ? _setPressed : null,
            child: SizedBox(
              height: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null)
                    Icon(widget.icon, color: widget.foreground)
                  else
                    Text(
                      widget.label,
                      style: scoreStyle(widget.small ? 18 : 26, color: widget.foreground),
                    ),
                  if (widget.caption != null || widget.icon != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.icon != null ? widget.label : widget.caption!,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: widget.foreground.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
