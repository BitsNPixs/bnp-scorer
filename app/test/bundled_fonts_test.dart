import 'dart:io';

import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  // Unlike the other tests, this one loads the real fonts, from the assets only.
  setUpAll(() {
    AppFonts.useGoogleFonts = true;
    AppFonts.useBundledFonts();
  });

  /// Runs [body] and returns what it printed. google_fonts reports a failed
  /// load with debugPrint, and Flutter checks debugPrint is restored before
  /// tear-down runs, hence try/finally rather than addTearDown.
  Future<List<String>> printedBy(Future<void> Function() body) async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    try {
      await body();
    } finally {
      debugPrint = original;
    }
    return logs;
  }

  test('nothing is ever downloaded', () {
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
  });

  // A missing file makes google_fonts throw inside the frame, which stalls the
  // test rather than failing it, hence the short timeouts.
  testWidgets(
    'every weight the app draws loads from the bundled files',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      final logs = await printedBy(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: SingleChildScrollView(
              child: Column(
                children: [
                  for (final style in [
                    for (final w in AppFonts.interWeights) GoogleFonts.inter(fontWeight: w),
                    for (final w in AppFonts.displayWeights) scoreStyle(20, weight: w),
                    for (final w in AppFonts.displayItalicWeights)
                      AppFonts.display(TextStyle(fontWeight: w, fontStyle: FontStyle.italic)),
                    // The themes themselves, light and dark.
                    for (final t in [AppTheme.light(), AppTheme.dark()]) ...[
                      t.textTheme.bodyMedium!,
                      t.textTheme.titleMedium!,
                      t.textTheme.labelSmall!,
                      t.textTheme.headlineSmall!,
                      t.textTheme.titleLarge!,
                      t.appBarTheme.titleTextStyle!,
                    ],
                  ])
                    Text('42 Runs', style: style),
                ],
              ),
            ),
          ),
        );
        await tester.runAsync(GoogleFonts.pendingFonts);
      });
      expect(logs.where((l) => l.contains('unable to load font')), isEmpty, reason: logs.join('\n'));
    },
  );

  testWidgets(
    'preload loads every bundled font, so the first frame never uses a fallback',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      final logs = await printedBy(() async => tester.runAsync(AppFonts.preload));
      expect(logs, isEmpty, reason: logs.join('\n'));
    },
  );

  testWidgets('the asset list google_fonts searches holds every file', (tester) async {
    final manifest = await tester.runAsync(() => AssetManifest.loadFromAssetBundle(rootBundle));
    final assets = manifest!.listAssets();
    for (final name in _expectedFiles) {
      expect(assets, contains('${AppFonts.assetFolder}/$name'), reason: name);
    }
  });

  test('each bundled file is a TrueType font named the way google_fonts looks for it', () {
    for (final name in _expectedFiles) {
      final file = File('${AppFonts.assetFolder}/$name');
      expect(file.existsSync(), isTrue, reason: name);
      expect(file.readAsBytesSync().take(4), [0, 1, 0, 0], reason: '$name is not a TrueType file');
    }
  });

  testWidgets('the font licences are listed in the app', (tester) async {
    final entries = await tester.runAsync(() => LicenseRegistry.licenses.toList());
    for (final family in ['Inter', 'Barlow Condensed']) {
      final entry = entries!.where((e) => e.packages.contains(family));
      expect(entry, hasLength(1), reason: family);
      final text = entry.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'), reason: family);
    }
  });
}

final _expectedFiles = [
  for (final w in AppFonts.interWeights) 'Inter-${_name(w)}.ttf',
  for (final w in AppFonts.displayWeights) 'BarlowCondensed-${_name(w)}.ttf',
  for (final w in AppFonts.displayItalicWeights) 'BarlowCondensed-${_name(w)}Italic.ttf',
];

/// google_fonts' file name part for a weight, e.g. 600 → SemiBold.
String _name(FontWeight weight) => const {
  400: 'Regular',
  500: 'Medium',
  600: 'SemiBold',
  700: 'Bold',
  800: 'ExtraBold',
  900: 'Black',
}[weight.value]!;
