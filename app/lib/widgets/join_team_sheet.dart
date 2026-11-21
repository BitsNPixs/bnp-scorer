import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloud_teams.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/format.dart';
import '../ui/inputs.dart';
import 'avatars.dart';
import 'scoring_sheets.dart';
import 'surface_panel.dart';

/// A player types a team's join code and asks to join. Their captain then
/// adds them from the team's page. Returns the team's name once asked.
Future<String?> showJoinTeamSheet(BuildContext context, {String? code}) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _JoinTeamSheet(code: code),
    );

class _JoinTeamSheet extends ConsumerStatefulWidget {
  const _JoinTeamSheet({this.code});

  final String? code;

  @override
  ConsumerState<_JoinTeamSheet> createState() => _JoinTeamSheetState();
}

class _JoinTeamSheetState extends ConsumerState<_JoinTeamSheet> {
  late final _code = TextEditingController(text: widget.code ?? '');
  PublishedTeam? _team;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Opened from an invite link: look the code up straight away.
    if (widget.code != null) WidgetsBinding.instance.addPostFrameCallback((_) => _find());
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _fail(String message) => setState(() {
        _error = message;
        _busy = false;
      });

  Future<void> _find() async {
    if (!mounted) return;
    final code = normalizeJoinCode(_code.text);
    if (code == null) return _fail('A join code is 6 letters and numbers, like ${joinCodeOf('example')}.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final team = await ref.read(cloudTeamsProvider)!.teamByCode(code);
      if (!mounted) return;
      if (team == null) return _fail('No team has that code. Check it with your captain.');
      setState(() {
        _team = team;
        _busy = false;
      });
    } on Object catch (e) {
      if (mounted) _fail('Could not reach the cloud. Check your connection and try again.');
      debugPrint('Looking up a join code failed: $e');
    }
  }

  Future<void> _ask() async {
    final team = _team!;
    if (ref.read(accountsProvider).current == null) return _fail('Sign in from Settings first.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final me = await ref.read(myProfileProvider.future);
      if (!mounted) return;
      if (me == null) {
        return _fail('Add your mobile number in Settings first: your captain adds you by your profile.');
      }
      if (team.team.hasPlayer(me.id)) return _fail('You are already in ${team.team.name}.');
      await ref.read(cloudTeamsProvider)!.requestJoin(team.team.id, playerId: me.id, name: me.name);
      if (mounted) Navigator.of(context).pop(team.team.name);
    } on Object catch (e) {
      if (mounted) _fail('Could not send the request. Check your connection and try again.');
      debugPrint('Asking to join failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final team = _team;
    final error = _error;
    return SheetBody(
      title: 'Join a team',
      subtitle: 'Type the code your captain sent. They add you, and the matches you play count on your profile.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('join-code'),
            controller: _code,
            autofocus: widget.code == null,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [LengthLimitingTextInputFormatter(8)],
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _find(),
            onChanged: (_) {
              if (_team != null) setState(() => _team = null);
            },
            decoration: fieldDecoration(context, 'Join code', icon: Icons.key_rounded),
          ),
          const SizedBox(height: 12),
          if (team == null)
            FilledButton(onPressed: _busy ? null : _find, child: const Text('Find team'))
          else ...[
            SurfacePanel(
              child: Row(
                children: [
                  TeamBadge(name: team.team.name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          team.team.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${plural(team.team.players.length, 'player')} · Shared by ${team.ownerName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _ask, child: const Text('Ask to join')),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error, style: TextStyle(color: scheme.error)),
          ],
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(color: AppColors.neon),
          ],
        ],
      ),
    );
  }
}
