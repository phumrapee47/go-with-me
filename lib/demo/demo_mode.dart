/// Demo mode (no Supabase). Enabled ONLY by `--dart-define=DEMO_MODE=true`.
///
/// The define defaults to false, so no build (release included) runs demo
/// mode unless it was explicitly requested at build time.
/// To remove the feature: delete lib/demo/, the `demoModeEnabled` branch in
/// lib/main.dart, and the `extraRoutesProvider` hook in app_router.dart.
const bool demoModeEnabled = bool.fromEnvironment('DEMO_MODE');
