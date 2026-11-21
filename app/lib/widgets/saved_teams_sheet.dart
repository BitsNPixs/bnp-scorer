import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import 'avatars.dart';
import 'scoring_sheets.dart';

/// Lists saved teams and returns the one tapped, or null if dismissed.
/// [excludeTeamId] hides the team already playing on the other side.
Future<Team?> showSavedTeamsSheet(BuildContext context, {String? excludeTeamId}) =>
    showModalBottomSheet<Team>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _SavedTeamsSheet(excludeTeamId: excludeTeamId),
    );

class _SavedTeamsSheet extends ConsumerWidget {
  const _SavedTeamsSheet({this.excludeTeamId});

  final String? excludeTeamId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Team team) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${team.name}?'),
        content: const Text('Past matches keep their scorecards.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.wicket,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final repository = ref.read(teamRepositoryProvider);
    try {
      await repository.delete(team.id);
    } on Object catch (e) {
      if (context.mounted) showMessage(context, 'Could not delete the team: $e', isError: true);
      return;
    }
    if (context.mounted) ref.invalidate(savedTeamsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = (ref.watch(savedTeamsProvider).value ?? const <Team>[])
        .where((t) => t.id != excludeTeamId)
        .toList();
    return SheetBody(
      title: 'Saved teams',
      subtitle: 'Tap a team to add its players',
      child: teams.isEmpty
          ? const Text('No saved teams left.')
          : Column(
              children: [
                for (final team in teams)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: TeamBadge(name: team.name, size: 40, logoUrl: team.logoUrl),
                    title: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(plural(team.players.length, 'player')),
                    trailing: IconButton(
                      tooltip: 'Delete ${team.name}',
                      onPressed: () => _delete(context, ref, team),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                    onTap: () => Navigator.of(context).pop(team),
                  ),
              ],
            ),
    );
  }
}
