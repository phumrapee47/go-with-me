import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_settings.dart';
import 'core/theme/tone.dart';
import 'features/matching/presentation/match_alert_host.dart';
import 'features/matching/presentation/match_moment.dart';
import 'features/push/presentation/push_tap_host.dart';
import 'features/roles/presentation/role_providers.dart';

class GoWithMeApp extends ConsumerWidget {
  const GoWithMeApp({super.key, this.useGoogleFonts = true});

  final bool useGoogleFonts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // App-level tone follows the active role (cached locally, so the first frame is already right);
    // trip-bound screens override it with the tone of their trip (TripRoleTone).
    final tone = ref.watch(appToneProvider);
    // System "remove animations": switch tone instantly (design-spec D.6).
    final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    // US-46 (round 7): our own 4-way resolver (system/light/dark/auto-by-time, Q17) decides the
    // *brightness* fed into the token set; `theme`/`darkTheme`/`themeMode` below keep doing what
    // they always did (encoding rider/driver TONE, never the OS brightness — that hack predates
    // round 7 and is left untouched).
    final themeModeSetting = ref.watch(themeSettingsProvider);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final effectiveBrightness = resolveEffectiveBrightness(
      mode: themeModeSetting,
      platformBrightness: platformBrightness,
      now: DateTime.now(),
    );
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: themeForTone(AppTone.rider, useGoogleFonts: useGoogleFonts, brightness: effectiveBrightness),
      darkTheme: themeForTone(AppTone.driver, useGoogleFonts: useGoogleFonts, brightness: effectiveBrightness),
      // Only ever one of the two: never follow the OS brightness (that's `effectiveBrightness` above).
      themeMode: tone == AppTone.driver ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
      themeAnimationCurve: Curves.easeOut,
      routerConfig: router,
      // App-wide "match ended" alert (Q-7): visible from every screen.
      builder: (context, child) => PushTapHost(
        router: router,
        child: MatchAlertHost(
          router: router,
          child: MatchMomentHost(router: router, child: child ?? const SizedBox.shrink()),
        ),
      ),
      locale: const Locale('th'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('th')],
    );
  }
}
