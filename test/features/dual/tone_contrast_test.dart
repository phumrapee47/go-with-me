import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/theme/app_theme.dart';
import 'package:gowithme/core/theme/tone.dart';

/// Automated WCAG 2.x check of both token sets (design-spec D.1.3): text >= 4.5:1, UI parts >= 3:1.
void main() {
  const rider = ToneColors.rider;
  const driver = ToneColors.driver;
  const white = Color(0xFFFFFFFF);
  const navy = Color(0xFF0B1B33);
  const amber = Color(0xFFF5A623);

  void pair(String name, Color fg, Color bg, [double min = 4.5]) {
    test('$name >= $min:1', () {
      final r = contrastRatio(fg, bg);
      expect(r, greaterThanOrEqualTo(min), reason: '$name is ${r.toStringAsFixed(2)}:1');
    });
  }

  test('the ratio function matches known values', () {
    expect(contrastRatio(const Color(0xFF000000), white), closeTo(21, 0.01));
    expect(contrastRatio(const Color(0xFF777777), white), closeTo(4.48, 0.02));
    expect(contrastRatio(amber, white), closeTo(2.0, 0.1), reason: 'why amber is never text on white');
  });

  group('Rider tone', () {
    pair('main text on bg', rider.text, rider.bg);
    pair('main text on surface', rider.text, rider.surface);
    pair('secondary text on surface', rider.textSecondary, rider.surface);
    pair('secondary text on bg', rider.textSecondary, rider.bg);
    pair('primary button label', rider.onPrimary, rider.primary);
    pair('link/primary ink on surface', rider.primaryInk, rider.surface);
    pair('link/primary ink on bg', rider.primaryInk, rider.bg);
    pair('mode badge text on mint', rider.text, rider.infoBg);
    pair('success button label', rider.onSuccessFill, rider.successFill);
    pair('SOS/danger button label', white, rider.danger);
    pair('error text on danger tint', rider.dangerInk, rider.dangerTint);
    pair('success ink on surface', rider.successInk, rider.surface);
    pair('snackbar text', rider.snackbarText, rider.snackbarBg);
    pair('selected chip text', rider.onSelectedFill, rider.selectedFill);
    pair('accent icon on mint', rider.accentInk, rider.infoBg, 3);
    pair('input border on surface', rider.borderStrong, rider.surface, 3);
    pair('input border on bg', rider.borderStrong, rider.bg, 3);
    pair('focus ring on surface', rider.primaryInk, rider.surface, 3);
  });

  group('Driver tone (deep navy + amber)', () {
    pair('main text on bg', driver.text, driver.bg);
    pair('main text on surface', driver.text, driver.surface);
    pair('main text on raised', driver.text, driver.surfaceRaised);
    pair('secondary text on bg', driver.textSecondary, driver.bg);
    pair('secondary text on surface', driver.textSecondary, driver.surface);
    pair('secondary text on raised', driver.textSecondary, driver.surfaceRaised);
    pair('disabled text on surface', driver.textDisabled, driver.surface);
    pair('disabled text on raised', driver.textDisabled, driver.surfaceRaised);
    pair('text ON amber (button, badge, chip)', driver.onPrimary, driver.primary);
    pair('mode badge text on amber', navy, amber);
    pair('amber-ink links on bg', driver.primaryInk, driver.bg);
    pair('amber-ink links on surface', driver.primaryInk, driver.surface);
    pair('amber-ink links on raised', driver.primaryInk, driver.surfaceRaised);
    pair('error text on bg', driver.dangerInk, driver.bg);
    pair('error text on surface', driver.dangerInk, driver.surface);
    pair('error text on danger tint', driver.dangerInk, driver.dangerTint);
    pair('success button label on success fill', driver.onSuccessFill, driver.successFill);
    pair('SOS/danger label white on red', white, driver.danger);
    pair('snackbar text', driver.snackbarText, driver.snackbarBg);
    pair('warning ink on raised', driver.warningInk, driver.warningTint);
    pair('selected chip text on amber', driver.onSelectedFill, driver.selectedFill);
    // UI components >= 3:1
    pair('amber on bg', driver.primary, driver.bg, 3);
    pair('amber on surface', driver.primary, driver.surface, 3);
    pair('input border on bg', driver.borderStrong, driver.bg, 3);
    pair('input border on surface', driver.borderStrong, driver.surface, 3);
    pair('focus ring on bg', driver.primaryInk, driver.bg, 3);
    pair('white ring on the surface behind the red SOS', white, driver.surface, 3);
    pair('white ring on bg behind the red SOS', white, driver.bg, 3);
    pair('navy route casing on the light map', driver.routeCasing, const Color(0xFFE9EEF3), 3);
    test('SOS red is identical in both tones (never amber, never hidden)', () {
      expect(driver.danger, rider.danger);
    });
  });

  group('themes are built from the tokens', () {
    test('rider = light with the original look, driver = dark navy', () {
      final r = themeForTone(AppTone.rider, useGoogleFonts: false);
      final d = themeForTone(AppTone.driver, useGoogleFonts: false);
      expect(r.brightness, Brightness.light);
      expect(d.brightness, Brightness.dark);
      expect(r.scaffoldBackgroundColor, const Color(0xFFF8F9FC));
      expect(d.scaffoldBackgroundColor, navy);
      expect(r.colorScheme.primary, const Color(0xFF1E6FD9));
      expect(d.colorScheme.primary, amber);
      expect(d.extension<ToneColors>()!.isDriver, isTrue);
      expect(identical(themeForTone(AppTone.driver, useGoogleFonts: false), d), isTrue, reason: 'cached');
    });

    test('colour-scheme pairs used by Material widgets stay readable', () {
      for (final t in [AppTone.rider, AppTone.driver]) {
        final cs = themeForTone(t, useGoogleFonts: false).colorScheme;
        expect(contrastRatio(cs.onSurface, cs.surface), greaterThanOrEqualTo(4.5), reason: '$t onSurface');
        expect(contrastRatio(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5), reason: '$t onPrimary');
        expect(contrastRatio(cs.onSurfaceVariant, cs.surface), greaterThanOrEqualTo(4.5), reason: '$t variant');
        expect(contrastRatio(cs.onSecondaryContainer, cs.secondaryContainer), greaterThanOrEqualTo(4.5),
            reason: '$t secondaryContainer');
      }
    });
  });
}
