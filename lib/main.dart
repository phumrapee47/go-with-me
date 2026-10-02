import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/logging/log.dart';
import 'core/providers.dart';
import 'core/storage/secure_local_storage.dart';
import 'demo/demo_mode.dart';
import 'demo/demo_overrides.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo mode: in-memory fakes, Supabase is never initialised (lib/demo).
  if (demoModeEnabled) {
    await runDemoApp(runApp);
    return;
  }

  var config = loadConfigFromEnvironment();
  if (config is ConfigReady) {
    try {
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.anonKey,
        debug: false,
        authOptions: FlutterAuthClientOptions(localStorage: SecureLocalStorage()),
      );
    } catch (_) {
      Log.e('Supabase.initialize failed');
      config = const ConfigProblem(ConfigIssue.initFailed);
    }
  } else {
    Log.d('Supabase config missing/invalid: showing setup screen');
  }

  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        configProvider.overrideWithValue(config),
        sharedPrefsProvider.overrideWithValue(prefs),
      ],
      child: const GoWithMeApp(),
    ),
  );
}
