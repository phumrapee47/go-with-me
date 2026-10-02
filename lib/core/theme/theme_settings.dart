import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// US-46 (round 7): the 4-way theme choice (design-spec-round7 G-10 /
/// requirements-round7-ba.md US-46 AC1). Manual light/dark always wins over
/// system and over auto-by-time; "system" defers to the OS; "autoByTime" uses
/// the device clock only (Q17 — no GPS/sunrise-sunset math).
enum ThemeModeSetting {
  system('system'),
  light('light'),
  dark('dark'),
  autoByTime('auto_by_time');

  const ThemeModeSetting(this.storageValue);
  final String storageValue;

  static ThemeModeSetting fromStorage(Object? v) {
    for (final m in values) {
      if (m.storageValue == v) return m;
    }
    return ThemeModeSetting.system;
  }
}

/// Auto-by-time window (Q17, US-46 AC2): 18:00 inclusive to 06:00 exclusive, device local time.
bool isNightByClock(DateTime now) => now.hour >= 18 || now.hour < 6;

/// Pure resolver so the 4-way logic is unit-testable without a widget tree.
/// [platformBrightness] is only consulted for [ThemeModeSetting.system].
Brightness resolveEffectiveBrightness({
  required ThemeModeSetting mode,
  required Brightness platformBrightness,
  required DateTime now,
}) =>
    switch (mode) {
      ThemeModeSetting.light => Brightness.light,
      ThemeModeSetting.dark => Brightness.dark,
      ThemeModeSetting.system => platformBrightness,
      ThemeModeSetting.autoByTime => isNightByClock(now) ? Brightness.dark : Brightness.light,
    };

const _prefsKey = 'gwm.themeModeSetting';

class ThemeSettingsController extends Notifier<ThemeModeSetting> {
  @override
  ThemeModeSetting build() {
    final raw = ref.read(sharedPrefsProvider).getString(_prefsKey);
    return ThemeModeSetting.fromStorage(raw);
  }

  Future<void> setMode(ThemeModeSetting mode) async {
    state = mode;
    await ref.read(sharedPrefsProvider).setString(_prefsKey, mode.storageValue);
  }
}

final themeSettingsProvider = NotifierProvider<ThemeSettingsController, ThemeModeSetting>(
  ThemeSettingsController.new,
);
