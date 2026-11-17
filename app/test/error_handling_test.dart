import 'dart:ui';

import 'package:bnp_scorer/data/error_log.dart';
import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/ui/error_handling.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  var now = DateTime.utc(2026, 11, 17, 10);

  Future<(ErrorLog, SharedPreferences)> freshLog([Map<String, Object> stored = const {}]) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    return (ErrorLog(prefs, clock: () => now), prefs);
  }

  group('ErrorLog', () {
    test('keeps errors newest first, and they survive a restart', () async {
      final (log, prefs) = await freshLog();
      expect(log.entries, isEmpty);
      log.record(StateError('first'), StackTrace.fromString('#0 a\n#1 b'));
      now = now.add(const Duration(minutes: 1));
      log.record(const FormatException('second'), null);

      final entries = ErrorLog(prefs).entries;
      expect(entries.map((e) => e.error), ['FormatException: second', 'Bad state: first']);
      expect(entries.last.stack, '#0 a\n#1 b');
      expect(entries.first.stack, isEmpty);
      expect(entries.first.at, now);
    });

    test('counts the same error repeated back to back as one entry', () async {
      final (log, _) = await freshLog();
      final stack = StackTrace.fromString('#0 build');
      for (var i = 0; i < 3; i++) {
        log.record(StateError('drawing failed'), stack);
      }
      log.record(StateError('other'), stack);
      log.record(StateError('drawing failed'), stack);

      expect(log.entries.map((e) => (e.error, e.count)), [
        ('Bad state: drawing failed', 1),
        ('Bad state: other', 1),
        ('Bad state: drawing failed', 3),
      ]);
    });

    test('keeps only the latest entries, short messages and the top of the stack', () async {
      final (log, _) = await freshLog();
      final longStack = StackTrace.fromString([for (var i = 0; i < 40; i++) '#$i frame'].join('\n'));
      for (var i = 0; i < ErrorLog.maxEntries + 5; i++) {
        log.record(StateError('error $i ${'x' * 2000}'), longStack);
      }
      final entries = log.entries;
      expect(entries, hasLength(ErrorLog.maxEntries));
      expect(entries.first.error, startsWith('Bad state: error ${ErrorLog.maxEntries + 4} '));
      expect(entries.first.error.length, lessThanOrEqualTo(1001));
      expect(entries.first.stack.split('\n'), hasLength(12));
    });

    test('an unreadable log reads as empty and is replaced by the next error', () async {
      final (log, _) = await freshLog({ErrorLog.key: 'not json'});
      expect(log.entries, isEmpty);
      log.record(StateError('after'), null);
      expect(log.entries.single.error, 'Bad state: after');
    });

    test('recording never throws, even when the error cannot be printed', () async {
      final (log, _) = await freshLog();
      expect(() => log.record(_Unprintable(), null), returnsNormally);
      expect(log.entries, isEmpty);
    });
  });

  group('problemReport', () {
    final at = DateTime(2026, 11, 17, 9, 5);

    test('lists the version, phone and errors under a space to write in', () {
      final report = problemReport(
        errors: [
          ErrorEntry(at: at, error: 'Bad state: boom', stack: '#0 main', count: 4),
          ErrorEntry(at: at, error: 'FormatException: bad', stack: ''),
        ],
        version: '0.1.0 (build 1)',
        platform: 'android 15',
        now: at,
      );
      expect(report, startsWith('BNP Scorer problem report\nVersion 0.1.0 (build 1) on android 15\n'));
      expect(report, contains('What went wrong? Write it here:'));
      expect(report, contains('1. 2026-11-17 09:05 (4 times)\nBad state: boom\n#0 main'));
      expect(report, contains('2. 2026-11-17 09:05\nFormatException: bad'));
      expect(report.indexOf('Write it here'), lessThan(report.indexOf('Bad state')));
    });

    test('says so when nothing went wrong', () {
      final report = problemReport(errors: const [], version: '0.1.0 (build 1)', platform: 'android', now: at);
      expect(report, contains('No errors were recorded on this phone.'));
    });
  });

  group('installErrorHandlers', () {
    testWidgets('records Flutter and uncaught errors and swaps the error box', (tester) async {
      final (log, _) = await freshLog();
      final flutterHandler = FlutterError.onError;
      final platformHandler = PlatformDispatcher.instance.onError;
      final errorBuilder = ErrorWidget.builder;
      final presented = <FlutterErrorDetails>[];
      FlutterError.onError = presented.add;
      try {
        installErrorHandlers(log);

        final details = FlutterErrorDetails(exception: StateError('layout'), stack: StackTrace.current);
        FlutterError.onError!(details);
        expect(presented, [details], reason: 'still printed to the console');

        expect(PlatformDispatcher.instance.onError!(StateError('async'), StackTrace.empty), isTrue);
        expect(log.entries.map((e) => e.error), ['Bad state: async', 'Bad state: layout']);

        expect(ErrorWidget.builder(details), isA<FriendlyErrorPanel>());
      } finally {
        FlutterError.onError = flutterHandler;
        PlatformDispatcher.instance.onError = platformHandler;
        ErrorWidget.builder = errorBuilder;
      }
    });
  });

  group('FriendlyErrorPanel', () {
    testWidgets('reads on a phone screen, with no theme around it', (tester) async {
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const FriendlyErrorPanel());

      expect(find.text(FriendlyErrorPanel.message), findsOneWidget);
      expect(find.text(FriendlyErrorPanel.hint), findsOneWidget);
      final message = tester.getRect(find.text(FriendlyErrorPanel.message));
      expect(message.left, greaterThanOrEqualTo(0));
      expect(message.right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    });

    testWidgets('scales down in a small slot instead of overflowing', (tester) async {
      await tester.pumpWidget(const Center(
        child: SizedBox(width: 80, height: 40, child: FriendlyErrorPanel()),
      ));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(FriendlyErrorPanel)), const Size(80, 40));
      final message = tester.getRect(find.text(FriendlyErrorPanel.message));
      final slot = tester.getRect(find.byType(FriendlyErrorPanel));
      expect(slot.contains(message.center), isTrue);
    });
  });
}

class _Unprintable {
  @override
  String toString() => throw UnsupportedError('no text');
}
