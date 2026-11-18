import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ids.dart';
import '../data/squad_import.dart';
import '../state/providers.dart';
import '../ui/feedback.dart';
import '../ui/format.dart';
import '../ui/inputs.dart';
import '../widgets/avatars.dart';
import '../widgets/paste_players_sheet.dart';
import '../widgets/scoring_sheets.dart';
import '../widgets/surface_panel.dart';

/// Creates a team, or edits a saved squad. Past matches keep their own copy of
/// the team, so nothing here changes an old scorecard.
class TeamEditScreen extends ConsumerStatefulWidget {
  const TeamEditScreen({super.key, this.team});

  /// Null for a new team.
  final Team? team;

  @override
  ConsumerState<TeamEditScreen> createState() => _TeamEditScreenState();
}

class _TeamEditScreenState extends ConsumerState<TeamEditScreen> {
  final _name = TextEditingController();
  final _playerInput = TextEditingController();
  final _players = <Player>[];
  String? _captainId;
  String? _viceCaptainId;
  String? _keeperId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final team = widget.team;
    if (team != null) {
      _name.text = team.name;
      _players.addAll(team.players);
      _captainId = team.captainId;
      _viceCaptainId = team.viceCaptainId;
      _keeperId = team.keeperId;
    }
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _playerInput.dispose();
    super.dispose();
  }

  String? _blocker(List<Team> saved) {
    final name = _name.text.trim();
    if (name.isEmpty) return 'Give the team a name';
    if (saved.any((t) => t.id != widget.team?.id && t.name.toLowerCase() == name.toLowerCase())) {
      return 'There is already a team called $name';
    }
    if (_players.length < 2) return 'Add at least 2 players';
    return null;
  }

  void _addPlayer() {
    final name = _playerInput.text.trim();
    if (name.isEmpty) return;
    setState(() => _players.add(Player(id: newId(), name: name)));
    _playerInput.clear();
  }

  /// Adds a list pasted from WhatsApp; its (c), (vc) and (wk) marks apply.
  Future<void> _pasteList() async {
    final incoming = await showPastePlayersSheet(context, existing: _players.map((p) => p.name));
    if (incoming == null || !mounted) return;
    final update = addToSquad(
      players: _players,
      captainId: _captainId,
      viceCaptainId: _viceCaptainId,
      keeperId: _keeperId,
      incoming: incoming,
      newId: newId,
    );
    setState(() {
      _players
        ..clear()
        ..addAll(update.players);
      _captainId = update.captainId;
      _viceCaptainId = update.viceCaptainId;
      _keeperId = update.keeperId;
    });
    showMessage(context, 'Added ${plural(update.added, 'player')}.');
  }

  void _replace(Player player, {String? name, PlayerRole? role}) {
    final i = _players.indexWhere((p) => p.id == player.id);
    setState(() {
      _players[i] = Player(id: player.id, name: name ?? player.name, role: role ?? player.role);
    });
  }

  void _remove(Player player) => setState(() {
        _players.removeWhere((p) => p.id == player.id);
        if (_captainId == player.id) _captainId = null;
        if (_viceCaptainId == player.id) _viceCaptainId = null;
        if (_keeperId == player.id) _keeperId = null;
      });

  /// Captain and vice-captain are different people.
  void _makeCaptain(Player player) => setState(() {
        _captainId = player.id;
        if (_viceCaptainId == player.id) _viceCaptainId = null;
      });

  void _makeViceCaptain(Player player) => setState(() {
        _viceCaptainId = player.id;
        if (_captainId == player.id) _captainId = null;
      });

  void _makeKeeper(Player player) => setState(() => _keeperId = player.id);

  Future<void> _rename(Player player) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(name: player.name),
    );
    if (name != null && name.isNotEmpty) _replace(player, name: name);
  }

  Future<void> _showPlayerActions(Player player) async {
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        void choose(VoidCallback action) => Navigator.of(sheetContext).pop(action);
        Widget tile(IconData icon, String label, VoidCallback action) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(label),
              onTap: () => choose(action),
            );
        return SheetBody(
          title: player.name,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Role'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final role in PlayerRole.values)
                    ChoiceChip(
                      label: Text(role.label),
                      selected: player.role == role,
                      onSelected: (_) => choose(() => _replace(player, role: role)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              tile(Icons.star_rounded, 'Make captain', () => _makeCaptain(player)),
              tile(Icons.star_half_rounded, 'Make vice-captain', () => _makeViceCaptain(player)),
              tile(Icons.sports_handball_rounded, 'Make wicket-keeper', () => _makeKeeper(player)),
              tile(Icons.edit_rounded, 'Rename', () => _rename(player)),
              tile(Icons.person_remove_rounded, 'Remove from squad', () => _remove(player)),
            ],
          ),
        );
      },
    );
    action?.call();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final team = Team(
      id: widget.team?.id ?? newId(),
      name: _name.text.trim(),
      players: _players,
      captainId: _captainId,
      viceCaptainId: _viceCaptainId,
      keeperId: _keeperId,
    );
    try {
      await ref.read(teamRepositoryProvider).save(team);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Could not save the team: $e', isError: true);
      }
      return;
    }
    if (!mounted) return;
    ref.invalidate(savedTeamsProvider);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final team = widget.team;
    if (team == null) return;
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
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repository = ref.read(teamRepositoryProvider);
    try {
      await repository.delete(team.id);
    } on Object catch (e) {
      if (mounted) showMessage(context, 'Could not delete the team: $e', isError: true);
      return;
    }
    if (!mounted) return;
    ref.invalidate(savedTeamsProvider);
    Navigator.of(context).pop();
  }

  String _subtitle(Player player) => [
        if (player.id == _captainId) 'Captain',
        if (player.id == _viceCaptainId) 'Vice-captain',
        if (player.id == _keeperId) 'Wicket-keeper',
        ?player.role?.label,
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedTeamsProvider).value ?? const <Team>[];
    final blocker = _blocker(saved);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.team == null ? 'New team' : 'Edit team'),
        actions: [
          if (widget.team != null)
            IconButton(
              tooltip: 'Delete team',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: fieldDecoration(context, 'Team name', icon: Icons.groups_rounded),
          ),
          const SizedBox(height: 12),
          SurfacePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel('Squad · ${_players.length}'),
                const SizedBox(height: 4),
                for (final player in _players)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: PlayerAvatar(name: player.name),
                    title: Text(player.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: _subtitle(player).isEmpty
                        ? null
                        : Text(_subtitle(player), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.more_horiz_rounded),
                    onTap: () => _showPlayerActions(player),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: _playerInput,
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
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _pasteList,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Paste a list'),
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
              if (blocker != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    blocker,
                    style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              FilledButton.icon(
                onPressed: blocker == null && !_saving ? _save : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save team'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});

  final String name;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rename player'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: fieldDecoration(context, 'Player name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      );
}
