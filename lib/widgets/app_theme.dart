import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// The app's colours, in one place: manuscript paper and ink, with one
/// burnt-orange accent for whatever is moving or active (the playhead, the
/// measure being played). The judgement colours live here too, so dark mode
/// can lighten them -- the light-mode shades are too dark to read on a dark
/// page.
///
/// Read with [AppPalette.of]; screens shown without the app's theme (as in
/// most tests) get [light].
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  /// The page behind everything.
  final Color paper;

  /// Cards, dialogs and menus: a shade off the page.
  final Color surface;

  /// Text, staff lines and notes.
  final Color ink;

  /// Secondary text: hints, labels, captions.
  final Color mutedInk;

  /// Thin lines: card edges, dividers, chart grids.
  final Color rule;

  /// The playhead and the measure being played.
  final Color accent;

  final Color perfect;
  final Color great;
  final Color good;
  final Color miss;
  final Color fail;

  const AppPalette({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.mutedInk,
    required this.rule,
    required this.accent,
    required this.perfect,
    required this.great,
    required this.good,
    required this.miss,
    required this.fail,
  });

  static const light = AppPalette(
    paper: Color(0xFFF4EFE4),
    surface: Color(0xFFFBF8F1),
    ink: Color(0xFF1F1B16),
    mutedInk: Color(0xFF6B6358),
    rule: Color(0xFFD9D0BF),
    accent: Color(0xFFC8551B),
    // Yellow, darkened enough to read on a light background (Material's
    // stock yellows are either too pale for that or lean orange).
    perfect: Color(0xFFD4A900),
    great: Color(0xFF388E3C), // Material green 700
    good: Color(0xFF1976D2), // Material blue 700
    miss: Color(0xFFD32F2F), // Material red 700
    // Crimson, darkened and pulled toward purple so it reads apart from
    // Miss's red even at a glance.
    fail: Color(0xFF8E0E3A),
  );

  static const dark = AppPalette(
    paper: Color(0xFF17140F),
    surface: Color(0xFF221E18),
    ink: Color(0xFFEDE6D8),
    mutedInk: Color(0xFFA39A8B),
    rule: Color(0xFF3A342B),
    accent: Color(0xFFF08A4B),
    perfect: Color(0xFFF2CC3D),
    great: Color(0xFF6CC17A),
    good: Color(0xFF6FA8F0),
    miss: Color(0xFFF06B5F),
    // Raspberry: lighter than the light-mode crimson, still bluer than Miss.
    fail: Color(0xFFE0609A),
  );

  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppPalette>() ?? (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppPalette copyWith({
    Color? paper,
    Color? surface,
    Color? ink,
    Color? mutedInk,
    Color? rule,
    Color? accent,
    Color? perfect,
    Color? great,
    Color? good,
    Color? miss,
    Color? fail,
  }) {
    return AppPalette(
      paper: paper ?? this.paper,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      mutedInk: mutedInk ?? this.mutedInk,
      rule: rule ?? this.rule,
      accent: accent ?? this.accent,
      perfect: perfect ?? this.perfect,
      great: great ?? this.great,
      good: good ?? this.good,
      miss: miss ?? this.miss,
      fail: fail ?? this.fail,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      paper: mix(paper, other.paper),
      surface: mix(surface, other.surface),
      ink: mix(ink, other.ink),
      mutedInk: mix(mutedInk, other.mutedInk),
      rule: mix(rule, other.rule),
      accent: mix(accent, other.accent),
      perfect: mix(perfect, other.perfect),
      great: mix(great, other.great),
      good: mix(good, other.good),
      miss: mix(miss, other.miss),
      fail: mix(fail, other.fail),
    );
  }
}

/// The font for headings and numbers; body text stays the platform's own.
const String displayFontFamily = 'Barlow Semi Condensed';

