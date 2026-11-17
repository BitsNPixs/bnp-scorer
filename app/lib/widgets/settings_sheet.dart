import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/accounts.dart';
import '../data/app_info.dart';
import '../data/error_log.dart';
import '../screens/backup_screen.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import 'avatars.dart';
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
        const _AccountSection(),
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
        const SizedBox(height: 24),
        const SectionLabel('About'),
        const SizedBox(height: 10),
        const _AboutPanel(),
        const SizedBox(height: 10),
        SurfacePanel(
          padding: EdgeInsets.zero,
          child: Consumer(
            builder: (_, ref, _) => ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Report a problem'),
              subtitle: const Text('Tell us what went wrong, with recent error details'),
              trailing: const Icon(Icons.send_rounded),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _reportProblem(context, ref);
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        SurfacePanel(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open-source licences'),
            subtitle: const Text('Fonts and libraries BNP Scorer is built with'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showLicensePage(
                context: context,
                applicationName: 'BNP Scorer',
                applicationLegalese: 'By Bits N Pixs',
              );
            },
          ),
        ),
      ],
    ),
  ),
);

/// Google sign-in, so the matches a scorer starts are published for everyone.
/// Hidden in a build without the cloud.
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  static const publicNotice = "While you're signed in, every new match you score is public: anyone "
      'with BNP Scorer can follow it, including the player names. Matches already on this phone '
      'stay private.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    if (!accounts.available) return const SizedBox.shrink();
    final scorer = ref.watch(scorerProvider).value ?? accounts.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const SectionLabel('Account'),
        const SizedBox(height: 10),
        SurfacePanel(
          padding: EdgeInsets.zero,
          child: scorer == null
              ? ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: const Text('Sign in with Google'),
                  subtitle: const Text('Publish the matches you score so everyone can follow them'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _signIn(context, accounts),
                )
              : ListTile(
                  leading: PlayerAvatar(name: scorer.name, radius: 18),
                  title: Text(scorer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: const Text('New matches you score are public'),
                  trailing: TextButton(
                    onPressed: () => _signOut(context, accounts),
                    child: const Text('Sign out'),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _signIn(BuildContext context, Accounts accounts) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Publish your matches?'),
        content: const Text(publicNotice),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Not now')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (agreed != true || !context.mounted) return;
    try {
      final scorer = await accounts.signIn();
      if (scorer != null && context.mounted) showMessage(context, 'Signed in as ${scorer.name}');
    } on AccountsException catch (e) {
      if (context.mounted) showMessage(context, e.message, isError: true);
    }
  }

  Future<void> _signOut(BuildContext context, Accounts accounts) async {
    try {
      await accounts.signOut();
      if (context.mounted) showMessage(context, 'Signed out. New matches stay on this phone.');
    } on Object catch (e) {
      if (context.mounted) showMessage(context, 'Could not sign out: $e', isError: true);
    }
  }
}

/// Opens the share sheet with a problem report. Reads everything it needs
/// before the first await, as the sheet that called it is closing.
Future<void> _reportProblem(BuildContext context, WidgetRef ref) async {
  final errors = ref.read(errorLogProvider).entries;
  final files = ref.read(deviceFilesProvider);
  final report = problemReport(
    errors: errors,
    version: appVersionLabel,
    platform: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    now: DateTime.now(),
  );
  try {
    await files.shareText(report, subject: 'BNP Scorer problem report');
  } on Object catch (e) {
    if (context.mounted) showMessage(context, 'Could not open sharing: $e', isError: true);
  }
}

/// Version and the privacy promise, inline so nobody has to dig for them.
class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  static const privacy = 'Your matches stay on this phone. No account, no internet, nothing '
      'collected. Sharing sends only what you see, to the app you pick.';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BNP Scorer', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('Version $appVersionLabel · By Bits N Pixs', style: text.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(privacy, style: text.bodyMedium)),
            ],
          ),
        ],
      ),
    );
  }
}

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
