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
import '../widgets/scoring_sheets.dart';
import '../widgets/stat_widgets.dart';
import '../widgets/surface_panel.dart';
import 'team_edit_screen.dart';

class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key});

  void _open(BuildContext context, [Team? team]) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TeamEditScreen(team: team)));

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
      await _explain(context, e.message);
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

  Future<void> _explain(BuildContext context, String message) => showDialog<void>(
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
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.of(dialogContext).pop(),
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
          IconButton(
            tooltip: 'Import teams from a CSV file',
            onPressed: () => _import(context, ref),
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
                        leading: TeamBadge(name: team.name, size: 40),
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
      title: 'Import teams',
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
