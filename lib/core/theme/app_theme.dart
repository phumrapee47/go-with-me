import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';
import 'tone.dart';

/// Rider tone = the original look. [useGoogleFonts] is false in tests to avoid
/// network font fetching.
ThemeData buildAppTheme({bool useGoogleFonts = true}) => buildToneTheme(AppTone.rider, useGoogleFonts: useGoogleFonts);

final _cache = <(AppTone, bool, Brightness), ThemeData>{};

/// `riderTheme` / `driverTheme` (design-spec D.1). Cached: building GoogleFonts
/// styles is not free and trip-bound screens ask for the theme of their role.
/// [brightness] adds the US-46 (round 7) rider-dark/driver-dark token sets
/// (design-roles §G.5.4) without touching the existing light tokens/behaviour.
ThemeData themeForTone(AppTone tone, {bool useGoogleFonts = true, Brightness brightness = Brightness.light}) =>
    _cache.putIfAbsent(
      (tone, useGoogleFonts, brightness),
      () => buildToneTheme(tone, useGoogleFonts: useGoogleFonts, brightness: brightness),
    );

ThemeData buildToneTheme(AppTone tone, {bool useGoogleFonts = true, Brightness brightness = Brightness.light}) {
  final c = ToneColors.resolve(tone, brightness).withFonts(useGoogleFonts);
  // Driver tone has always been rendered with a dark ColorScheme (design-spec D.1.2);
  // round 7 adds an explicit dark rider variant too (rider-dark).
  final dark = tone == AppTone.driver || brightness == Brightness.dark;

  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: dark ? c.primaryInk : AppColors.teal,
    onSecondary: dark ? c.onPrimary : Colors.white,
    tertiary: c.successFill,
    onTertiary: c.onSuccessFill,
    error: c.danger,
    onError: Colors.white,
    errorContainer: c.dangerTint,
    onErrorContainer: c.dangerInk,
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.textSecondary,
    outline: c.borderStrong,
    outlineVariant: c.border,
    primaryContainer: c.primaryTint,
    onPrimaryContainer: c.text,
    secondaryContainer: c.selectedFill,
    onSecondaryContainer: c.onSelectedFill,
    surfaceContainerHighest: dark ? c.surfaceRaised : null,
    surfaceContainerHigh: dark ? c.surfaceRaised : null,
    surfaceContainer: dark ? c.surface : null,
    surfaceContainerLow: dark ? c.surface : null,
    surfaceContainerLowest: dark ? c.bg : null,
  );

  // Thai needs looser line height than Latin so tone marks are not clipped.
  TextStyle body(double size, FontWeight w) => useGoogleFonts
      ? GoogleFonts.notoSansThai(fontSize: size, fontWeight: w, height: 1.5, color: c.text)
      : TextStyle(fontSize: size, fontWeight: w, height: 1.5, color: c.text);
  TextStyle head(double size, FontWeight w) => useGoogleFonts
      ? GoogleFonts.prompt(fontSize: size, fontWeight: w, height: 1.4, color: c.text)
      : TextStyle(fontSize: size, fontWeight: w, height: 1.4, color: c.text);

  final textTheme = TextTheme(
    displayMedium: head(28, FontWeight.w600),
    titleLarge: head(22, FontWeight.w600),
    titleMedium: head(18, FontWeight.w500),
    bodyLarge: body(16, FontWeight.w400),
    bodyMedium: body(14, FontWeight.w400),
    labelLarge: body(14, FontWeight.w600),
    bodySmall: body(12, FontWeight.w400).copyWith(color: c.textSecondary),
  );

  OutlineInputBorder border(Color color, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: color, width: w),
      );
  final inputBorder = border(dark ? c.borderStrong : c.border);

  Color? fillWhenSelected(Set<WidgetState> s) => s.contains(WidgetState.selected) ? c.primary : null;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [c],
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    textTheme: textTheme,
    iconTheme: IconThemeData(color: c.text),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? c.surface : c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge,
      // Driver tone: 3 dp amber under the top bar (design-spec D.4, decorative). Rider-dark has
      // no amber accent (that colour belongs to the Driver tone only, in either brightness).
      shape: tone == AppTone.driver
          ? Border(bottom: BorderSide(color: brightness == Brightness.dark ? c.primary : const Color(0xFFF5A623), width: 3))
          : null,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      // Soft-depth: a real (small) shadow carries the elevation now, not a 1px border.
      elevation: dark ? 4 : 8,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.24),
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: AppShape.card(),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.dialogBg,
      surfaceTintColor: Colors.transparent,
      shape: AppShape.card(),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.dialogBg,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: c.dialogBg,
      shape: AppShape.sheet(),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: border(c.primaryInk, 2),
      errorBorder: border(c.dangerInk),
      focusedErrorBorder: border(c.dangerInk, 2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      errorMaxLines: 3,
      labelStyle: TextStyle(color: c.textSecondary),
      hintStyle: TextStyle(color: c.textSecondary),
      errorStyle: TextStyle(color: c.dangerInk),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.primaryTint,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => textTheme.bodySmall?.copyWith(color: s.contains(WidgetState.selected) && dark ? c.primaryInk : null),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.primaryInk : c.textSecondary),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.snackbarBg,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.snackbarText),
      actionTextColor: dark ? const Color(0xFF8A5A00) : null,
    ),
    dividerTheme: DividerThemeData(color: c.border, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: c.primary, foregroundColor: c.onPrimary, shape: AppShape.control()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.primaryInk,
        side: BorderSide(color: c.primaryInk, width: 1.5),
        shape: AppShape.control(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.primaryInk, shape: AppShape.control()),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.primary,
      foregroundColor: c.onPrimary,
      shape: AppShape.card(),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary, linearTrackColor: c.primaryTint),
    listTileTheme: ListTileThemeData(iconColor: c.text, textColor: c.text),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => fillWhenSelected(s) ?? (dark ? c.surface : null)),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onPrimary : (dark ? c.borderStrong : null)),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : (dark ? c.borderStrong : null)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(fillWhenSelected),
      checkColor: WidgetStatePropertyAll(c.onPrimary),
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(color: s.contains(WidgetState.selected) ? c.primary : c.borderStrong, width: 2),
      ),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : c.borderStrong)),
    chipTheme: ChipThemeData(
      backgroundColor: dark ? c.surfaceRaised : null,
      selectedColor: c.selectedFill,
      checkmarkColor: c.onSelectedFill,
      labelStyle: textTheme.bodyMedium,
      secondaryLabelStyle: textTheme.bodyMedium?.copyWith(color: c.onSelectedFill),
      side: BorderSide(color: dark ? c.borderStrong : c.border),
      shape: AppShape.control(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.selectedFill : (dark ? c.surface : null)),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onSelectedFill : c.text),
        side: WidgetStatePropertyAll(BorderSide(color: c.borderStrong)),
        shape: WidgetStatePropertyAll(AppShape.control()),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.primaryInk),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.snackbarBg, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: c.snackbarText),
    ),
  );
}
