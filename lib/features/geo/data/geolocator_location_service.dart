import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/result.dart';
import '../domain/location_service.dart';

class GeolocatorLocationService implements LocationService {
  /// BUG-2 (round 8): `Geolocator.isLocationServiceEnabled` /
  /// `checkPermission` / `requestPermission` have no built-in timeout and are
  /// known to hang on some devices/GPS states, causing an ANR upstream
  /// (`obtainCurrentLocation` always awaits these before `currentPosition`).
  /// Every native call below is wrapped with `.timeout` so a stuck plugin
  /// call always resolves within a bounded time instead of blocking the flow.
  /// Timeouts are constructor params (default 12 s) so tests can use a short
  /// value instead of actually waiting seconds for a hang to be detected.
  const GeolocatorLocationService({
    Duration permissionTimeout = const Duration(seconds: 12),
    Duration positionTimeout = const Duration(seconds: 12),
  })  : _permissionTimeout = permissionTimeout,
        _positionTimeout = positionTimeout;

  final Duration _permissionTimeout;
  final Duration _positionTimeout;

  /// BUG-2 (web current-location fix, round 9): iOS Safari (and most modern
  /// browsers) only expose `navigator.geolocation` on secure contexts —
  /// `https://` or `localhost`/`127.0.0.1`. Accessed over a plain
  /// `http://<lan-ip>` origin (e.g. `flutter run -d web-server` tested from a
  /// phone over a hotspot), `geolocator_web`'s `requestPermission()` /
  /// `getCurrentPosition()` still get called, but the underlying browser call
  /// always fails (observed as a `PermissionDeniedException`, see
  /// `geolocator_web`'s `convertPositionError` mapping code 1) — *even when
  /// `navigator.permissions.query` separately reports `granted`*, because
  /// that query isn't gated by secure-context the same way. The previous
  /// code caught every `currentPosition()` failure with one generic
  /// `catch (_)`, so this hard browser restriction was indistinguishable
  /// from a real GPS/timeout failure and always surfaced the same unhelpful
  /// "couldn't get location" text. This is a browser security boundary, not
  /// something app code can work around, so it is detected up front and
  /// reported honestly instead.
  static bool get _isInsecureWebOrigin {
    if (!kIsWeb) return false;
    final uri = Uri.base;
    if (uri.scheme == 'https') return false;
    const localHosts = {'localhost', '127.0.0.1', '::1', '[::1]'};
    return !localHosts.contains(uri.host);
  }

  LocationPermissionState _map(LocationPermission p) => switch (p) {
        LocationPermission.always || LocationPermission.whileInUse => LocationPermissionState.granted,
        LocationPermission.deniedForever => LocationPermissionState.deniedForever,
        _ => LocationPermissionState.denied,
      };

  @override
  Future<LocationPermissionState> permission() async {
    try {
      final enabled =
          await Geolocator.isLocationServiceEnabled().timeout(_permissionTimeout);
      if (!enabled) return LocationPermissionState.serviceOff;
      return _map(await Geolocator.checkPermission().timeout(_permissionTimeout));
    } on TimeoutException {
      // No enum value maps to "unknown/timed out"; `serviceOff` is the
      // closest existing state and (unlike `denied`) drives callers straight
      // to an immediate error message instead of re-showing the consent
      // dialog (see current_location.dart `obtainCurrentLocation`).
      return LocationPermissionState.serviceOff;
    }
  }

  @override
  Future<LocationPermissionState> request() async {
    try {
      final enabled =
          await Geolocator.isLocationServiceEnabled().timeout(_permissionTimeout);
      if (!enabled) return LocationPermissionState.serviceOff;
      return _map(await Geolocator.requestPermission().timeout(_permissionTimeout));
    } on TimeoutException {
      return LocationPermissionState.serviceOff;
    }
  }

  @override
  Future<Result<LatLng>> currentPosition() async {
    if (_isInsecureWebOrigin) {
      return const Err(AppFailure(FailureCode.locationInsecureOrigin));
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      ).timeout(_positionTimeout);
      return Ok(LatLng(p.latitude, p.longitude));
    } on TimeoutException {
      return const Err(AppFailure(FailureCode.networkTimeout));
    } on PermissionDeniedException {
      // Kept distinct from the generic branch below: on web this is also
      // what an insecure-origin browser refusal surfaces as (see
      // `_isInsecureWebOrigin` doc above) if the origin check above ever
      // misses a case (e.g. an environment with a non-browser `Uri.base`),
      // so it still reads as a permission problem rather than "unavailable".
      return const Err(AppFailure(FailureCode.locationDenied));
    } catch (_) {
      return const Err(AppFailure(FailureCode.locationUnavailable));
    }
  }

  @override
  Stream<LocationFix> watch() => Geolocator.getPositionStream(
        // While-in-use only: no foreground service / background mode is
        // configured, so updates stop when the app is not visible.
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).map((p) => LocationFix(
            point: LatLng(p.latitude, p.longitude),
            at: p.timestamp,
            accuracyM: p.accuracy,
          ));
}
