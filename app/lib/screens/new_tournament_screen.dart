import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ids.dart';
import '../state/providers.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../ui/inputs.dart';
import '../widgets/avatars.dart';
import '../widgets/overs_picker.dart';
import '../widgets/surface_panel.dart';
import 'tournament_screen.dart';

class NewTournamentScreen extends ConsumerStatefulWidget {
  const NewTournamentScreen({super.key});

  @override
  ConsumerState<NewTournamentScreen> createState() => _NewTournamentScreenState();
}

class _NewTournamentScreenState extends ConsumerState<NewTournamentScreen> {
  final _name = TextEditingController();
  final _venue = TextEditingController();
  final _teamIds = <String>{};
  int _overs = 10;
  bool _wantsFinal = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _venue.dispose();
    super.dispose();
  }

  /// A final needs a league of at least three teams.
  bool get _hasFinal => _wantsFinal && _teamIds.length >= 3;

  String? get _blocker {
    if (_name.text.trim().isEmpty) return 'Give the tournament a name';
    if (_teamIds.length < 2) return 'Choose at least 2 teams';
    return null;
  }

  Future<void> _create(List<Team> saved) async {
    if (_blocker != null || _saving) return;
    setState(() => _saving = true);
    final teams = saved.where((t) => _teamIds.contains(t.id)).toList();
    final venue = _venue.text.trim();
    final tournament = Tournament(
      id: newId(),
      name: _name.text.trim(),
      oversPerInnings: _overs,
      hasFinal: _hasFinal,
      teams: teams,
      fixtures: roundRobinFixtures(teams),
      createdAt: DateTime.now(),
      venue: venue.isEmpty ? null : venue,
    );
    try {
      await ref.read(tournamentRepositoryProvider).save(tournament);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Could not save the tournament: $e', isError: true);
      }
      return;
    }
    if (!mounted) return;
    ref.invalidate(tournamentsProvider);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => TournamentScreen(tournamentId: tournament.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedTeamsProvider).value ?? const <Team>[];
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final blocker = _blocker;
    final leagueGames = _teamIds.length * (_teamIds.length - 1) ~/ 2;
    final summary = [
      plural(leagueGames, 'match'),
      if (_hasFinal) 'final',
    ].join(' + ');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('New tournament'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: fieldDecoration(context, 'Tournament name', icon: Icons.emoji_events_outlined),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _venue,
            textCapitalization: TextCapitalization.words,
            decoration: fieldDecoration(context, 'Ground / venue (optional)', icon: Icons.place_outlined),
          ),
          const SizedBox(height: 12),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel('Teams · ${_teamIds.length}'),
                const SizedBox(height: 4),
                if (saved.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Teams are saved when they play a match. Start a match first, or add teams there.',
                      style: text.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                for (final team in saved)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: TeamBadge(name: team.name, size: 36),
                    title: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(plural(team.players.length, 'player')),
                    value: _teamIds.contains(team.id),
                    onChanged: (selected) => setState(() {
                      if (selected ?? false) {
                        _teamIds.add(team.id);
                      } else {
                        _teamIds.remove(team.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OversPicker(overs: _overs, onChanged: (o) => setState(() => _overs = o)),
          const SizedBox(height: 12),
          SurfacePanel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SwitchListTile(
              title: const Text('Final between the top two'),
              subtitle: const Text('Needs at least 3 teams'),
              value: _hasFinal,
              onChanged: _teamIds.length >= 3 ? (v) => setState(() => _wantsFinal = v) : null,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(blocker ?? summary, style: text.bodySmall?.copyWith(color: muted)),
              ),
              FilledButton.icon(
                onPressed: blocker == null && !_saving ? () => _create(saved) : null,
                icon: const Icon(Icons.emoji_events_rounded),
                label: const Text('Create tournament'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
