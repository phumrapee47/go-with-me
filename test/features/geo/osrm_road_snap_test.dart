import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/config/service_config.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/features/geo/data/osrm_road_snap.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

class _Clock {
  DateTime now = DateTime(2026, 1, 1);
  DateTime call() => now;
  Future<void> sleep(Duration d) async => now = now.add(d);
}

const _cfg = ServiceConfig(userAgent: 'GoWithMe/test (contact: t@example.com)');
const _raw = LatLng(13.7460, 100.5340);

http.Response _json(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

String _ok(double lat, double lng) =>
    jsonEncode({
      'code': 'Ok',
      'waypoints': [
        {
          'location': [lng, lat],
          'distance': 5,
        }
      ],
    });

Future<AppFailure> _failure(Future<Object?> f) async {
  try {
    await f;
  } on AppFailure catch (e) {
    return e;
  }
  fail('expected AppFailure');
}

void main() {
  group('parseOsrmNearestResponse', () {
    test('parses a valid response and recomputes the deviation locally', () {
      final r = parseOsrmNearestResponse(jsonDecode(_ok(13.7461, 100.5341)), _raw);
      expect(r.point, const LatLng(13.7461, 100.5341));
      expect(r.deviationM, greaterThan(0));
      expect(r.deviationM, lessThan(50));
    });

    test('non-Ok code throws routeNotFound', () {
      expect(
        () => parseOsrmNearestResponse(jsonDecode('{"code":"NoSegment","waypoints":[]}'), _raw),
        throwsA(isA<AppFailure>().having((e) => e.code, 'code', FailureCode.routeNotFound)),
      );
    });

    test('missing waypoints throws routeNotFound', () {
      expect(
        () => parseOsrmNearestResponse(jsonDecode('{"code":"Ok"}'), _raw),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('OsrmRoadSnap', () {
    test('fetches, parses, and caches identical points', () async {
      final c = _Clock();
      var calls = 0;
      late http.Request seen;
      final s = OsrmRoadSnap(
        MockClient((r) async {
          calls++;
          seen = r;
          return _json(_ok(13.7461, 100.5341));
        }),
        _cfg,
        clock: c.call,
        sleep: c.sleep,
      );
      final a = await s.nearest(mode: TravelMode.car, point: _raw);
      final b = await s.nearest(mode: TravelMode.car, point: _raw);
      expect(a.point, const LatLng(13.7461, 100.5341));
      expect(b, same(a));
      expect(calls, 1);
      expect(seen.url.path, contains('/nearest/v1/driving/'));
      expect(seen.headers['User-Agent'], contains('GoWithMe'));
    });

    test('foot mode uses the foot host and profile', () async {
      late http.Request seen;
      final s = OsrmRoadSnap(
        MockClient((r) async {
          seen = r;
          return _json(_ok(13.7461, 100.5341));
        }),
        _cfg,
      );
      await s.nearest(mode: TravelMode.walk, point: _raw);
      expect(seen.url.host, Uri.parse(_cfg.osrmFootBaseUrl).host);
      expect(seen.url.path, contains('/nearest/v1/foot/'));
    });

    test('retries once on a transient failure then succeeds', () async {
      final c = _Clock();
      var calls = 0;
      final s = OsrmRoadSnap(
        MockClient((r) async {
          calls++;
          if (calls == 1) return http.Response('', 503);
          return _json(_ok(13.7461, 100.5341));
        }),
        _cfg,
        clock: c.call,
        sleep: c.sleep,
      );
      final r = await s.nearest(mode: TravelMode.car, point: _raw);
      expect(calls, 2);
      expect(r.point, const LatLng(13.7461, 100.5341));
    });

    test('timeout maps to networkTimeout (fail-open contract for the caller)', () async {
      final cfg = ServiceConfig(
        userAgent: _cfg.userAgent,
        snapTimeout: const Duration(milliseconds: 5),
      );
      final c = _Clock();
      final s = OsrmRoadSnap(
        MockClient((r) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return _json(_ok(13.7461, 100.5341));
        }),
        cfg,
        clock: c.call,
        sleep: c.sleep,
      );
      final f = await _failure(s.nearest(mode: TravelMode.car, point: _raw));
      expect(f.code, FailureCode.networkTimeout);
      expect(f.retryable, isTrue);
    });

    test('rate limited (429) maps to rateLimited and never opens the circuit breaker', () async {
      final c = _Clock();
      var calls = 0;
      final s = OsrmRoadSnap(
        MockClient((r) async {
          calls++;
          return http.Response('', 429, headers: {'retry-after': '30'});
        }),
        _cfg,
        clock: c.call,
        sleep: c.sleep,
      );
      for (var i = 0; i < 5; i++) {
        final f = await _failure(s.nearest(mode: TravelMode.car, point: LatLng(13.74 + i * 0.01, 100.53)));
        expect(f.code, FailureCode.rateLimited);
      }
      // A 6th distinct point still reaches the network (breaker never tripped
      // by rate-limiting alone) rather than fail fast from an open breaker.
      final before = calls;
      await _failure(s.nearest(mode: TravelMode.car, point: const LatLng(13.9, 100.6)));
      expect(calls, greaterThan(before));
    });
  });
}
