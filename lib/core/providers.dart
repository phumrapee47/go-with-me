import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'config/app_constants.dart';

/// Overridden in main() with the evaluated config.
final configProvider = Provider<ConfigState>(
  (ref) => throw UnimplementedError('configProvider must be overridden'),
);

/// Overridden in main() with a pre-loaded instance (sync reads afterwards).
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

final splashDurationProvider = Provider<Duration>((ref) => AppConstants.splashDuration);

/// Completes once the minimum splash time has elapsed.
final splashElapsedProvider = FutureProvider<void>(
  (ref) => Future<void>.delayed(ref.watch(splashDurationProvider)),
);
