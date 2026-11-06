import 'dart:math';

final _random = Random.secure();

/// Short, sortable, collision-resistant id (time + randomness). Safe to
/// generate offline on several devices at once.
String newId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = List.generate(6, (_) => _random.nextInt(36).toRadixString(36)).join();
  return '$time$rand';
}
