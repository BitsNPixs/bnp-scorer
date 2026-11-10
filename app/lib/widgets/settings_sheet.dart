import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/backup_screen.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'scoring_sheets.dart';
import 'surface_panel.dart';

/// Appearance and data settings, opened from the top of Home.
Future<void> showSettingsSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (sheetContext) => SheetBody(
    title: 'Settings',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Appearance'),
        const SizedBox(height: 10),
        const _ThemePicker(),
        const SizedBox(height: 24),
        const SectionLabel('Data'),
        const SizedBox(height: 10),
        SurfacePanel(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.backup_rounded),
            title: const Text('Backup and restore'),
            subtitle: const Text('Keep your matches safe or move them to a new phone'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(sheetContext)
                ..pop()
                ..push(MaterialPageRoute<void>(builder: (_) => const BackupScreen()));
            },
          ),
        ),
      ],
    ),
  ),
);

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  static const _options = [
    (ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
    (ThemeMode.light, Icons.light_mode_rounded, 'Light'),
    (ThemeMode.dark, Icons.dark_mode_rounded, 'Dark'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Row(
      children: [
        for (final (i, (value, icon, label)) in _options.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _ThemeOption(
              icon: icon,
              label: label,
              preview: value,
              selected: mode == value,
              onTap: () => ref.read(themeModeProvider.notifier).select(value),
            ),
          ),
        ],
      ],
    );
  }
}

/// A tiny drawing of the app in that theme, so the choice is obvious.
class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final ThemeMode preview;
  final bool selected;
  final VoidCallback onTap;

  static final _light = AppTheme.light().colorScheme;
  static final _dark = AppTheme.dark().colorScheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget swatch(ColorScheme s) => Expanded(
      child: Container(
        color: s.surface,
        padding: const EdgeInsets.all(5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 12,
              decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 4),
            Container(
              height: 7,
              width: 22,
              decoration: BoxDecoration(color: AppColors.neon, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 4),
            Container(
              height: 7,
              decoration: BoxDecoration(color: s.surfaceContainerHigh, borderRadius: BorderRadius.circular(4)),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
          boxShadow: selected ? AppColors.glow(scheme.primary, strength: 0.18, blur: 16) : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 54,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (preview != ThemeMode.dark) swatch(_light),
                          if (preview != ThemeMode.light) swatch(_dark),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 16, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                            color: selected ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
