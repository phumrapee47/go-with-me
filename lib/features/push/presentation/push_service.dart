import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import '../../../core/logging/log.dart';
import '../domain/push_models.dart';

/// Whether the OS-level permission has been granted, denied, or never asked.
enum PushPermissionStatus { granted, denied, notDetermined, unsupported }

/// Thin, swappable wrapper around `firebase_messaging` (US-42). Every method
/// is guarded: when Firebase has no config for this app (no
/// `firebase_options.dart`/`google-services.json`/`GoogleService-Info.plist`
/// yet exist — round 7 stage A ships without them), every call fails soft
/// (logs once, returns a neutral value) instead of throwing. This keeps
/// `flutter build web`/`flutter build apk` green and the app usable with
/// push simply inert until a real Firebase project is wired up.
abstract class PushService {
  DevicePlatform? get platform;

  Future<PushPermissionStatus> requestPermission();

  /// Best-effort current permission status without prompting.
  Future<PushPermissionStatus> currentPermission();

  /// null when unavailable (no permission, no Firebase config, web without
  /// a VAPID key, etc.) — callers must treat this as "cannot register yet",
  /// never as an error to surface to the user.
  Future<String?> getToken();

  Stream<String> get onTokenRefresh;

  /// Foreground messages (app open, in view).
  Stream<PushMessage> get onForegroundMessage;

  /// The user tapped a notification (app was backgrounded, now resumed).
  Stream<PushMessage> get onMessageTap;
}

/// Android/Web only this round (Q3: iOS/APNs deferred to P1).
DevicePlatform? currentDevicePlatform() {
  if (kIsWeb) return DevicePlatform.web;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return DevicePlatform.android;
    case TargetPlatform.iOS:
      return DevicePlatform.ios;
    default:
      return null;
  }
}

class FirebasePushService implements PushService {
  FirebasePushService({String? webVapidKey}) : _webVapidKey = webVapidKey;
  final String? _webVapidKey;

  bool _initTried = false;
  bool _available = false;
  final _foreground = StreamController<PushMessage>.broadcast();
  final _tap = StreamController<PushMessage>.broadcast();
  final _tokenRefresh = StreamController<String>.broadcast();
  StreamSubscription<RemoteMessage>? _fgSub;
  StreamSubscription<RemoteMessage>? _tapSub;
  StreamSubscription<String>? _refreshSub;

  @override
  final DevicePlatform? platform = currentDevicePlatform();

  Future<bool> _ensureInit() async {
    if (_initTried) return _available;
    _initTried = true;
    try {
      if (Firebase.apps.isEmpty) {
        // No `firebase_options.dart` generated yet (round 7 stage A has no
        // Firebase project). `Firebase.initializeApp()` without options
        // throws on every platform we support when config is absent —
        // caught here so the rest of the app never sees it.
        await Firebase.initializeApp();
      }
      _fgSub = FirebaseMessaging.onMessage.listen((m) {
        final parsed = PushMessage.fromData(m.data);
        if (parsed != null) _foreground.add(parsed);
      });
      _tapSub = FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final parsed = PushMessage.fromData(m.data);
        if (parsed != null) _tap.add(parsed);
      });
      _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(_tokenRefresh.add);
      _available = true;
    } catch (_) {
      Log.d('Push: Firebase unavailable (no config yet), push is inert');
      _available = false;
    }
    return _available;
  }

  @override
  Future<PushPermissionStatus> requestPermission() async {
    if (!await _ensureInit()) return PushPermissionStatus.unsupported;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      return _mapAuth(settings.authorizationStatus);
    } catch (_) {
      Log.d('Push: requestPermission failed');
      return PushPermissionStatus.unsupported;
    }
  }

  @override
  Future<PushPermissionStatus> currentPermission() async {
    if (!await _ensureInit()) return PushPermissionStatus.unsupported;
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      return _mapAuth(settings.authorizationStatus);
    } catch (_) {
      Log.d('Push: getNotificationSettings failed');
      return PushPermissionStatus.unsupported;
    }
  }

  PushPermissionStatus _mapAuth(AuthorizationStatus s) => switch (s) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermissionStatus.granted,
        AuthorizationStatus.denied => PushPermissionStatus.denied,
        AuthorizationStatus.notDetermined => PushPermissionStatus.notDetermined,
      };

  @override
  Future<String?> getToken() async {
    if (!await _ensureInit()) return null;
    try {
      return await FirebaseMessaging.instance.getToken(vapidKey: kIsWeb ? _webVapidKey : null);
    } catch (_) {
      Log.d('Push: getToken failed');
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => _tokenRefresh.stream;

  @override
  Stream<PushMessage> get onForegroundMessage => _foreground.stream;

  @override
  Stream<PushMessage> get onMessageTap => _tap.stream;

  void dispose() {
    _fgSub?.cancel();
    _tapSub?.cancel();
    _refreshSub?.cancel();
    _foreground.close();
    _tap.close();
    _tokenRefresh.close();
  }
}

/// No Firebase at all: DEMO_MODE, and any environment/test where the plugin
/// must never be touched.
class NoopPushService implements PushService {
  const NoopPushService();

  @override
  DevicePlatform? get platform => currentDevicePlatform();

  @override
  Future<PushPermissionStatus> requestPermission() async => PushPermissionStatus.unsupported;

  @override
  Future<PushPermissionStatus> currentPermission() async => PushPermissionStatus.unsupported;

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<PushMessage> get onForegroundMessage => const Stream.empty();

  @override
  Stream<PushMessage> get onMessageTap => const Stream.empty();
}
