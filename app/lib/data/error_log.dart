import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One uncaught error. The same error repeated back to back (an error while
/// drawing repeats every frame) is one entry with a [count].
class ErrorEntry {
  const ErrorEntry({required this.at, required this.error, required this.stack, this.count = 1});

  factory ErrorEntry.fromJson(Map<String, Object?> json) => ErrorEntry(
        at: DateTime.parse(json['at']! as String),
        error: json['error']! as String,
        stack: json['stack'] as String? ?? '',
        count: json['count'] as int? ?? 1,
      );

  /// When it last happened.
  final DateTime at;
  final String error;

  /// The top of the stack trace.
  final String stack;
  final int count;

  Map<String, Object?> toJson() =>
      {'at': at.toUtc().toIso8601String(), 'error': error, 'stack': stack, 'count': count};
}

/// Recent uncaught errors, kept on the phone so a scorer can send them with
/// "Report a problem". Nothing leaves the phone unless they share it.
class ErrorLog {
  ErrorLog(this._prefs, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  static const key = 'bnp_scorer.errorLog';
  static const maxEntries = 20;
  static const _stackLines = 12;
  static const _maxErrorLength = 1000;

  /// Newest first. An unreadable log reads as empty rather than failing.
  List<ErrorEntry> get entries {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List<Object?>) ErrorEntry.fromJson(e! as Map<String, Object?>),
      ];
    } on Object catch (e) {
      debugPrint('Ignoring an unreadable error log: $e');
      return const [];
    }
  }

  /// Never throws: it runs inside the app's error handlers.
  void record(Object error, StackTrace? stack) {
    try {
      var text = '$error';
      if (text.length > _maxErrorLength) text = '${text.substring(0, _maxErrorLength)}…';
      final trace = '${stack ?? ''}'
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(_stackLines)
          .join('\n');
      final now = _clock();
      final previous = entries;
      final last = previous.isEmpty ? null : previous.first;
      final updated = last != null && last.error == text && last.stack == trace
          ? [ErrorEntry(at: now, error: text, stack: trace, count: last.count + 1), ...previous.skip(1)]
          : [ErrorEntry(at: now, error: text, stack: trace), ...previous.take(maxEntries - 1)];
      // The in-memory copy updates at once; the write to disk follows.
      unawaited(_prefs
          .setString(key, jsonEncode([for (final e in updated) e.toJson()]))
          .catchError((Object _) => false));
    } on Object catch (e) {
      debugPrint('Could not record an error: $e');
    }
  }
}

/// The text "Report a problem" shares: version, phone, a space for the
/// scorer's own words, then the recent errors.
String problemReport({
  required List<ErrorEntry> errors,
  required String version,
  required String platform,
  required DateTime now,
}) {
  String time(DateTime t) => t.toLocal().toString().substring(0, 16);
  final out = StringBuffer()
    ..writeln('BNP Scorer problem report')
    ..writeln('Version $version on $platform')
    ..writeln('Sent ${time(now)}')
    ..writeln()
    ..writeln('What went wrong? Write it here:')
    ..writeln()
    ..writeln()
    ..writeln();
  if (errors.isEmpty) {
    out.writeln('No errors were recorded on this phone.');
  } else {
    out.writeln('Recent errors, newest first:');
    for (final (i, e) in errors.indexed) {
      out
        ..writeln()
        ..writeln('${i + 1}. ${time(e.at)}${e.count > 1 ? ' (${e.count} times)' : ''}')
        ..writeln(e.error);
      if (e.stack.isNotEmpty) out.writeln(e.stack);
    }
  }
  return out.toString();
}
