import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../core/error/app_failure.dart';
import '../core/error/result.dart';
import '../core/geo/geo.dart';
import '../features/geo/domain/geo_services.dart';
import '../features/push/domain/push_models.dart';
import '../features/push/domain/push_repository.dart';
import '../features/push/presentation/push_service.dart';
import '../features/trip/domain/travel_mode.dart';

/// Round 7 stage A demo fakes (US-42 push, DB-independent half). Never
/// touches `firebase_messaging`/Supabase — mirrors every other `Demo*`
/// repository in this folder.
class DemoPushService implements PushService {
  final _foreground = StreamController<PushMessage>.broadcast();
  final _tap = StreamController<PushMessage>.broadcast();
  final _tokenRefresh = StreamController<String>.broadcast();

  bool granted = true;
  int _tokenSeq = 0;

  @override
  DevicePlatform? platform = DevicePlatform.android;

  @override
  Future<PushPermissionStatus> requestPermission() async =>
      granted ? PushPermissionStatus.granted : PushPermissionStatus.denied;

  @override
  Future<PushPermissionStatus> currentPermission() async =>
      granted ? PushPermissionStatus.granted : PushPermissionStatus.denied;

  @override
  Future<String?> getToken() async => granted ? 'demo-device-token-${_tokenSeq++}' : null;

  @override
  Stream<String> get onTokenRefresh => _tokenRefresh.stream;

  @override
  Stream<PushMessage> get onForegroundMessage => _foreground.stream;

  @override
  Stream<PushMessage> get onMessageTap => _tap.stream;

  /// Demo hub tool: "app open elsewhere" -> in-app banner (G.1.5).
  void simulateForeground(PushMessage m) => _foreground.add(m);

  /// Demo hub tool: "tap the notification" -> deep-link routing (G-3).
  void simulateTap(PushMessage m) => _tap.add(m);
}

class DemoPushRepository implements PushRepository {
  final registered = <String, DevicePlatform>{};

  @override
  Future<Result<void>> registerToken(String token, DevicePlatform platform) async {
    registered[token] = platform;
    return const Ok(null);
  }

  @override
  Future<Result<void>> unregisterToken(String token) async {
    registered.remove(token);
    return const Ok(null);
  }
}

/// US-43 road-snap fake: never touches the real OSRM host in demo mode
/// (same discipline as `DemoRouting`). A hub toggle drives the 3 outcomes
/// (G.2.1): snap ~15 m away (accepted), snap ~200 m away (rejected, over the
/// `snapMaxDeviationM` default of 40 m), or simulated service failure.
enum DemoSnapMode { accept, rejectDeviation, fail }

class DemoRoadSnap implements RoadSnapService {
  DemoSnapMode mode = DemoSnapMode.accept;

  @override
  Future<SnapResult> nearest({required TravelMode mode, required LatLng point}) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    switch (this.mode) {
      case DemoSnapMode.accept:
        // ~0.00015 deg ~= 15-17 m at Bangkok's latitude.
        final snapped = LatLng(point.latitude + 0.00015, point.longitude);
        return SnapResult(point: snapped, deviationM: haversineM(point, snapped));
      case DemoSnapMode.rejectDeviation:
        final far = LatLng(point.latitude + 0.0018, point.longitude);
        return SnapResult(point: far, deviationM: haversineM(point, far));
      case DemoSnapMode.fail:
        throw const AppFailure(FailureCode.serverUnavailable, retryable: true);
    }
  }
}
