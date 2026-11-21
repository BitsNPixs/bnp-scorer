import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/player_directory.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../ui/inputs.dart';
import 'scoring_sheets.dart';
import 'surface_panel.dart';

/// Lets a player edit their own profile: name, role, batting and bowling
/// style, home town. Tapping a chosen chip again clears it.
Future<void> showEditProfileSheet(BuildContext context, PlayerProfile profile) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _EditProfileSheet(profile: profile),
    );

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});

  final PlayerProfile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _town = TextEditingController(text: widget.profile.homeTown ?? '');
  late PlayerRole? _role = widget.profile.role;
  late BattingStyle? _batting = widget.profile.battingStyle;
  late BowlingArm? _arm = widget.profile.bowlingArm;
  late BowlingType? _type = widget.profile.bowlingType;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _town.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Your name cannot be empty.');
      return;
    }
    final town = _town.text.trim();
    final p = widget.profile;
    final updated = PlayerProfile(
      id: p.id,
      name: name,
      ownerUid: p.ownerUid,
      role: _role,
      battingStyle: _batting,
      bowlingArm: _arm,
      bowlingType: _type,
      homeTown: town.isEmpty ? null : town,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(playerDirectoryProvider)!.saveDetails(updated);
      if (mounted) Navigator.of(context).pop();
    } on PlayerDirectoryException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _saving = false;
        });
      }
    }
  }

  Widget _choice<T>(String label, List<T> options, String Function(T) labelOf, T? selected, ValueChanged<T?> set) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(label),
            const SizedBox(height: 8),
            OptionChips<T>(
              options: options,
              labelOf: labelOf,
              selected: selected,
              color: AppColors.neon,
              onSelected: (o) => setState(() => set(o == selected ? null : o)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final limit = [LengthLimitingTextInputFormatter(profileTextLimit)];
    return SheetBody(
      title: 'Edit profile',
      subtitle: 'Everyone can see this. Your number never shows.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('profile-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            inputFormatters: limit,
            decoration: fieldDecoration(context, 'Your name', icon: Icons.person_rounded),
          ),
          _choice('Role', PlayerRole.values, (r) => r.label, _role, (v) => _role = v),
          _choice('Batting', BattingStyle.values, (b) => b.label, _batting, (v) => _batting = v),
          _choice('Bowling arm', BowlingArm.values, (a) => a.label, _arm, (v) => _arm = v),
          _choice(
            'Bowling',
            BowlingType.values,
            (t) => t.label[0].toUpperCase() + t.label.substring(1),
            _type,
            (v) => _type = v,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('profile-town'),
            controller: _town,
            textCapitalization: TextCapitalization.words,
            inputFormatters: limit,
            decoration: fieldDecoration(context, 'Home town or area', icon: Icons.place_rounded),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        ],
      ),
    );
  }
}
