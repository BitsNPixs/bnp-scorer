import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/format.dart';
import '../widgets/avatars.dart';
import '../widgets/stat_widgets.dart';
import '../widgets/surface_panel.dart';
import 'team_edit_screen.dart';

class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key});

  void _open(BuildContext context, [Team? team]) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => TeamEditScreen(team: team)),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(savedTeamsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        backgroundColor: AppColors.lime,
        foregroundColor: AppColors.ink,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New team', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: teams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load teams.\n$error', textAlign: TextAlign.center)),
        data: (list) => list.isEmpty
            ? const StatsEmpty(message: 'No teams yet. Teams are saved when they play, or add one here.')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final team = list[i];
                  final captain = team.playerById(team.captainId ?? '')?.name;
                  return SurfacePanel(
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
                  );
                },
              ),
      ),
    );
  }
}
