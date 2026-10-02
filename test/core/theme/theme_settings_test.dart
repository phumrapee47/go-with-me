import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/theme/theme_settings.dart';
import 'package:gowithme/core/theme/tone.dart';

void main() {
  group('isNightByClock (Q17: device clock only, 18:00-06:00)', () {
    test('18:00 is night (inclusive)', () => expect(isNightByClock(DateTime(2026, 1, 1, 18, 0)), isTrue));
    test('05:59 is night', () => expect(isNightByClock(DateTime(2026, 1, 1, 5, 59)), isTrue));
    test('06:00 is day (exclusive)', () => expect(isNightByClock(DateTime(2026, 1, 1, 6, 0)), isFalse));
    test('17:59 is day', () => expect(isNightByClock(DateTime(2026, 1, 1, 17, 59)), isFalse));
    test('midnight is night', () => expect(isNightByClock(DateTime(2026, 1, 1, 0, 0)), isTrue));
    test('noon is day', () => expect(isNightByClock(DateTime(2026, 1, 1, 12, 0)), isFalse));
  });

  group('resolveEffectiveBrightness', () {
    final noon = DateTime(2026, 1, 1, 12);
    final midnight = DateTime(2026, 1, 1, 23);

    test('light mode is always light regardless of clock/platform', () {
      expect(
        resolveEffectiveBrightness(mode: ThemeModeSetting.light, platformBrightness: Brightness.dark, now: midnight),
        Brightness.light,
      );
    });

    test('dark mode is always dark regardless of clock/platform', () {
      expect(
        resolveEffectiveBrightness(mode: ThemeModeSetting.dark, platformBrightness: Brightness.light, now: noon),
        Brightness.dark,
      );
    });

    test('system mode follows the platform brightness, ignoring the clock', () {
      expect(
        resolveEffectiveBrightness(mode: ThemeModeSetting.system, platformBrightness: Brightness.dark, now: noon),
        Brightness.dark,
      );
      expect(
        resolveEffectiveBrightness(mode: ThemeModeSetting.system, platformBrightness: Brightness.light, now: midnight),
        Brightness.light,
      );
    });

    test('auto-by-time follows the clock, ignoring the platform', () {
      expect(
        resolveEffectiveBrightness(mode: ThemeModeSetting.autoByTime, platformBrightness: Brightness.light, now: midnight),
        Brightness.dark,
      );
      expect(
        resolveEffectiveBrightness(mode: ThemeModeSetting.autoByTime, platformBrightness: Brightness.dark, now: noon),
        Brightness.light,
      );
    });
  });

  group('ThemeModeSetting.fromStorage', () {
    test('round-trips every value', () {
      for (final m in ThemeModeSetting.values) {
        expect(ThemeModeSetting.fromStorage(m.storageValue), m);
      }
    });

    test('unknown/missing value defaults to system (fail-safe)', () {
      expect(ThemeModeSetting.fromStorage(null), ThemeModeSetting.system);
      expect(ThemeModeSetting.fromStorage('nonsense'), ThemeModeSetting.system);
    });
  });

  group('ToneColors.resolve + contrast (G.5.1.3 golden pairs, WCAG AA)', () {
    test('rider-dark text on bg/surface/raised passes >= 4.5:1', () {
      final c = ToneColors.resolve(AppTone.rider, Brightness.dark);
      expect(contrastRatio(c.text, c.bg), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(c.text, c.surface), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(c.text, c.surfaceRaised), greaterThanOrEqualTo(4.5));
    });

    test('driver-dark text on bg/surface/raised passes >= 4.5:1', () {
      final c = ToneColors.resolve(AppTone.driver, Brightness.dark);
      expect(contrastRatio(c.text, c.bg), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(c.text, c.surface), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(c.text, c.surfaceRaised), greaterThanOrEqualTo(4.5));
    });

    test('driver-dark onPrimary on primary (amber) passes >= 4.5:1', () {
      final c = ToneColors.resolve(AppTone.driver, Brightness.dark);
      expect(contrastRatio(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
    });

    test('rider-dark onPrimary on primary passes >= 4.5:1', () {
      final c = ToneColors.resolve(AppTone.rider, Brightness.dark);
      expect(contrastRatio(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
    });

    test('resolve() picks the 4 distinct token sets', () {
      expect(ToneColors.resolve(AppTone.rider, Brightness.light), ToneColors.rider);
      expect(ToneColors.resolve(AppTone.driver, Brightness.light), ToneColors.driver);
      expect(ToneColors.resolve(AppTone.rider, Brightness.dark), ToneColors.riderDark);
      expect(ToneColors.resolve(AppTone.driver, Brightness.dark), ToneColors.driverDark);
    });

    test('driver-dark amber is dimmer than driver-light amber (Q-G5)', () {
      // Luminance proxy: dimmer amber should be darker (lower red channel) than driver-light's.
      expect(ToneColors.driverDark.primary.r, lessThan(ToneColors.driver.primary.r));
    });
  });
}
