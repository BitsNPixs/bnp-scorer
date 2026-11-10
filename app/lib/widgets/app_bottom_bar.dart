import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'surface_panel.dart';

/// One tab in [AppBottomBar].
typedef BottomBarItem = ({IconData icon, IconData selectedIcon, String label});

/// The floating bottom bar: two tabs, the raised "new match" button, two tabs.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.onCreate,
    this.createTooltip = 'New match',
  }) : assert(items.length == 4, 'Two tabs either side of the button');

  final List<BottomBarItem> items;
  final int selected;
  final ValueChanged<int> onSelected;
  final VoidCallback onCreate;
  final String createTooltip;

  static const barHeight = 68.0;
  static const createSize = 60.0;

  /// How far the create button rises above the bar.
  static const _lift = 18.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(int i) => Expanded(
      child: _BarTab(item: items[i], selected: selected == i, onTap: () => onSelected(i)),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: SizedBox(
          height: barHeight + _lift,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Material(
                color: scheme.surfaceContainerLow,
                shape: cardShape(context, radius: 28),
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: barHeight,
                  child: Row(
                    children: [
                      tab(0),
                      tab(1),
                      const SizedBox(width: createSize + 16),
                      tab(2),
                      tab(3),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                child: _CreateButton(tooltip: createTooltip, onTap: onCreate),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarTab extends StatelessWidget {
  const _BarTab({required this.item, required this.selected, required this.onTap});

  final BottomBarItem item;
  final bool selected;
  final VoidCallback onTap;

  static const _duration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Tooltip(
      message: item.label,
      child: Semantics(
        selected: selected,
        button: true,
        child: InkResponse(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          radius: 36,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: _duration,
                curve: Curves.easeOutCubic,
                width: selected ? 52 : 36,
                height: 30,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary.withValues(alpha: 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: AnimatedScale(
                  scale: selected ? 1.12 : 1,
                  duration: _duration,
                  curve: Curves.easeOutBack,
                  child: Icon(selected ? item.selectedIcon : item.icon, color: color, size: 24),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                    duration: _duration,
                    // Built on the theme's style: this replaces, not merges,
                    // the inherited one, so a bare TextStyle loses the font.
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      fontSize: 11,
                      color: color,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                    child: Text(item.label, maxLines: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The big neon "+" that starts a match from any tab.
class _CreateButton extends StatefulWidget {
  const _CreateButton({required this.tooltip, required this.onTap});

  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_CreateButton> createState() => _CreateButtonState();
}

class _CreateButtonState extends State<_CreateButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const size = AppBottomBar.createSize;
    return Tooltip(
      message: widget.tooltip,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.neonGradient,
            boxShadow: AppColors.glow(AppColors.neon, strength: 0.45, blur: 20),
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onTap();
              },
              onHighlightChanged: (v) => setState(() => _pressed = v),
              child: const Icon(Icons.add_rounded, size: 32, color: AppColors.night),
            ),
          ),
        ),
      ),
    );
  }
}
