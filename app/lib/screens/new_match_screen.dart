import 'dart:math';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ids.dart';
import '../data/match_record.dart';
import '../data/team_repository.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/feedback.dart';
import '../ui/inputs.dart';
import '../widgets/avatars.dart';
import '../widgets/overs_picker.dart';
import '../widgets/saved_teams_sheet.dart';
import '../widgets/surface_panel.dart';
import 'scoring_screen.dart';

const _quickFillSize = 11;

/// A tournament fixture to start, with the squads to fill in.
class FixtureMatch {
  const FixtureMatch({
    required this.tournament,
    required this.fixture,
    required this.home,
    required this.away,
  });

  final Tournament tournament;
  final Fixture fixture;
  final Team home;
  final Team away;
}

class NewMatchScreen extends ConsumerStatefulWidget {
  const NewMatchScreen({super.key, this.fixture});

  /// When set, the teams, overs and title come from the tournament.
  final FixtureMatch? fixture;

  @override
  ConsumerState<NewMatchScreen> createState() => _NewMatchScreenState();
}

class _NewMatchScreenState extends ConsumerState<NewMatchScreen> {
  final _teamA = _TeamDraft('Team A');
  final _teamB = _TeamDraft('Team B');
  final _venue = TextEditingController();
  int _overs = 10;
  int _tossWinner = 0;
  TossDecision _decision = TossDecision.bat;
  bool _wideCountsRun = true;
  bool _noBallCountsRun = true;
  bool _freeHit = true;
  bool _lastManStands = false;
  bool _limitBowlerOvers = false;
  bool _trackShots = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final draft in [_teamA, _teamB]) {
      draft.name.addListener(_refresh);
    }
    final fixture = widget.fixture;
    if (fixture != null) {
      _teamA.load(fixture.home);
      _teamB.load(fixture.away);
      _overs = fixture.fixture.isDecider ? 1 : fixture.tournament.oversPerInnings;
      _venue.text = fixture.tournament.titleOf(fixture.fixture);
    }
  }

  @override
  void dispose() {
    _teamA.dispose();
    _teamB.dispose();
    _venue.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  /// Why the match cannot start yet, or null when it can.
  String? get _blocker {
    final a = _teamA.name.text.trim();
    final b = _teamB.name.text.trim();
    if (a.isEmpty || b.isEmpty) return 'Give both teams a name';
    if (a.toLowerCase() == b.toLowerCase()) return 'Team names must be different';
    if (_teamA.players.length < 2 || _teamB.players.length < 2) {
      return 'Add at least 2 players per team';
    }
    if (_limitBowlerOvers) {
      final fewest = [_teamA.players.length, _teamB.players.length].reduce(min);
      if (fewest * _maxBowlerOvers < _overs) {
        return 'Too few bowlers for $_maxBowlerOvers overs each: add players or remove the limit';
      }
    }
    return null;
  }

  int get _maxBowlerOvers => (_overs / 5).ceil();

  /// One over, and the fixture already says who bats first.
  bool get _isSuperOver => widget.fixture?.fixture.isDecider ?? false;

  Future<void> _start() async {
    if (_blocker != null || _saving) return;
    setState(() => _saving = true);
    final savedTeams = ref.read(teamRepositoryProvider);
    final tournaments = widget.fixture == null ? null : ref.read(tournamentRepositoryProvider);
    await _linkTypedTeams(savedTeams);
    if (!mounted) return;
    final now = DateTime.now();
    final teamA = _teamA.build();
    final teamB = _teamB.build();
    final venue = _venue.text.trim();
    final setup = MatchSetup(
      id: newId(),
      teamA: teamA,
      teamB: teamB,
      rules: MatchRules(
        oversPerInnings: _overs,
        wideRuns: _wideCountsRun ? 1 : 0,
        noBallRuns: _noBallCountsRun ? 1 : 0,
        freeHitOnNoBall: _freeHit,
        lastManStands: _lastManStands,
        maxOversPerBowler: _limitBowlerOvers ? _maxBowlerOvers : null,
        superOver: _isSuperOver,
        trackShots: _trackShots,
      ),
      tossWinnerId: _tossWinner == 0 ? teamA.id : teamB.id,
      tossDecision: _decision,
      venue: venue.isEmpty ? null : venue,
    );
    try {
      await ref.read(matchRepositoryProvider).save(
            MatchRecord(setup: setup, events: const [], createdAt: now, updatedAt: now),
          );
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Could not save the match: $e', isError: true);
      }
      return;
    }
    await _rememberTeams(savedTeams, [teamA, teamB]);
    final fixture = widget.fixture;
    String? linkError;
    if (fixture != null && tournaments != null) {
      try {
        await tournaments.save(fixture.tournament.withMatch(fixture.fixture.id, setup.id));
      } on Object catch (e) {
        linkError = 'Match saved, but not added to the tournament: $e';
      }
    }
    if (!mounted) return;
    ref.invalidate(matchListProvider);
    ref.invalidate(savedTeamsProvider);
    if (fixture != null) ref.invalidate(tournamentsProvider);
    if (linkError != null) showMessage(context, linkError, isError: true);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => ScoringScreen(matchId: setup.id)),
    );
  }

  /// Career stats follow ids, so a team typed by hand must share the ids of the
  /// saved team with its name. Without saved teams it is simply a new team.
  Future<void> _linkTypedTeams(TeamRepository repository) async {
    final List<Team> saved;
    try {
      saved = await repository.loadAll();
    } on Object catch (e) {
      debugPrint('Loading saved teams failed: $e');
      return;
    }
    _teamA.linkByName(saved, _teamB);
    _teamB.linkByName(saved, _teamA);
  }

  /// The match is already saved, so a failure here must not stop it starting.
  Future<void> _rememberTeams(TeamRepository repository, List<Team> played) async {
    try {
      final saved = await repository.loadAll();
      for (final team in played) {
        final squad = mergeIntoSquad(saved, team);
        if (squad != null) await repository.save(squad);
      }
    } on Object catch (e) {
      debugPrint('Saving teams failed: $e');
    }
  }

  Future<void> _useSavedTeam(_TeamDraft draft, _TeamDraft other) async {
    final team = await showSavedTeamsSheet(context, excludeTeamId: other.savedTeamId);
    if (team == null || !mounted) return;
    draft.load(team);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final blocker = _blocker;
    final saved = ref.watch(savedTeamsProvider).value ?? const <Team>[];
    VoidCallback? pickFor(_TeamDraft draft, _TeamDraft other) =>
        widget.fixture == null && saved.any((t) => t.id != other.savedTeamId)
            ? () => _useSavedTeam(draft, other)
            : null;
    final teamNames = [_teamA.displayName, _teamB.displayName];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('New match'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _TeamEditor(
            draft: _teamA,
            label: 'Home',
            onChanged: _refresh,
            onUseSaved: pickFor(_teamA, _teamB),
            locked: widget.fixture != null,
          ),
          const SizedBox(height: 12),
          _TeamEditor(
            draft: _teamB,
            label: 'Away',
            onChanged: _refresh,
            onUseSaved: pickFor(_teamB, _teamA),
            locked: widget.fixture != null,
          ),
          const SizedBox(height: 12),
          if (!_isSuperOver) ...[
          OversPicker(overs: _overs, onChanged: (o) => setState(() => _overs = o)),
          const SizedBox(height: 12),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Toss'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < 2; i++) ...[
                      if (i == 1) const SizedBox(width: 10),
                      Expanded(
                        child: _TossCard(
                          name: teamNames[i],
                          selected: _tossWinner == i,
                          onTap: () => setState(() => _tossWinner = i),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text('${teamNames[_tossWinner]} won the toss and chose to', style: text.bodyMedium),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<TossDecision>(
                    segments: const [
                      ButtonSegment(
                        value: TossDecision.bat,
                        icon: Icon(Icons.sports_cricket_rounded),
                        label: Text('Bat'),
                      ),
                      ButtonSegment(
                        value: TossDecision.bowl,
                        icon: Icon(Icons.sports_baseball_rounded),
                        label: Text('Bowl'),
                      ),
                    ],
                    selected: {_decision},
                    onSelectionChanged: (s) => setState(() => _decision = s.first),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ],
          SurfacePanel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('House rules'),
                subtitle: Text(_rulesSummary()),
                children: [
                  SwitchListTile(
                    title: const Text('Wide gives 1 run'),
                    value: _wideCountsRun,
                    onChanged: (v) => setState(() => _wideCountsRun = v),
                  ),
                  SwitchListTile(
                    title: const Text('No-ball gives 1 run'),
                    value: _noBallCountsRun,
                    onChanged: (v) => setState(() => _noBallCountsRun = v),
                  ),
                  SwitchListTile(
                    title: const Text('Free hit after a no-ball'),
                    value: _freeHit,
                    onChanged: (v) => setState(() => _freeHit = v),
                  ),
                  SwitchListTile(
                    title: const Text('Last man stands'),
                    subtitle: const Text('The last batter can bat alone'),
                    value: _lastManStands,
                    onChanged: (v) => setState(() => _lastManStands = v),
                  ),
                  SwitchListTile(
                    title: const Text('Limit overs per bowler'),
                    subtitle: Text('Max $_maxBowlerOvers ${_maxBowlerOvers == 1 ? 'over' : 'overs'} each'),
                    value: _limitBowlerOvers,
                    onChanged: (v) => setState(() => _limitBowlerOvers = v),
                  ),
                  SwitchListTile(
                    title: const Text('Record shot direction'),
                    subtitle: const Text('One more tap per scoring shot, for a wagon wheel'),
                    value: _trackShots,
                    onChanged: (v) => setState(() => _trackShots = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _venue,
            textCapitalization: TextCapitalization.words,
            decoration: fieldDecoration(context, 'Ground / venue (optional)', icon: Icons.place_outlined),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (blocker != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    blocker,
                    style: text.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: blocker == null && !_saving ? _start : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start match'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _rulesSummary() {
    final parts = [
      if (!_wideCountsRun) 'no wide run',
      if (!_noBallCountsRun) 'no no-ball run',
      if (!_freeHit) 'no free hit',
      if (_lastManStands) 'last man stands',
      if (_limitBowlerOvers) 'max $_maxBowlerOvers ov/bowler',
      if (_trackShots) 'shot direction',
    ];
    return parts.isEmpty ? 'Standard rules' : parts.join(' · ');
  }
}

/// Editable team: name plus players. Kept outside the widget so the parent
/// can build the [Team] when the match starts.
class _TeamDraft {
  _TeamDraft(String hint) : name = TextEditingController(), _hint = hint;

  final TextEditingController name;
  final String _hint;
  final players = <String>[];

  /// Saved squad members left out of this match.
  final sittingOut = <String>[];
  final playerInput = TextEditingController();

  /// Set when the team came from the saved list. Reusing its ids keeps a team
  /// and its players the same across matches.
  Team? _saved;
  var _savedPlayers = <String, Player>{};

  String? get savedTeamId => _saved?.id;

  String get displayName => name.text.trim().isEmpty ? _hint : name.text.trim();

  bool isSaved(String player) => _savedPlayers.containsKey(player);

  void _useIdsOf(Team team) {
    _saved = team;
    _savedPlayers = {for (final p in team.players) p.name: p};
  }

  /// Treats a typed name as the saved team of that name. [other] may already
  /// be playing as that team, and a team cannot play itself.
  void linkByName(List<Team> saved, _TeamDraft other) {
    if (savedTeamId != null) return;
    final typed = name.text.trim().toLowerCase();
    final match = saved.where((t) => t.name.toLowerCase() == typed && t.id != other.savedTeamId);
    if (match.isNotEmpty) _useIdsOf(match.first);
  }

  void load(Team team) {
    final names = [for (final p in team.players) p.name];
    _useIdsOf(team);
    players
      ..clear()
      ..addAll(names.take(_quickFillSize));
    sittingOut
      ..clear()
      ..addAll(names.skip(_quickFillSize));
    name.text = team.name;
  }

  Team build() {
    // Taken out as used, so a repeated name still gets its own id.
    final known = {..._savedPlayers};
    return Team(
      id: savedTeamId ?? newId(),
      name: name.text.trim(),
      players: [for (final p in players) known.remove(p) ?? Player(id: newId(), name: p)],
      captainId: _saved?.captainId,
      viceCaptainId: _saved?.viceCaptainId,
      keeperId: _saved?.keeperId,
    );
  }

  void dispose() {
    name.dispose();
    playerInput.dispose();
  }
}

class _TeamEditor extends StatefulWidget {
  const _TeamEditor({
    required this.draft,
    required this.label,
    required this.onChanged,
    this.onUseSaved,
    this.locked = false,
  });

  final _TeamDraft draft;
  final String label;
  final VoidCallback onChanged;

  /// Null when there is no saved team to choose.
  final VoidCallback? onUseSaved;

  /// A tournament fixture fixes the team, so its name cannot change here.
  final bool locked;

  @override
  State<_TeamEditor> createState() => _TeamEditorState();
}

class _TeamEditorState extends State<_TeamEditor> {
  final _playerFocus = FocusNode();

  @override
  void dispose() {
    _playerFocus.dispose();
    super.dispose();
  }

  _TeamDraft get _draft => widget.draft;

  void _addPlayer() {
    final name = _draft.playerInput.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _draft.sittingOut.remove(name);
      _draft.players.add(name);
    });
    _draft.playerInput.clear();
    _playerFocus.requestFocus(); // keep typing the next name
    widget.onChanged();
  }

  /// A saved player only sits out: they stay in the squad for next time.
  void _removePlayer(int index) {
    setState(() {
      final player = _draft.players.removeAt(index);
      if (_draft.isSaved(player)) _draft.sittingOut.add(player);
    });
    widget.onChanged();
  }

  void _bringIn(String player) {
    setState(() {
      _draft.sittingOut.remove(player);
      _draft.players.add(player);
    });
    widget.onChanged();
  }

  void _quickFill() {
    setState(() {
      var n = 1;
      while (_draft.players.length < _quickFillSize) {
        final candidate = placeholderPlayerName(n);
        if (!_draft.players.contains(candidate)) _draft.players.add(candidate);
        n++;
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TeamBadge(name: _draft.displayName, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _draft.name,
                  readOnly: widget.locked,
                  textCapitalization: TextCapitalization.words,
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  decoration: fieldDecoration(context, '${widget.label} team name'),
                ),
              ),
            ],
          ),
          if (widget.onUseSaved != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: widget.onUseSaved,
              icon: const Icon(Icons.groups_rounded, size: 18),
              label: const Text('Saved teams'),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: SectionLabel('Players · ${_draft.players.length}')),
              if (_draft.players.length < _quickFillSize && _draft.sittingOut.isEmpty)
                TextButton.icon(
                  onPressed: _quickFill,
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text('Fill to $_quickFillSize'),
                ),
            ],
          ),
          if (_draft.players.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _draft.players.length; i++)
                  InputChip(
                    avatar: PlayerAvatar(name: _draft.players[i], radius: 12),
                    label: Text(_draft.players[i]),
                    onDeleted: () => _removePlayer(i),
                  ),
              ],
            ),
          ],
          if (_draft.sittingOut.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionLabel('Sitting out · ${_draft.sittingOut.length}'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final player in _draft.sittingOut)
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: Text(player),
                    onPressed: () => _bringIn(player),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _draft.playerInput,
            focusNode: _playerFocus,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addPlayer(),
            decoration: fieldDecoration(
              context,
              'Add player name',
              icon: Icons.person_add_alt_1_rounded,
              suffix: IconButton(
                tooltip: 'Add player',
                onPressed: _addPlayer,
                icon: const Icon(Icons.add_circle_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TossCard extends StatelessWidget {
  const _TossCard({required this.name, required this.selected, required this.onTap});

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        gradient: selected ? AppColors.heroGradient : null,
        color: selected ? null : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppColors.neon.withValues(alpha: 0.6) : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: selected ? AppColors.glow(AppColors.neon, strength: 0.2, blur: 16) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              children: [
                Icon(
                  selected ? Icons.emoji_events_rounded : Icons.circle_outlined,
                  color: selected ? AppColors.neon : scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
