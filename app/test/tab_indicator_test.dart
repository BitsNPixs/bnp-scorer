import 'package:bnp_scorer/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => AppFonts.useGoogleFonts = false);

  testWidgets('the pill sits inset in its tab, not filling its height', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: DecoratedBox(
          decoration: PillTabIndicator(color: Color(0xFFFF0000)),
          child: SizedBox(width: 100, height: 46),
        ),
      ),
    ));
    // Painted in the box's own coordinates: 46 tall, 8 off the top and bottom.
    const pill = Rect.fromLTRB(0, 8, 100, 38);
    expect(
      find.byType(DecoratedBox),
      paints..rrect(rrect: RRect.fromRectAndRadius(pill, const Radius.circular(15)), color: const Color(0xFFFF0000)),
    );
  });

  test('both themes use it for tab bars', () {
    expect(AppTheme.light().tabBarTheme.indicator, isA<PillTabIndicator>());
    expect(AppTheme.dark().tabBarTheme.indicator, isA<PillTabIndicator>());
  });
}
