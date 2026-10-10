import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The two app tones (design-spec "Dual role & tones" D.1). A tone is a scope
/// property (app-level = active role, trip-bound = the trip's role), never a
/// permission.
enum AppTone { rider, driver }

/// Semantic colour tokens shared by both tones (design-spec D.1.1 / D.1.2), so a
/// component reads `context.tone.text` and never has to know which tone it is in.
@immutable
class ToneColors extends ThemeExtension<ToneColors> {
  const ToneColors({
    required this.tone,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textSecondary,
    required this.textDisabled,
    required this.primary,
    required this.onPrimary,
    required this.primaryInk,
    required this.primaryTint,
    required this.selectedFill,
    required this.onSelectedFill,
    required this.infoBg,
    required this.successFill,
    required this.onSuccessFill,
    required this.successInk,
    required this.danger,
    required this.dangerInk,
    required this.dangerTint,
    required this.warningInk,
    required this.warningTint,
    required this.accentInk,
    required this.snackbarBg,
    required this.snackbarText,
    required this.routeColor,
    required this.routeCasing,
    required this.routeWidth,
    required this.dialogBg,
    this.googleFonts = true,
    this.brightness = Brightness.light,
  });

  final AppTone tone;
  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textSecondary;
  final Color textDisabled;

  /// Primary button fill / switch-on / spinner (fill and large icons only).
  final Color primary;
  final Color onPrimary;

  /// Primary used as text, link, small icon, selected tab or focus ring.
  final Color primaryInk;
  final Color primaryTint;

  /// Selected chip / segmented cell fill and the text on it.
  final Color selectedFill;
  final Color onSelectedFill;
  final Color infoBg;
  final Color successFill;
  final Color onSuccessFill;
  final Color successInk;

  /// Solid red fill (SOS, danger button). Same in both tones.
  final Color danger;

  /// Red used as text/icon on the tone background.
  final Color dangerInk;
  final Color dangerTint;
  final Color warningInk;
  final Color warningTint;
  final Color accentInk;
  final Color snackbarBg;
  final Color snackbarText;

  /// Map route of a trip owned in this tone (with casing).
  final Color routeColor;
  final Color routeCasing;
  final double routeWidth;
  final Color dialogBg;

  /// Whether the theme built from these tokens loads Google Fonts (false in tests), so a nested
  /// trip-tone theme can be built with the same font setting.
  final bool googleFonts;

  /// US-46 (round 7): which token set within [tone] this is — `light` (D.1.1/D.1.2, the
  /// original look) or `dark` (G.5.1.1/G.5.1.2, night driving/riding). Independent of [tone]
  /// itself (design-roles §G.5.4: brightness is a second axis, not a third tone).
  final Brightness brightness;

  bool get isDriver => tone == AppTone.driver;
  bool get isDark => brightness == Brightness.dark;

