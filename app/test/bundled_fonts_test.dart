import 'dart:io';

import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Every weight and style the app draws. A new one needs its file in
/// assets/google_fonts, or it falls back to the system font.
const _interWeights = [400, 500, 600, 700, 800, 900];
const _barlowWeights = [400, 500, 600, 700, 800, 900];
const _barlowItalicWeights = [700, 800, 900];

FontWeight _weight(int w) => FontWeight.values[w ~/ 100 - 1];

void main() {
  // Unlike the other tests, this one loads the real fonts, from the assets only.
  setUpAll(() {
    AppFonts.useGoogleFonts = true;
    AppFonts.useBundledFonts();
  });

  Future<void> drawAndLoad(WidgetTester tester, List<TextStyle> styles) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: SingleChildScrollView(
          child: Column(children: [for (final s in styles) Text('42 Runs', style: s)]),
        ),
      ),
    );
    await tester.runAsync(GoogleFonts.pendingFonts);
  }

  test('nothing is ever downloaded', () {
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
  });

  // A missing file makes google_fonts throw inside the frame, which stalls the
  // test rather than failing it, hence the short timeout.
  testWidgets(
    'every weight the app draws loads from the bundled files',
    timeout: const Timeout(Duration(seconds: 30)),
    (tester) async {
      // google_fonts reports a failed load with debugPrint. Flutter checks that
      // debugPrint is restored before tear-down runs, hence try/finally.
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      try {
        await drawAndLoad(tester, [
          for (final w in _interWeights) GoogleFonts.inter(fontWeight: _weight(w)),
          for (final w in _barlowWeights) scoreStyle(20, weight: _weight(w)),
          for (final w in _barlowItalicWeights)
            AppFonts.display(TextStyle(fontWeight: _weight(w), fontStyle: FontStyle.italic)),
          // The themes themselves, light and dark.
          ...[AppTheme.light(), AppTheme.dark()].expand(
            (t) => [
              t.textTheme.bodyMedium!,
              t.textTheme.titleMedium!,
              t.textTheme.labelSmall!,
              t.textTheme.headlineSmall!,
              t.textTheme.titleLarge!,
              t.appBarTheme.titleTextStyle!,
            ],
          ),
        ]);
      } finally {
        debugPrint = original;
      }
      expect(logs.where((l) => l.contains('unable to load font')), isEmpty, reason: logs.join('\n'));
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
  for (final w in _interWeights) 'Inter-${_name(w)}.ttf',
  for (final w in _barlowWeights) 'BarlowCondensed-${_name(w)}.ttf',
  for (final w in _barlowItalicWeights) 'BarlowCondensed-${_name(w)}Italic.ttf',
];

String _name(int weight) =>
    const {400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold', 900: 'Black'}[weight]!;