/// The app's theme: flat paper surfaces edged with thin rules instead of
/// raised cards, ink-black main buttons, square-ish corners, and a
/// condensed face with even-width digits for headings and numbers (so a
/// BPM or a millisecond count doesn't shift about as it changes).
ThemeData buildAppTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: palette.ink,
    onPrimary: palette.paper,
    primaryContainer: palette.rule,
    onPrimaryContainer: palette.ink,
    secondary: palette.accent,
    onSecondary: palette.paper,
    error: palette.miss,
    onError: palette.paper,
    surface: palette.paper,
    onSurface: palette.ink,
    onSurfaceVariant: palette.mutedInk,
    surfaceContainerLowest: palette.surface,
    surfaceContainerLow: palette.surface,
    surfaceContainer: palette.surface,
    surfaceContainerHigh: palette.surface,
    surfaceContainerHighest: palette.surface,
    outline: palette.mutedInk,
    outlineVariant: palette.rule,
    inverseSurface: palette.ink,
    onInverseSurface: palette.paper,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  const tabular = [FontFeature.tabularFigures()];
  TextStyle? display(TextStyle? style, FontWeight weight) =>
      style?.copyWith(fontFamily: displayFontFamily, fontWeight: weight, fontFeatures: tabular);
  final text = base.textTheme;
  final textTheme = text.copyWith(
    displayLarge: display(text.displayLarge, FontWeight.w600),
    displayMedium: display(text.displayMedium, FontWeight.w600),
    displaySmall: display(text.displaySmall, FontWeight.w600),
    headlineLarge: display(text.headlineLarge, FontWeight.w600),
    headlineMedium: display(text.headlineMedium, FontWeight.w600),
    headlineSmall: display(text.headlineSmall, FontWeight.w600),
    titleLarge: display(text.titleLarge, FontWeight.w600),
    titleMedium: display(text.titleMedium?.copyWith(fontSize: 18), FontWeight.w500),
  );

  const corner = BorderRadius.all(Radius.circular(4));
  const shape = RoundedRectangleBorder(borderRadius: corner);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);

  return base.copyWith(
    scaffoldBackgroundColor: palette.paper,
    textTheme: textTheme,
    extensions: [palette],
    dividerTheme: DividerThemeData(color: palette.rule, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.paper,
      foregroundColor: palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: palette.ink, fontSize: 24),
      shape: Border(bottom: BorderSide(color: palette.rule)),
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: corner,
        side: BorderSide(color: palette.rule),
      ),
    ),
    // The main action on a screen: solid ink.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.ink,
        foregroundColor: palette.paper,
        disabledBackgroundColor: palette.rule,
        disabledForegroundColor: palette.mutedInk,
        elevation: 0,
        shape: shape,
        padding: buttonPadding,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.ink,
        foregroundColor: palette.paper,
        shape: shape,
        padding: buttonPadding,
      ),
    ),
    // Everything else: drawn in ink on the page.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        side: BorderSide(color: palette.ink),
        shape: shape,
        padding: buttonPadding,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.ink, shape: shape),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
      titleTextStyle: textTheme.titleLarge?.copyWith(color: palette.ink),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: corner,
        side: BorderSide(color: palette.rule),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.ink,
      contentTextStyle: TextStyle(color: palette.paper),
      actionTextColor: palette.accent,
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.ink,
      foregroundColor: palette.paper,
      elevation: 0,
      shape: shape,
    ),
    // Like the editor's type buttons: what's chosen is filled in ink.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: palette.ink,
        selectedForegroundColor: palette.paper,
        foregroundColor: palette.ink,
        side: BorderSide(color: palette.ink),
        shape: shape,
      ),
    ),
    switchTheme: SwitchThemeData(trackOutlineColor: WidgetStatePropertyAll(palette.mutedInk)),
    inputDecorationTheme: InputDecorationTheme(
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.mutedInk)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.accent, width: 2)),
      floatingLabelStyle: TextStyle(color: palette.accent),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.accent,
      selectionColor: palette.accent.withValues(alpha: 0.3),
      selectionHandleColor: palette.accent,
    ),
    // Screens slide in from the right and back out to the right on every
    // platform, the way a swipe back moves them (see `SwipeBack`).
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values) platform: const CupertinoPageTransitionsBuilder(),
      },
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
  );
}
