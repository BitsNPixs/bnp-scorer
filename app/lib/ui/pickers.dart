import 'package:flutter/material.dart';

import 'inputs.dart';

/// A day, then a time. Null if either is cancelled.
Future<DateTime?> pickDateTime(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  final start = initial?.toLocal() ?? DateTime(now.year, now.month, now.day, 9);
  final day = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 2),
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
  if (time == null) return null;
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}

/// Asks for a ground. Pops with the text, empty to clear it, or null if
/// cancelled.
Future<String?> askGround(BuildContext context, {String? current}) => showDialog<String>(
      context: context,
      builder: (_) => _GroundDialog(current: current),
    );

class _GroundDialog extends StatefulWidget {
  const _GroundDialog({this.current});

  final String? current;

  @override
  State<_GroundDialog> createState() => _GroundDialogState();
}

class _GroundDialogState extends State<_GroundDialog> {
  late final _ground = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _ground.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ground'),
        content: TextField(
          key: const ValueKey('ground'),
          controller: _ground,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: fieldDecoration(context, 'Ground / venue', icon: Icons.place_outlined),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(_ground.text.trim()), child: const Text('Save')),
        ],
      );
}
