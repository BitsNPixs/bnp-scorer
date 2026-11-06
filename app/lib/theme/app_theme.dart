import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand palette. Scoring colours are fixed across light and dark themes so
/// a "4" always looks like a 4.
abstract final class AppColors {
  /// Night-match navy used for the score hero and primary actions.
  static const ink = Color(0xFF0E1430);
  static const inkRaised = Color(0xFF26338A);

  /// Floodlight lime: the accent on ink.
  static const lime = Color(0xFFD4FF3F);

  static const four = Color(0xFFFFB21E);
  static const six = Color(0xFF7C4DFF);
  static const wicket = Color(0xFFFF4D5E);
  static const extra = Color(0xFF12B5A6);
  static const dot = Color(0xFF9AA3B5);
  static const live = Color(0xFFFF3B5C);

  /// Chart series in fixed order: first innings, then second. Checked for
  /// contrast and colour-blind separation against each theme's card surface.
  static List<Color> chartSeries(Brightness brightness) => brightness == Brightness.light
      ? const [Color(0xFF3446FF), Color(0xFFE85D04)]
      : const [Color(0xFF6F80F5), Color(0xFFDE6A20)];

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ink, inkRaised],
  );
}

/// Widget tests turn this off so fonts are not fetched over the network.
abstract final class AppFonts {
  static bool useGoogleFonts = true;
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3446FF),
      brightness: brightness,
    ).copyWith(
      primary: isLight ? AppColors.ink : AppColors.lime,
      onPrimary: isLight ? Colors.white : AppColors.ink,
      surface: isLight ? const Color(0xFFF4F5FA) : const Color(0xFF080B1C),
      surfaceContainerLowest: isLight ? Colors.white : const Color(0xFF10152E),
      surfaceContainerLow: isLight ? Colors.white : const Color(0xFF141A36),
      surfaceContainer: isLight ? const Color(0xFFECEEF6) : const Color(0xFF1A2142),
      surfaceContainerHigh: isLight ? const Color(0xFFE3E6F2) : const Color(0xFF212950),
      error: AppColors.wicket,
    );

    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final fonts = AppFonts.useGoogleFonts;
    final body = fonts ? GoogleFonts.interTextTheme(base.textTheme) : base.textTheme;
    final display = fonts ? GoogleFonts.spaceGroteskTextTheme(base.textTheme) : base.textTheme;
    final textTheme = body
        .copyWith(
          displayLarge: display.displayLarge,
          displayMedium: display.displayMedium,
          displaySmall: display.displaySmall,
          headlineLarge: display.headlineLarge,
          headlineMedium: display.headlineMedium,
          headlineSmall: display.headlineSmall,
          titleLarge: display.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

/// Space Grotesk with tabular figures, for scores that must not jitter.
TextStyle scoreStyle(double size, {Color? color, FontWeight weight = FontWeight.w700}) {
  final style = TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  return AppFonts.useGoogleFonts ? GoogleFonts.spaceGrotesk(textStyle: style) : style;
}
