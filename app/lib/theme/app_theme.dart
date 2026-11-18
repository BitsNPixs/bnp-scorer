import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show LicenseEntry, LicenseEntryWithLineBreaks, LicenseRegistry, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand palette: a floodlit night pitch with the BitsNPixs green as the
/// accent (the field is still called neon). Scoring
/// colours are fixed across light and dark themes so a "4" always looks like
/// a 4.
abstract final class AppColors {
  /// Floodlit night: hero cards in both themes, and the dark theme's base.
  static const night = Color(0xFF081008);
  static const nightRaised = Color(0xFF1F3F17);

  /// The brand green, a shade brighter than the logo's so it carries on night:
  /// the accent on night and the fill of primary actions.
  static const neon = Color(0xFF7DC43A);
  static const neonDeep = Color(0xFF5A9420);

  /// Green for text and icons on light surfaces, where neon is too faint.
  static const turf = Color(0xFF3F7A14);

  /// BitsNPixs' green, the "n" of the company logo. Only the BNP Scorer
  /// logo uses it (`tool/generate_app_icon_test.dart`); the app itself stays
  /// neon.
  static const brandGreen = Color(0xFF6FAE29);

  static const four = Color(0xFFFFB21E);
  static const six = Color(0xFF7C4DFF);
  static const wicket = Color(0xFFFF4D5E);

  /// Blue, so extras never read as the green of runs off the bat.
  static const extra = Color(0xFF1C72D8);
  static const dot = Color(0xFF9AA3B5);
  static const live = Color(0xFFFF3B5C);

  /// Chart series in fixed order: first innings, then second. Checked for
  /// contrast and colour-blind separation against each theme's card surface.
  static List<Color> chartSeries(Brightness brightness) => brightness == Brightness.light
      ? const [Color(0xFF3446FF), Color(0xFFE85D04)]
      : const [Color(0xFF6F80F5), Color(0xFFDE6A20)];

