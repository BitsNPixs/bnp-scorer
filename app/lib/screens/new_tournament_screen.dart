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

enum _Knockout { none, finalOnly, semiFinals }

const _minTeamsForFinal = 3;
const _minTeamsForGroupsOrSemis = 4;

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
  bool _wantsTwoGroups = false;
  bool _homeAndAway = false;
  DateTime? _startsAt;
  int _perDay = 2;
  _Knockout _wanted = _Knockout.finalOnly;
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

  bool get _twoGroups => _wantsTwoGroups && _teamIds.length >= _minTeamsForGroupsOrSemis;

  /// What was asked for, within what this many teams allows. Two groups always
  /// need a knockout game, or they would never meet.
  _Knockout get _knockout {
    final teams = _teamIds.length;
    if (teams < _minTeamsForFinal) return _Knockout.none;
    if (_wanted == _Knockout.semiFinals && teams < _minTeamsForGroupsOrSemis) {
      return _Knockout.finalOnly;
    }
    if (_wanted == _Knockout.none && _twoGroups) return _Knockout.finalOnly;
    return _wanted;
  }

  int get _legs => _homeAndAway ? 2 : 1;

  List<List<String>>? _groupsOf(List<Team> teams) => _twoGroups ? splitIntoTwoGroups(teams) : null;

  List<Fixture> _fixturesOf(List<Team> teams) {
    final groups = _groupsOf(teams);
    final fixtures = groups == null
        ? roundRobinFixtures(teams, legs: _legs)
        : leagueFixtures(groups, legs: _legs);
    final start = _startsAt;
    return start == null ? fixtures : scheduleFixtures(fixtures, start, perDay: _perDay);
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _startsAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (time == null || !mounted) return;
    setState(() => _startsAt = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

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
    final knockout = _knockout;
    final tournament = Tournament(
      id: newId(),
      name: _name.text.trim(),
      oversPerInnings: _overs,
      hasFinal: knockout != _Knockout.none,
      hasSemiFinals: knockout == _Knockout.semiFinals,
      legs: _legs,
      groups: _groupsOf(teams),
      teams: teams,
      fixtures: _fixturesOf(teams),
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
    final selected = saved.where((t) => _teamIds.contains(t.id)).toList();
    final knockout = _knockout;
    final teamCount = _teamIds.length;
    final summary = [
      plural(_fixturesOf(selected).length, 'match'),
      if (knockout == _Knockout.semiFinals) 'semi-finals',
      if (knockout != _Knockout.none) 'final',
    ].join(' + ');
    String groupText(List<String> ids) =>
        ids.map((id) => selected.firstWhere((t) => t.id == id).name).join(', ');
    final groups = _groupsOf(selected);

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
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.event_rounded),
                  title: const Text('First match'),
                  subtitle: Text(
                    _startsAt == null ? 'Optional. Dates every fixture.' : fixtureDate(_startsAt!),
                  ),
                  trailing: _startsAt == null
                      ? null
                      : IconButton(
                          tooltip: 'Clear date',
                          onPressed: () => setState(() => _startsAt = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  onTap: _pickStart,
                ),
                if (_startsAt != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('Matches a day'),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            segments: [
                              for (final n in const [1, 2, 3, 4])
                                ButtonSegment(value: n, label: Text('$n')),
                            ],
                            selected: {_perDay},
                            onSelectionChanged: (s) => setState(() => _perDay = s.first),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SurfacePanel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Two groups'),
                  subtitle: Text(
                    groups == null
                        ? 'Needs at least 4 teams'
                        : 'A: ${groupText(groups[0])}\nB: ${groupText(groups[1])}',
                  ),
                  value: _twoGroups,
                  onChanged: teamCount >= _minTeamsForGroupsOrSemis
                      ? (v) => setState(() => _wantsTwoGroups = v)
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Home and away'),
                  subtitle: const Text('Teams meet twice'),
                  value: _homeAndAway,
                  onChanged: (v) => setState(() => _homeAndAway = v),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Knockouts'),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<_Knockout>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: _Knockout.none,
                              enabled: !_twoGroups,
                              label: const Text('None'),
                            ),
                            ButtonSegment(
                              value: _Knockout.finalOnly,
                              enabled: teamCount >= _minTeamsForFinal,
                              label: const Text('Final'),
                            ),
                            ButtonSegment(
                              value: _Knockout.semiFinals,
                              enabled: teamCount >= _minTeamsForGroupsOrSemis,
                              label: const Text('Semis'),
                            ),
                          ],
                          selected: {knockout},
                          onSelectionChanged: (s) => setState(() => _wanted = s.first),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
