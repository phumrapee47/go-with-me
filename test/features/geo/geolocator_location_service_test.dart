import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/features/geo/data/geolocator_location_service.dart';
import 'package:gowithme/features/geo/domain/location_service.dart';

/// BUG-2 (round 8): verifies `permission()`/`request()`/`currentPosition()`
/// always resolve within their configured timeout, even when the native
/// geolocator plugin hangs forever (the reported ANR cause).
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission checkResult = LocationPermission.whileInUse;
  LocationPermission requestResult = LocationPermission.whileInUse;
  Position? position;

  /// When set, these calls never complete (simulates the native hang).
  bool hangServiceEnabled = false;
  bool hangCheckPermission = false;
  bool hangRequestPermission = false;
  bool hangGetCurrentPosition = false;

  @override
  Future<bool> isLocationServiceEnabled() {
    if (hangServiceEnabled) return Completer<bool>().future;
    return Future.value(serviceEnabled);
  }

  @override
  Future<LocationPermission> checkPermission() {
    if (hangCheckPermission) return Completer<LocationPermission>().future;
    return Future.value(checkResult);
  }

  @override
  Future<LocationPermission> requestPermission() {
    if (hangRequestPermission) return Completer<LocationPermission>().future;
    return Future.value(requestResult);
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    if (hangGetCurrentPosition) return Completer<Position>().future;
    if (position != null) return Future.value(position!);
    throw StateError('no position configured');
  }
}

Position _pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 1, 1),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  late _FakeGeolocatorPlatform fake;
  late GeolocatorLocationService svc;

  setUp(() {
    fake = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = fake;
    svc = const GeolocatorLocationService(
      permissionTimeout: Duration(milliseconds: 50),
      positionTimeout: Duration(milliseconds: 50),
    );
  });

  group('permission()', () {
    test('returns serviceOff within the timeout when isLocationServiceEnabled hangs', () async {
      fake.hangServiceEnabled = true;
      final result = await svc.permission().timeout(const Duration(seconds: 2));
      expect(result, LocationPermissionState.serviceOff);
    });

    test('returns serviceOff within the timeout when checkPermission hangs', () async {
      fake.hangCheckPermission = true;
      final result = await svc.permission().timeout(const Duration(seconds: 2));
      expect(result, LocationPermissionState.serviceOff);
    });

    test('regression: resolves normally (granted) when the plugin answers quickly', () async {
      fake.checkResult = LocationPermission.whileInUse;
      expect(await svc.permission(), LocationPermissionState.granted);
    });

    test('regression: service off is reported immediately, not confused with a timeout', () async {
      fake.serviceEnabled = false;
      expect(await svc.permission(), LocationPermissionState.serviceOff);
    });

    test('regression: denied permission is reported as denied', () async {
      fake.checkResult = LocationPermission.denied;
      expect(await svc.permission(), LocationPermissionState.denied);
    });
  });

  group('request()', () {
    test('returns serviceOff within the timeout when requestPermission hangs', () async {
      fake.hangRequestPermission = true;
      final result = await svc.request().timeout(const Duration(seconds: 2));
      expect(result, LocationPermissionState.serviceOff);
    });

    test('regression: resolves normally (granted) when the plugin answers quickly', () async {
      fake.requestResult = LocationPermission.always;
      expect(await svc.request(), LocationPermissionState.granted);
    });
  });

  group('currentPosition()', () {
    test('returns a networkTimeout failure within the timeout when getCurrentPosition hangs', () async {
      fake.hangGetCurrentPosition = true;
      final result = await svc.currentPosition().timeout(const Duration(seconds: 2));
      result.when(
        ok: (_) => fail('expected a timeout failure'),
        err: (f) => expect(f.code, FailureCode.networkTimeout),
      );
    });

    test('regression: returns the position when the plugin answers quickly', () async {
      fake.position = _pos(13.7455, 100.5345);
      final result = await svc.currentPosition();
      result.when(
        ok: (p) {
          expect(p.latitude, 13.7455);
          expect(p.longitude, 100.5345);
        },
        err: (f) => fail('expected Ok, got $f'),
      );
    });
  });
}
