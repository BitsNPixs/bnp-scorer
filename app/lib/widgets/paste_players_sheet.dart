import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/squad_import.dart';
import '../ui/format.dart';
import '../ui/inputs.dart';
import 'avatars.dart';
import 'scoring_sheets.dart';
import 'surface_panel.dart';

/// Asks for a list of names, as it arrives on WhatsApp, and returns the
/// players to add, or null if the scorer backs out. Names already in
/// [existing] are left out. With [showMarks], captain, keeper and role marks
/// read from the list show on each name; New match takes names only.
Future<List<ImportedPlayer>?> showPastePlayersSheet(
  BuildContext context, {
  required Iterable<String> existing,
  bool showMarks = true,
}) =>
    showModalBottomSheet<List<ImportedPlayer>>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _PastePlayersSheet(existing: {for (final n in existing) n.toLowerCase()}, showMarks: showMarks),
    );

class _PastePlayersSheet extends StatefulWidget {
  const _PastePlayersSheet({required this.existing, required this.showMarks});

  final Set<String> existing;
  final bool showMarks;

  @override
  State<_PastePlayersSheet> createState() => _PastePlayersSheetState();
}

class _PastePlayersSheetState extends State<_PastePlayersSheet> {
  final _input = TextEditingController();

  /// Names the scorer took out of the preview, lower case.
  final _dropped = <String>{};

  /// Likely headings the scorer brought back in, lower case.
  final _restored = <String>{};

  bool _isOut(ImportedPlayer p) {
    final key = p.name.toLowerCase();
    return _dropped.contains(key) || (p.likelyHeading && !_restored.contains(key));
  }

  void _takeOff(ImportedPlayer p) => setState(() {
        _dropped.add(p.name.toLowerCase());
        _restored.remove(p.name.toLowerCase());
      });

  void _bringBack(ImportedPlayer p) => setState(() {
        _dropped.remove(p.name.toLowerCase());
        _restored.add(p.name.toLowerCase());
      });

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _fillFromClipboard();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Saves a tap: a list already copied from WhatsApp is pasted in for the
  /// scorer to check. A single copied word is left alone.
  Future<void> _fillFromClipboard() async {
    final String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      return; // no clipboard here; the field just starts empty
    }
    if (!mounted || text == null || _input.text.isNotEmpty) return;
    if (parsePlayerList(text).length >= 2) _input.text = text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final found = parsePlayerList(_input.text);
    final already = found.where((p) => widget.existing.contains(p.name.toLowerCase())).length;
    final fresh = [for (final p in found) if (!widget.existing.contains(p.name.toLowerCase())) p];
    final chosen = [for (final p in fresh) if (!_isOut(p)) p];
    return SheetBody(
      title: 'Paste players',
      subtitle: widget.showMarks
          ? 'One name per line. Numbers and emoji are skipped, and (c), (vc) and (wk) are read.'
          : 'One name per line. Numbers, emoji and marks like (c) are skipped.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('paste-list'),
            controller: _input,
            minLines: 4,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.words,
            decoration: fieldDecoration(context, 'Paste the list here'),
          ),
          const SizedBox(height: 16),
          SectionLabel('Adding · ${chosen.length}'),
          const SizedBox(height: 8),
          if (fresh.isEmpty)
            Text(
              found.isEmpty ? 'Names show here as you paste.' : 'Everyone in this list is already in the team.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in fresh)
                  _isOut(p)
                      ? ActionChip(
                          avatar: const Icon(Icons.add_rounded, size: 18),
                          label: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onPressed: () => _bringBack(p),
                        )
                      : InputChip(
                          avatar: PlayerAvatar(name: p.name, radius: 12),
                          label: Text(
                            widget.showMarks && p.marks.isNotEmpty ? '${p.name} · ${p.marks.join(', ')}' : p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () => _takeOff(p),
                        ),
              ],
            ),
          if (already > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${plural(already, 'name')} already in the team, left out.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: chosen.isEmpty ? null : () => Navigator.of(context).pop(chosen),
            icon: const Icon(Icons.playlist_add_rounded),
            label: Text(chosen.isEmpty ? 'Add players' : 'Add ${plural(chosen.length, 'player')}'),
          ),
        ],
      ),
    );
  }
}
