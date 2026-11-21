import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/device_contacts.dart';
import '../data/phone_numbers.dart';
import '../data/player_directory.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/inputs.dart';
import 'avatars.dart';
import 'scoring_sheets.dart';
import 'surface_panel.dart';

/// Shown when a signed-out scorer tries to add a player by number.
const signInToAddByNumber = 'Sign in from Settings to add players by number.';

/// Finds a player by mobile number for a captain building a squad, or
/// invites them under it when nobody has that number yet. Returns the player
/// to add, or null. [inTeam] holds the ids already in the team. Needs the
/// player directory and a signed-in scorer.
Future<PlayerProfile?> showAddByNumberSheet(BuildContext context, {required Set<String> inTeam}) =>
    showModalBottomSheet<PlayerProfile>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _AddByNumberSheet(inTeam: inTeam),
    );

/// Asks whether a player found by number is [name], already in the team.
/// True to link them, false for someone else, null when dismissed.
Future<bool?> confirmSamePlayer(BuildContext context, String name) => showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Same person as $name?'),
        content: const Text('Then their matches here and their profile count as one player.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Someone else'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Same person'),
          ),
        ],
      ),
    );

class _AddByNumberSheet extends ConsumerStatefulWidget {
  const _AddByNumberSheet({required this.inTeam});

  final Set<String> inTeam;

  @override
  ConsumerState<_AddByNumberSheet> createState() => _AddByNumberSheetState();
}

class _AddByNumberSheetState extends ConsumerState<_AddByNumberSheet> {
  final _number = TextEditingController();
  final _name = TextEditingController();

  /// The number looked up, once a lookup has answered.
  String? _searched;
  PlayerProfile? _found;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  void _fail(String message) => setState(() {
        _error = message;
        _busy = false;
      });

  Future<void> _find() async {
    final e164 = normalizePhone(_number.text);
    if (e164 == null) return _fail('Type a 10-digit mobile number, or one with its + code.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found = await ref.read(playerDirectoryProvider)!.lookupByPhone(e164);
      if (!mounted) return;
      setState(() {
        _searched = e164;
        _found = found;
        _busy = false;
      });
    } on PlayerDirectoryException catch (e) {
      if (mounted) _fail(e.message);
    }
  }

  /// Fills the number from the phone's contact picker and looks it up, with
  /// the contact's name ready in case nobody has joined with it.
  Future<void> _pickContact() async {
    final PickedContact? contact;
    try {
      contact = await ref.read(deviceContactsProvider).pickContact();
    } on DeviceContactsException catch (e) {
      if (mounted) _fail(e.message);
      return;
    }
    if (contact == null || !mounted) return;
    final e164 = normalizePhone(contact.number);
    if (e164 == null) {
      final who = contact.name.isEmpty ? 'That contact' : contact.name;
      return _fail('$who has no mobile number the app can use.');
    }
    _number.text = e164;
    _name.text = contact.name;
    setState(() {
      _searched = null;
      _found = null;
    });
    await _find();
  }

  Future<void> _invite() async {
    final name = _name.text.trim();
    final number = _searched!;
    if (name.isEmpty) return _fail('Type their name.');
    final scorer = ref.read(accountsProvider).current;
    if (scorer == null) return _fail(signInToAddByNumber);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final player = await ref.read(playerDirectoryProvider)!.invite(name, number, scorer);
      if (mounted) Navigator.of(context).pop(player);
    } on PlayerDirectoryException catch (e) {
      if (mounted) _fail(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final searched = _searched;
    final found = _found;
    final error = _error;
    final inTeam = found != null && widget.inTeam.contains(found.id);
    final spinner = SizedBox.square(
      dimension: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.night.withValues(alpha: 0.7)),
    );
    return SheetBody(
      title: 'Add by mobile number',
      subtitle: 'A player who has joined BNP Scorer brings their profile and career with them.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('find-number'),
            controller: _number,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _find(),
            // A changed number needs a new lookup.
            onChanged: (_) {
              if (_searched != null) {
                setState(() {
                  _searched = null;
                  _found = null;
                });
              }
            },
            decoration: fieldDecoration(context, '98765 43210', icon: Icons.phone_rounded),
          ),
          const SizedBox(height: 12),
          if (searched == null) ...[
            FilledButton(onPressed: _busy ? null : _find, child: _busy ? spinner : const Text('Find')),
            if (ref.watch(deviceContactsProvider).available)
              TextButton.icon(
                onPressed: _busy ? null : _pickContact,
                icon: const Icon(Icons.contacts_rounded, size: 18),
                label: const Text('Pick from contacts'),
              ),
          ]
          else if (found != null) ...[
            SurfacePanel(
              child: Row(
                children: [
                  PlayerAvatar(name: found.name, photoUrl: found.photoUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          found.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          found.claimed ? 'Verified player' : 'Invited by a captain, not joined yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (found.claimed) const Icon(Icons.verified_rounded, color: AppColors.neonDeep),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: inTeam ? null : () => Navigator.of(context).pop(found),
              child: Text(inTeam ? 'Already in the team' : 'Add to team'),
            ),
          ] else ...[
            Text(
              'Nobody has joined with this number yet. Add them by name: when they join with it, '
              'these matches become theirs.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('invite-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _invite(),
              decoration: fieldDecoration(context, 'Their name', icon: Icons.person_rounded),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _invite, child: _busy ? spinner : const Text('Add as invited')),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}
