import 'dart:math';

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
import '../widgets/scoring_sheets.dart';
import '../widgets/surface_panel.dart';
import 'tournament_screen.dart';

enum _Knockout {
  none('None'),
  finalOnly('Final'),
  semiFinals('Semis'),
  quarterFinals('Quarters');

  const _Knockout(this.label);

  final String label;
}

const _minTeamsForFinal = 3;
const _minTeamsForGroupsOrSemis = 4;
const _minTeamsForQuarters = 8;

class NewTournamentScreen extends ConsumerStatefulWidget {
  const NewTournamentScreen({super.key, this.random});

  /// Shuffles the draw of a knockout cup; tests pass a seeded one.
  final Random? random;

  @override
  ConsumerState<NewTournamentScreen> createState() => _NewTournamentScreenState();
}

class _NewTournamentScreenState extends ConsumerState<NewTournamentScreen> {
  final _name = TextEditingController();
  final _venue = TextEditingController();
  /// In the order they were ticked, which is a knockout cup's draw.
  final _teamIds = <String>[];
  TournamentFormat _format = TournamentFormat.league;
  late final Random _random = widget.random ?? Random();
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

  bool get _isCup => _format == TournamentFormat.knockout;

  bool get _twoGroups => !_isCup && _wantsTwoGroups && _teamIds.length >= _minTeamsForGroupsOrSemis;

  /// The knockout choices this many teams allows. Two groups always need a
  /// knockout game, or they would never meet.
  List<_Knockout> get _knockoutOptions {
    final teams = _teamIds.length;
    return [
      if (!_twoGroups) _Knockout.none,
      if (teams >= _minTeamsForFinal) _Knockout.finalOnly,
      if (teams >= _minTeamsForGroupsOrSemis) _Knockout.semiFinals,
      if (teams >= _minTeamsForQuarters) _Knockout.quarterFinals,
    ];
  }

  /// What was asked for, or the nearest smaller choice this many teams allows.
  _Knockout get _knockout {
    final options = _knockoutOptions;
    if (options.isEmpty) return _Knockout.none;
    final wanted = _Knockout.values.indexOf(_wanted);
    return options.lastWhere((o) => o.index <= wanted, orElse: () => options.first);
  }

  int get _legs => _homeAndAway ? 2 : 1;

  /// The ticked teams, in the order they were ticked.
  List<Team> _selectedOf(List<Team> saved) => [
        for (final id in _teamIds) ?saved.where((t) => t.id == id).firstOrNull,
      ];

  List<List<String>>? _groupsOf(List<Team> teams) => _twoGroups ? splitIntoTwoGroups(teams) : null;

  List<Fixture> _fixturesOf(List<Team> teams) {
    final groups = _groupsOf(teams);
    final List<Fixture> fixtures;
    if (_isCup) {
      fixtures = teams.length < _minTeamsForFinal ? const [] : knockoutFixtures([for (final t in teams) t.id]);
    } else {
      fixtures = groups == null ? roundRobinFixtures(teams, legs: _legs) : leagueFixtures(groups, legs: _legs);
    }
    final start = _startsAt;
    return start == null ? fixtures : scheduleFixtures(fixtures, start, perDay: _perDay);
  }

  /// "11 matches · 4 byes" for a cup, "6 matches + semi-finals + final" for a league.
  String _summaryOf(List<Team> selected) {
    if (_isCup) {
      final teams = selected.length;
      return [plural(teams - 1, 'match'), if (_byes(teams) > 0) plural(_byes(teams), 'bye')].join(' · ');
    }
    final knockout = _knockout;
    return [
      plural(_fixturesOf(selected).length, 'match'),
      if (knockout == _Knockout.quarterFinals) 'quarter-finals',
      if (knockout.index >= _Knockout.semiFinals.index) 'semi-finals',
      if (knockout != _Knockout.none) 'final',
    ].join(' + ');
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
    if (_isCup && _teamIds.length < _minTeamsForFinal) return 'A cup needs at least 3 teams';
    if (_isCup && _teamIds.length > maxKnockoutTeams) return 'A cup takes at most $maxKnockoutTeams teams';
    return null;
  }

  Future<void> _create(List<Team> saved) async {
    if (_blocker != null || _saving) return;
    setState(() => _saving = true);
    final teams = _selectedOf(saved);
    final venue = _venue.text.trim();
    final knockout = _isCup ? _Knockout.none : _knockout;
    final tournament = Tournament(
      id: newId(),
      name: _name.text.trim(),
      oversPerInnings: _overs,
      format: _format,
      hasFinal: _isCup || knockout != _Knockout.none,
      hasSemiFinals: knockout.index >= _Knockout.semiFinals.index,
      hasQuarterFinals: knockout == _Knockout.quarterFinals,
      legs: _isCup ? 1 : _legs,
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
    final selected = _selectedOf(saved);
    final teamCount = _teamIds.length;
    final summary = _summaryOf(selected);
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Format'),
                      const SizedBox(height: 8),
                      OptionChips<TournamentFormat>(
                        options: TournamentFormat.values,
                        labelOf: (f) => f == TournamentFormat.league ? 'League' : 'Knockout cup',
                        selected: _format,
                        color: Theme.of(context).colorScheme.primary,
                        onSelected: (f) => setState(() => _format = f),
                      ),
                    ],
                  ),
                ),
                if (_isCup)
                  _CupDraw(teams: selected, onShuffle: () => setState(() => _teamIds.shuffle(_random)))
                else ...[
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
                        OptionChips<_Knockout>(
                          options: _knockoutOptions,
                          labelOf: (k) => k.label,
                          selected: _knockout,
                          color: Theme.of(context).colorScheme.primary,
                          onSelected: (k) => setState(() => _wanted = k),
                        ),
                      ],
                    ),
                  ),
                ],
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

/// Byes in a knockout cup of [teams]: the gap up to the next 4, 8, 16, 32 or 64.
int _byes(int teams) {
  var size = 2;
  while (size < teams) {
    size *= 2;
  }
  return size - teams;
}

/// A knockout cup's first round as it will be drawn, with a shuffle.
class _CupDraw extends StatelessWidget {
  const _CupDraw({required this.teams, required this.onShuffle});

  /// In draw order.
  final List<Team> teams;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final byes = _byes(teams.length);
    final playing = teams.skip(byes).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionLabel('Draw')),
              TextButton.icon(
                onPressed: teams.length < 2 ? null : onShuffle,
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Shuffle draw'),
              ),
            ],
          ),
          Text(
            'Losers go out each round. Teams meet in the order you tick them; when the '
            'number is not 4, 8, 16 or 32, the first teams get byes into round two.',
            style: text.bodySmall?.copyWith(color: muted),
          ),
          if (teams.length >= _minTeamsForFinal) ...[
            const SizedBox(height: 10),
            for (var i = 0; i + 1 < playing.length; i += 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${playing[i].name} v ${playing[i + 1].name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            if (byes > 0)
              Text(
                'Byes: ${teams.take(byes).map((t) => t.name).join(', ')}',
                style: text.bodyMedium?.copyWith(color: muted),
              ),
          ],
        ],
      ),
    );
  }
}
