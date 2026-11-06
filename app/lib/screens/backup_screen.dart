import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup.dart';
import '../state/providers.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../widgets/surface_panel.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _backUp() async {
    final matches = ref.read(matchRepositoryProvider);
    final teams = ref.read(teamRepositoryProvider);
    final tournaments = ref.read(tournamentRepositoryProvider);
    final files = ref.read(deviceFilesProvider);
    setState(() => _busy = true);
    try {
      final backup = await collectBackup(matches, teams, tournaments);
      if (backup.isEmpty) {
        if (mounted) showMessage(context, 'Nothing to back up yet.');
      } else {
        final now = DateTime.now();
        await files.shareTextFile(
          'bnp-scorer-backup-${isoDate(now)}.json',
          backup.encode(now),
        );
      }
    } on Object catch (e) {
      if (mounted) showMessage(context, 'Could not back up: $e', isError: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    final matches = ref.read(matchRepositoryProvider);
    final teams = ref.read(teamRepositoryProvider);
    final tournaments = ref.read(tournamentRepositoryProvider);
    final files = ref.read(deviceFilesProvider);
    setState(() => _busy = true);
    try {
      final raw = await files.pickTextFile();
      if (raw == null || !mounted) return;
      final backup = Backup.decode(raw);
      final confirmed = await _confirm(backup);
      if (!confirmed || !mounted) return;
      final result = await restoreBackup(backup, matches, teams, tournaments);
      if (!mounted) return;
      ref
        ..invalidate(matchListProvider)
        ..invalidate(savedTeamsProvider)
        ..invalidate(tournamentsProvider);
      showMessage(
        context,
        result.addedNothing ? 'Everything in that backup is already here.' : 'Added ${result.summary}.',
      );
    } on FormatException catch (e) {
      if (mounted) showMessage(context, e.message, isError: true);
    } on Object catch (e) {
      if (mounted) showMessage(context, 'Could not restore: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(Backup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'It holds ${backup.summary}. Anything missing is added, and nothing already '
          'on this phone is changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Back up'),
                const SizedBox(height: 8),
                Text(
                  'Your matches, teams and tournaments live only on this phone. Uninstalling '
                  'the app deletes them. Save a backup file to Drive, or send it to yourself.',
                  style: text.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _backUp,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Create backup'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Restore'),
                const SizedBox(height: 8),
                Text(
                  'Pick a backup file to add anything missing. Nothing already on this phone '
                  'is changed.',
                  style: text.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.restore_page_rounded),
                  label: const Text('Restore from a file'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
