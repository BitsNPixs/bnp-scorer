import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:bnp_scorer/widgets/logo_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders one layer of the logo at [px] pixels and returns its RGBA bytes.
Future<ByteData> _render(LogoLayer layer, int px) async {
  final recorder = ui.PictureRecorder();
  paintLogo(Canvas(recorder), px / logoCanvas, layer);
  final image = await recorder.endRecording().toImage(px, px);
  return (await image.toByteData())!;
}

Color _at(ByteData rgba, int px, int x, int y) {
  final i = (y * px + x) * 4;
  return Color.fromARGB(rgba.getUint8(i + 3), rgba.getUint8(i), rgba.getUint8(i + 1), rgba.getUint8(i + 2));
}

void main() {
  const px = 108; // one pixel per grid unit

  test('the ball is green, the b a cut-out of night and the p chalk', () async {
    final rgba = await _render(LogoLayer.foreground, px);
    final ballBody = _at(rgba, px, 46, 70); // low in the ball, clear of both letters
    expect(ballBody.a, 1);
    expect(ballBody.g, greaterThan(ballBody.r + 0.12), reason: 'the ball is green');
    expect(_at(rgba, px, 32, 42), AppColors.night, reason: 'the stem of the b is night');
    final pStem = _at(rgba, px, 56, 84); // the p below the ball
    expect(pStem.a, 1);
    expect(pStem.r, greaterThan(0.9), reason: 'the stem of the p is chalk, outside the ball');
    expect(_at(rgba, px, 10, 10).a, 0, reason: 'nothing outside the ball but the p');
  });

  test('the monochrome layer is a white ball with the letters punched out', () async {
    final rgba = await _render(LogoLayer.monochrome, px);
    expect(_at(rgba, px, 46, 70), Colors.white);
    expect(_at(rgba, px, 32, 42).a, 0, reason: 'the b is a hole');
    expect(_at(rgba, px, 79, 53).a, 0, reason: 'the ring of the p is a hole');
    expect(_at(rgba, px, 56, 84), Colors.white, reason: 'the stem of the p is white outside the ball');
  });

  test('the background layer fills the canvas and the mark stays in the safe zone', () async {
    final background = await _render(LogoLayer.background, px);
    expect(_at(background, px, 0, 0).a, 1);
    final mark = await _render(LogoLayer.foreground, px);
    for (var y = 0; y < px; y++) {
      for (var x = 0; x < px; x++) {
        if (_at(mark, px, x, y).a != 0) {
          expect(logoSafeZone.contains(Offset(x + 0.5, y + 0.5)), isTrue, reason: 'ink at $x,$y');
        }
      }
    }
  });

  testWidgets('LogoMark is square at the size asked for', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: LogoMark(size: 36))));
    expect(tester.getSize(find.byType(LogoMark)), const Size(36, 36));
  });
}