  /// Soft-depth shadow for resting cards/controls (2 layers: wide ambient + tight contact).
  /// Dark tones get a barely-there shadow (a dark bg can't show a dark shadow) so depth there
  /// reads mostly from [surfaceRaised] instead.
  List<BoxShadow> get cardShadow => isDark
      ? [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 10)),
        ]
      : [
          BoxShadow(color: text.withValues(alpha: 0.12), blurRadius: 28, offset: const Offset(0, 12)),
          BoxShadow(color: text.withValues(alpha: 0.07), blurRadius: 6, offset: const Offset(0, 2)),
        ];

  /// Same shadow, compressed — used for the pressed/active state of tappable cards.
  List<BoxShadow> get cardShadowPressed => isDark
      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))]
      : [BoxShadow(color: text.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))];

  static const rider = ToneColors(
    tone: AppTone.rider,
    // Round 9 (US-7/G9.7.2, PM ruling item 8): F7FAFC -> F8F9FC, approved token value change
    // (driver.bg is intentionally dark-navy always — not a "light background" equivalent, left as-is;
    // riderDark/driverDark already have their own dark-mode backgrounds, per the ruling's rationale).
    bg: Color(0xFFF8F9FC),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    border: Color(0xFFD8E2EC),
    borderStrong: Color(0xFF7A8CA5),
    text: Color(0xFF0B2545),
    textSecondary: Color(0xFF4A5A70),
    textDisabled: Color(0xFF4A5A70),
    primary: Color(0xFF1E6FD9),
    onPrimary: Color(0xFFFFFFFF),
    primaryInk: Color(0xFF1E6FD9),
    primaryTint: Color(0xFFE7F0FC),
    selectedFill: Color(0xFFE0F7F1),
    onSelectedFill: Color(0xFF0B2545),
    infoBg: Color(0xFFE0F7F1),
    successFill: Color(0xFF22C08A),
    onSuccessFill: Color(0xFF0B2545),
    successInk: Color(0xFF0E7A57),
    danger: Color(0xFFC53030),
    dangerInk: Color(0xFFC53030),
    dangerTint: Color(0xFFFDECEC),
    warningInk: Color(0xFFB45309),
    warningTint: Color(0xFFFFF4E0),
    accentInk: Color(0xFF12708A),
    snackbarBg: Color(0xFF0B2545),
    snackbarText: Color(0xFFFFFFFF),
    routeColor: Color(0xFF1E6FD9),
    routeCasing: Color(0xFFFFFFFF),
    routeWidth: 5,
    dialogBg: Color(0xFFFFFFFF),
  );

  static const driver = ToneColors(
    tone: AppTone.driver,
    bg: Color(0xFF0B1B33),
    surface: Color(0xFF12274A),
    surfaceRaised: Color(0xFF1A3560),
    border: Color(0xFF2C4A78),
    borderStrong: Color(0xFF6F8FBF),
    text: Color(0xFFF4F7FB),
    textSecondary: Color(0xFFB8C6DC),
    textDisabled: Color(0xFF8FA3C4),
    primary: Color(0xFFF5A623),
    onPrimary: Color(0xFF0B1B33),
    primaryInk: Color(0xFFFFC24D),
    primaryTint: Color(0xFF1A3560),
    selectedFill: Color(0xFFF5A623),
    onSelectedFill: Color(0xFF0B1B33),
    infoBg: Color(0xFF1A3560),
    successFill: Color(0xFF5FD9A8),
    onSuccessFill: Color(0xFF0B1B33),
    successInk: Color(0xFF5FD9A8),
    danger: Color(0xFFC53030),
    dangerInk: Color(0xFFFF8A8A),
    dangerTint: Color(0xFF3B1D2A),
    warningInk: Color(0xFFFFC24D),
    warningTint: Color(0xFF1A3560),
    accentInk: Color(0xFFFFC24D),
    snackbarBg: Color(0xFFF4F7FB),
    snackbarText: Color(0xFF0B1B33),
    routeColor: Color(0xFFF5A623),
    routeCasing: Color(0xFF0B1B33),
    routeWidth: 6,
    dialogBg: Color(0xFF1A3560),
  );

  /// G.5.1.1 rider-dark (design-spec-round7).
  static const riderDark = ToneColors(
    tone: AppTone.rider,
    brightness: Brightness.dark,
    bg: Color(0xFF0A1220),
    surface: Color(0xFF131C2E),
    surfaceRaised: Color(0xFF1B2740),
    border: Color(0xFF2A3752),
    borderStrong: Color(0xFF6F80A3),
    text: Color(0xFFEDF1F7),
    textSecondary: Color(0xFFAEB9CF),
    textDisabled: Color(0xFFAEB9CF),
    primary: Color(0xFF6FA8F5),
    onPrimary: Color(0xFF06121F),
    primaryInk: Color(0xFF6FA8F5),
    primaryTint: Color(0xFF1E2E4D),
    selectedFill: Color(0xFF1E2E4D),
    onSelectedFill: Color(0xFFEDF1F7),
    infoBg: Color(0xFF123B33),
    successFill: Color(0xFF3FCF9E),
    onSuccessFill: Color(0xFF06121F),
    successInk: Color(0xFF3FCF9E),
    danger: Color(0xFFFF6B6B),
    dangerInk: Color(0xFFFF6B6B),
    dangerTint: Color(0xFF3A1414),
    warningInk: Color(0xFFFFC24D),
    warningTint: Color(0xFF1E2E4D),
    accentInk: Color(0xFF7FE6C8),
    snackbarBg: Color(0xFFEDF1F7),
    snackbarText: Color(0xFF0A1220),
    routeColor: Color(0xFF6FA8F5),
    routeCasing: Color(0xFFEDF1F7),
    routeWidth: 5,
    dialogBg: Color(0xFF131C2E),
  );

  /// G.5.1.2 driver-dark (design-spec-round7) — dimmer amber than driver-light to cut
  /// windscreen glare at night (Q-G5).
  static const driverDark = ToneColors(
    tone: AppTone.driver,
    brightness: Brightness.dark,
    bg: Color(0xFF05101F),
    surface: Color(0xFF0C1D33),
    surfaceRaised: Color(0xFF142B4A),
    border: Color(0xFF24405F),
    borderStrong: Color(0xFF6A8AB8),
    text: Color(0xFFEAF0FA),
    textSecondary: Color(0xFFA9BBD6),
    textDisabled: Color(0xFFA9BBD6),
    primary: Color(0xFFD98A1E),
    onPrimary: Color(0xFF05101F),
    primaryInk: Color(0xFFF0B75B),
    primaryTint: Color(0xFF142B4A),
    selectedFill: Color(0xFFD98A1E),
    onSelectedFill: Color(0xFF05101F),
    infoBg: Color(0xFF142B4A),
    successFill: Color(0xFF4FCB9E),
    onSuccessFill: Color(0xFF05101F),
    successInk: Color(0xFF4FCB9E),
    danger: Color(0xFFFF6B6B),
    dangerInk: Color(0xFFFF6B6B),
    dangerTint: Color(0xFF331616),
    warningInk: Color(0xFFF0B75B),
    warningTint: Color(0xFF142B4A),
    accentInk: Color(0xFFF0B75B),
    snackbarBg: Color(0xFFEAF0FA),
    snackbarText: Color(0xFF05101F),
    routeColor: Color(0xFFF0B75B),
    // US-46 AC: light casing keeps the amber route readable on a dark map (a near-black casing sinks into it).
    routeCasing: Color(0xFFEDF1F7),
    routeWidth: 6,
    dialogBg: Color(0xFF142B4A),
  );

  static ToneColors of(AppTone t) => t == AppTone.driver ? driver : rider;

  /// The 4-way lookup (design-roles §G.5.4): tone x brightness.
  static ToneColors resolve(AppTone t, Brightness b) {
    if (b == Brightness.dark) return t == AppTone.driver ? driverDark : riderDark;
    return t == AppTone.driver ? driver : rider;
  }

  ToneColors withFonts(bool gf) => gf == googleFonts ? this : _rebuild(googleFonts: gf);

  ToneColors _rebuild({required bool googleFonts}) => ToneColors(
        tone: tone, bg: bg, surface: surface, surfaceRaised: surfaceRaised, border: border, borderStrong: borderStrong,
        text: text, textSecondary: textSecondary, textDisabled: textDisabled, primary: primary, onPrimary: onPrimary,
        primaryInk: primaryInk, primaryTint: primaryTint, selectedFill: selectedFill, onSelectedFill: onSelectedFill,
        infoBg: infoBg, successFill: successFill, onSuccessFill: onSuccessFill, successInk: successInk, danger: danger,
        dangerInk: dangerInk, dangerTint: dangerTint, warningInk: warningInk, warningTint: warningTint, accentInk: accentInk,
        snackbarBg: snackbarBg, snackbarText: snackbarText, routeColor: routeColor, routeCasing: routeCasing,
        routeWidth: routeWidth, dialogBg: dialogBg, googleFonts: googleFonts, brightness: brightness,
      );

  @override
  ToneColors copyWith() => this;

  @override
  ToneColors lerp(ThemeExtension<ToneColors>? other, double t) {
    if (other is! ToneColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ToneColors(
      tone: t < 0.5 ? tone : other.tone,
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      text: l(text, other.text),
      textSecondary: l(textSecondary, other.textSecondary),
      textDisabled: l(textDisabled, other.textDisabled),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primaryInk: l(primaryInk, other.primaryInk),
      primaryTint: l(primaryTint, other.primaryTint),
      selectedFill: l(selectedFill, other.selectedFill),
      onSelectedFill: l(onSelectedFill, other.onSelectedFill),
      infoBg: l(infoBg, other.infoBg),
      successFill: l(successFill, other.successFill),
      onSuccessFill: l(onSuccessFill, other.onSuccessFill),
      successInk: l(successInk, other.successInk),
      danger: l(danger, other.danger),
      dangerInk: l(dangerInk, other.dangerInk),
      dangerTint: l(dangerTint, other.dangerTint),
      warningInk: l(warningInk, other.warningInk),
      warningTint: l(warningTint, other.warningTint),
      accentInk: l(accentInk, other.accentInk),
      snackbarBg: l(snackbarBg, other.snackbarBg),
      snackbarText: l(snackbarText, other.snackbarText),
      routeColor: l(routeColor, other.routeColor),
      routeCasing: l(routeCasing, other.routeCasing),
      routeWidth: routeWidth + (other.routeWidth - routeWidth) * t,
      dialogBg: l(dialogBg, other.dialogBg),
      googleFonts: googleFonts,
      brightness: t < 0.5 ? brightness : other.brightness,
    );
  }
}

extension ToneContext on BuildContext {
  /// Tone tokens of the nearest theme; plain `MaterialApp`s without the extension get the Rider tone.
  ToneColors get tone => Theme.of(this).extension<ToneColors>() ?? ToneColors.rider;
}

/// WCAG 2.x contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final la = lum(a), lb = lum(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
