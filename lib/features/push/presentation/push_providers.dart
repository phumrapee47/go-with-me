import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/providers.dart';
import '../data/supabase_push_repository.dart';
import '../domain/push_repository.dart';
import 'push_service.dart';

/// Production default. DEMO_MODE never touches the real `firebase_messaging`
/// plugin — the demo overrides file swaps this for a fake for the demo
/// hub's "simulate incoming push" tools (same pattern as every other
/// `Provider` here: this file never imports the demo folder itself, only
/// `main.dart`/`app_router.dart` are allowed to).
final pushServiceProvider = Provider<PushService>((ref) => FirebasePushService());

/// Not yet live on any database (0011/0011a are drafts) — see
/// `SupabasePushRepository` doc comment. Overridden in demo mode.
final pushRepositoryProvider = Provider<PushRepository>(
  (ref) => SupabasePushRepository(Supabase.instance.client),
);

const _kAskedPrefsKey = 'push.permission_asked';
const _kMasterPrefsKey = 'push.master_enabled';
const _kTokenPrefsKey = 'push.device_token';

/// G.1.2/2.3 "pending deep link": set when a push is tapped while signed out
/// (stale session). Consumed exactly once by the router right after the next
/// successful sign-in (see `computeRedirect`/`routerProvider`), reusing the
/// same `returnTo` idea as D.9 without adding a second guard mechanism.
final pendingDeepLinkProvider = StateProvider<String?>((ref) => null);

/// One place for the "register/unregister on this device" bookkeeping (R7.3,
/// R7.4, G-1, G-2). Kept as a plain class (not a StateNotifier) because every
/// caller already re-reads/invalidates explicitly, same as
/// `consentRepositoryProvider`'s call sites elsewhere in the app.
class PushController {
  PushController(this._ref);
  final Ref _ref;

  bool get everAsked => _ref.read(sharedPrefsProvider).getBool(_kAskedPrefsKey) ?? false;

  /// G-1 "already-decided": set the moment the user answers the sheet
  /// either way (allow or "ไว้ทีหลัง"), so it is never shown again
  /// automatically (they can still change their mind at G-2).
  Future<void> markAsked() => _ref.read(sharedPrefsProvider).setBool(_kAskedPrefsKey, true);

  /// Q-G1: single master toggle (no per-kind preference this round).
  bool get masterEnabled => _ref.read(sharedPrefsProvider).getBool(_kMasterPrefsKey) ?? true;

  Future<PushPermissionStatus> currentPermission() =>
      _ref.read(pushServiceProvider).currentPermission();

  /// G-1 PushPermissionSheet: shows the Thai rationale, then the OS dialog.
  /// Granting also turns the master toggle on and registers a token
  /// immediately; denying never blocks anything else in the app.
  Future<PushPermissionStatus> requestPermission() async {
    final prefs = _ref.read(sharedPrefsProvider);
    final status = await _ref.read(pushServiceProvider).requestPermission();
    await prefs.setBool(_kAskedPrefsKey, true);
    if (status == PushPermissionStatus.granted) {
      await setMasterEnabled(true);
    }
    return status;
  }

  /// G-2 master toggle. Off = unregister this device's token immediately
  /// (§ design-spec G.1.3). On = register (or re-request permission first if
  /// the OS was never asked).
  Future<void> setMasterEnabled(bool on) async {
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.setBool(_kMasterPrefsKey, on);
    if (!on) {
      await unregisterThisDevice();
      return;
    }
    final status = await currentPermission();
    if (status != PushPermissionStatus.granted) return; // caller opens G-1 again
    await _registerCurrentToken();
  }

  Future<void> _registerCurrentToken() async {
    final service = _ref.read(pushServiceProvider);
    final platform = service.platform;
    if (platform == null) return; // e.g. iOS this round (Q3), or unsupported platform
    final token = await service.getToken();
    if (token == null) return; // fail-open: never surfaces as an app error
    final res = await _ref.read(pushRepositoryProvider).registerToken(token, platform);
    if (res.failureOrNull == null) {
      await _ref.read(sharedPrefsProvider).setString(_kTokenPrefsKey, token);
    }
  }

  /// Called on app start/after sign-in for a user who already granted
  /// permission in an earlier session (no sheet needed again).
  Future<void> ensureRegisteredIfEnabled() async {
    if (!masterEnabled) return;
    final status = await currentPermission();
    if (status != PushPermissionStatus.granted) return;
    await _registerCurrentToken();
  }

  /// R7.4 (Q1): sign-out / delete-account removes only this device's token.
  Future<void> unregisterThisDevice() async {
    final prefs = _ref.read(sharedPrefsProvider);
    final token = prefs.getString(_kTokenPrefsKey);
    if (token == null) return;
    await _ref.read(pushRepositoryProvider).unregisterToken(token);
    await prefs.remove(_kTokenPrefsKey);
  }
}

final pushControllerProvider = Provider<PushController>((ref) => PushController(ref));