  /// The floodlit card behind scores, champions and leaders.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [nightRaised, Color(0xFF0D1A0B)],
  );

  /// Fill of the big call-to-action buttons.
  static const neonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA6E55C), neonDeep],
  );

  /// A soft coloured glow under a raised element.
  static List<BoxShadow> glow(Color color, {double strength = 0.4, double blur = 24}) => [
    BoxShadow(
      color: color.withValues(alpha: strength),
      blurRadius: blur,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Widget tests turn this off so fonts are not fetched over the network.
abstract final class AppFonts {
  static bool useGoogleFonts = true;

  /// Where the font files and their licences ship. File names follow
  /// google_fonts' `<Family>-<Variant>.ttf`, e.g. `Inter-SemiBold.ttf`.
  static const assetFolder = 'assets/google_fonts';

  /// The fonts ship with the app, so the first launch works offline and
  /// nothing is downloaded. A weight missing from [assetFolder] is reported
  /// by google_fonts and drawn in the system font.
  static void useBundledFonts() {
    GoogleFonts.config.allowRuntimeFetching = false;
    LicenseRegistry.addLicense(_licenses);
  }

  /// Every weight the app draws, and so every file in [assetFolder]. A new
  /// weight or italic needs its file added there too.
  static const interWeights = [
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
    FontWeight.w800,
    FontWeight.w900,
  ];
  static const displayWeights = interWeights;
  static const displayItalicWeights = [FontWeight.w700, FontWeight.w800, FontWeight.w900];

  /// The longest startup waits for [preload].
  static const preloadLimit = Duration(seconds: 3);

  /// Loads every bundled font before the first frame, so no text is laid out
  /// in the narrower fallback font and then swapped. That swap is the likely
  /// reason chips on Home lost their last letter. Startup waits at most
  /// [preloadLimit]; a failed or slow load is logged and the app starts
  /// anyway, with the system font for anything not yet loaded.
  static Future<void> preload() async {
    try {
      await GoogleFonts.pendingFonts([
        for (final w in interWeights) GoogleFonts.inter(fontWeight: w),
        for (final w in displayWeights) GoogleFonts.barlowCondensed(fontWeight: w),
        for (final w in displayItalicWeights) GoogleFonts.barlowCondensed(fontWeight: w, fontStyle: FontStyle.italic),
      ]).timeout(preloadLimit);
    } on Object catch (e) {
      debugPrint('Could not preload the fonts: $e');
    }
  }

  static Stream<LicenseEntry> _licenses() async* {
    for (final (family, file) in const [('Inter', 'Inter'), ('Barlow Condensed', 'BarlowCondensed')]) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString('$assetFolder/$file-OFL.txt'));
    }
  }

  /// Barlow Condensed: tall, narrow scoreboard type for scores and headings.
  static TextStyle display(TextStyle style) => useGoogleFonts ? GoogleFonts.barlowCondensed(textStyle: style) : style;

  /// Inter, the body face, for text drawn outside the theme.
  static TextStyle body(TextStyle style) => useGoogleFonts ? GoogleFonts.inter(textStyle: style) : style;
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.neonDeep, brightness: brightness).copyWith(
      primary: isLight ? AppColors.turf : AppColors.neon,
      onPrimary: isLight ? Colors.white : AppColors.night,
      primaryContainer: isLight ? const Color(0xFFDDF2C4) : const Color(0xFF203D14),
      onPrimaryContainer: isLight ? const Color(0xFF1E3A08) : AppColors.neon,
      secondaryContainer: isLight ? const Color(0xFFE3EDDA) : const Color(0xFF1E2A1A),
      onSecondaryContainer: isLight ? const Color(0xFF121A0A) : const Color(0xFFE6F5D8),
      surface: isLight ? const Color(0xFFF0F3EC) : const Color(0xFF070A06),
      onSurface: isLight ? const Color(0xFF121A0C) : const Color(0xFFEAF1E6),
      onSurfaceVariant: isLight ? const Color(0xFF56614C) : const Color(0xFF95A38C),
      surfaceContainerLowest: isLight ? Colors.white : const Color(0xFF10160E),
      surfaceContainerLow: isLight ? const Color(0xFFF8FBF6) : const Color(0xFF141B11),
      surfaceContainer: isLight ? const Color(0xFFE5EBDF) : const Color(0xFF192217),
      surfaceContainerHigh: isLight ? const Color(0xFFDAE2D3) : const Color(0xFF202A1D),
      outline: isLight ? const Color(0xFF8E9A85) : const Color(0xFF3E4A37),
      outlineVariant: isLight ? const Color(0xFFD4DDCC) : const Color(0xFF253021),
      error: AppColors.wicket,
    );

    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final fonts = AppFonts.useGoogleFonts;
    final body = fonts ? GoogleFonts.interTextTheme(base.textTheme) : base.textTheme;
    final display = fonts ? GoogleFonts.barlowCondensedTextTheme(base.textTheme) : base.textTheme;
    TextStyle? bold(TextStyle? style) => style?.copyWith(fontWeight: FontWeight.w800);
    final textTheme = body
        .copyWith(
          displayLarge: bold(display.displayLarge),
          displayMedium: bold(display.displayMedium),
          displaySmall: bold(display.displaySmall),
          headlineLarge: bold(display.headlineLarge),
          headlineMedium: bold(display.headlineMedium),
          headlineSmall: bold(display.headlineSmall),
          titleLarge: display.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    final buttonText = textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.2);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _RiseTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        systemOverlayStyle: isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        titleTextStyle: AppFonts.display(
          TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: 0.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Neon with night text in both themes: the one colour that means "go".
          backgroundColor: AppColors.neon,
          foregroundColor: AppColors.night,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.10),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          minimumSize: const Size.fromHeight(56),
          shape: rounded,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: rounded,
          side: BorderSide(color: scheme.outline),
          textStyle: buttonText?.copyWith(fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.neon,
        foregroundColor: AppColors.night,
        shape: const StadiumBorder(),
        extendedTextStyle: buttonText?.copyWith(fontSize: 15),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerLowest,
        selectedColor: scheme.primary,
        showCheckmark: false,
        labelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onPrimary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(99)),
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(99),
        labelPadding: const EdgeInsets.symmetric(horizontal: 18),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// New screens rise a little and fade in, quick enough for a scorer mid-over.
class _RiseTransitionsBuilder extends PageTransitionsBuilder {
  const _RiseTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: enter,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(enter),
        child: child,
      ),
    );
  }
}

/// Barlow Condensed with tabular figures, for scores that must not jitter.
TextStyle scoreStyle(double size, {Color? color, FontWeight weight = FontWeight.w700}) => AppFonts.display(
  TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1,
    fontFeatures: const [FontFeature.tabularFigures()],
  ),
);
