import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ids.dart';
import '../data/squad_import.dart';
import '../state/providers.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../ui/motion.dart';
import '../widgets/avatars.dart';
import '../widgets/join_team_sheet.dart';
import '../widgets/scoring_sheets.dart';
import '../widgets/stat_widgets.dart';
import '../widgets/surface_panel.dart';
import 'team_edit_screen.dart';

class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key});

  void _open(BuildContext context, [Team? team]) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeamEditScreen(team: team)));

  /// Shows the format first, then picks a file or shares the template.
  Future<void> _startImport(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<_ImportChoice>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _ImportStart(),
    );
    if (!context.mounted) return;
    switch (choice) {
      case _ImportChoice.pickFile:
        await _import(context, ref);
      case _ImportChoice.shareTemplate:
        await _shareTemplate(context, ref);
      case null:
        break;
    }
  }

  /// Sends the template through the share sheet: to WhatsApp, email or Drive,
  /// to open in Sheets or Excel here or on a computer.
  Future<void> _shareTemplate(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(deviceFilesProvider).shareTextFile(teamsTemplateFileName, teamsTemplateCsv);
    } on Object catch (e) {
      if (context.mounted) showMessage(context, 'Could not share the template: $e', isError: true);
    }
  }

  /// Reads teams from a sheet saved as CSV, shows what each would become, and
  /// saves them once the scorer agrees.
  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final String? raw;
    try {
      raw = await ref.read(deviceFilesProvider).pickTextFile();
    } on Object catch (e) {
      if (context.mounted) showMessage(context, 'Could not open that file: $e', isError: true);
      return;
    }
    if (raw == null || !context.mounted) return;
    final List<ImportedTeam> teams;
    try {
      teams = parseTeamsCsv(raw);
    } on FormatException catch (e) {
      if (!context.mounted) return;
      final wantsTemplate = await _explain(context, e.message);
      if (wantsTemplate == true && context.mounted) await _shareTemplate(context, ref);
      return;
    }
    final saved = await ref.read(savedTeamsProvider.future);
    if (!context.mounted) return;
    final plan = planImport(saved, teams, newId: newId);
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _ImportPreview(plan: plan),
    );
    if (go != true || !context.mounted) return;
    final repository = ref.read(teamRepositoryProvider);
    final ready = [for (final p in plan) if (p.team != null) p];
    try {
      for (final p in ready) {
        await repository.save(p.team!);
      }
    } on Object catch (e) {
      if (context.mounted) showMessage(context, 'Could not save the teams: $e', isError: true);
      return;
    } finally {
      if (context.mounted) ref.invalidate(savedTeamsProvider);
    }
    if (!context.mounted) return;
    final added = ready.fold(0, (sum, p) => sum + p.update.added);
    showMessage(context, 'Imported ${plural(ready.length, 'team')} with ${plural(added, 'new player')}.');
  }

  /// Says what is wrong with a file. True when the scorer asks for the template.
  Future<bool?> _explain(BuildContext context, String message) => showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Could not import that file'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              const SelectableText('A template to fill in: $teamsTemplateAddress'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Share the template'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(savedTeamsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teams'),
        actions: [
          if (ref.watch(cloudTeamsProvider) != null)
            IconButton(
              tooltip: 'Join a team',
              onPressed: () async {
                final joined = await showJoinTeamSheet(context);
                if (joined != null && context.mounted) {
                  showMessage(context, 'Asked to join $joined. Your captain adds you.');
                }
              },
              icon: const Icon(Icons.group_add_rounded),
            ),
          IconButton(
            tooltip: 'Import teams from a CSV file',
            onPressed: () => _startImport(context, ref),
            icon: const Icon(Icons.upload_file_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New team'),
      ),
      body: teams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load teams.\n$error', textAlign: TextAlign.center)),
        data: (list) => list.isEmpty
            ? const StatsEmpty(
                message: 'No teams yet. Teams are saved when they play. Add one here, '
                    'or import a sheet saved as CSV with the button at the top.',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final team = list[i];
                  final captain = team.playerById(team.captainId ?? '')?.name;
                  return EntranceFade(
                    key: ValueKey(team.id),
                    index: i,
                    child: SurfacePanel(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: TeamBadge(name: team.name, size: 40, logoUrl: team.logoUrl),
                        title: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [plural(team.players.length, 'player'), if (captain != null) 'Captain: $captain'].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _open(context, team),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// What an import would do to each team, before anything is saved.
class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.plan});

  final List<PlannedTeam> plan;

  String _status(PlannedTeam p) {
    if (p.team == null) return 'Needs at least 2 players, so it is skipped';
    final players = plural(p.team!.players.length, 'player');
    if (p.isNew) return 'New team · $players';
    if (p.update.added == 0) return 'Already saved · nothing new';
    return 'Adds ${p.update.added} to the saved team · $players';
  }

  String _names(PlannedTeam p) => [
        for (final player in p.source.players)
          player.marks.isEmpty ? player.name : '${player.name} (${player.marks.join(', ')})',
      ].join(', ');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ready = plan.where((p) => p.team != null).length;
    return SheetBody(
      title: 'Check before importing',
      subtitle: 'A team with the same name as a saved one adds its new players to it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in plan) ...[
            SurfacePanel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TeamBadge(name: p.source.name, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _status(p),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: p.team == null ? scheme.error : scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _names(p),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: ready == 0 ? null : () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.download_done_rounded),
            label: Text(ready == 0 ? 'Nothing to import' : 'Import ${plural(ready, 'team')}'),
          ),
        ],
      ),
    );
  }
}

enum _ImportChoice { pickFile, shareTemplate }

/// The first step of an import: what the file should look like, taken from the
/// template itself, then pick a file or share the template to fill in.
class _ImportStart extends StatelessWidget {
  const _ImportStart();

  /// The header and a few rows of the template, from both teams, with roles
  /// short enough to fit a phone (Captain, Bowler, WK).
  static final _sample = () {
    final rows = parseCsv(teamsTemplateCsv);
    return [rows[0], rows[1], rows[3], rows[8]];
  }();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    Widget cell(String value, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: head
                ? text.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800, letterSpacing: 0.8)
                : text.bodySmall,
          ),
        );
    return SheetBody(
      title: 'Import teams',
      subtitle: 'Bring in many teams at once from Excel or Google Sheets, saved as CSV.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurfacePanel(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Table(
              columnWidths: const {0: FlexColumnWidth(5), 1: FlexColumnWidth(5), 2: FlexColumnWidth(4)},
              children: [
                for (final (i, row) in _sample.indexed)
                  TableRow(
                    decoration: i == 0
                        ? BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant)))
                        : null,
                    children: [for (final value in row) cell(i == 0 ? value.toUpperCase() : value, head: i == 0)],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'One row per player. Role is optional: Captain, Vice-captain, WK, Batter, Bowler or '
            'All-rounder. One column per team, with its name on top, works too.',
            style: muted,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_ImportChoice.pickFile),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Pick a CSV file'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(_ImportChoice.shareTemplate),
            icon: const Icon(Icons.share_rounded),
            label: const Text('Share the template'),
          ),
          const SizedBox(height: 14),
          Text(
            'One or two teams? "Paste a list" on the team\'s page is quicker.',
            textAlign: TextAlign.center,
            style: muted,
          ),
        ],
      ),
    );
  }
}
