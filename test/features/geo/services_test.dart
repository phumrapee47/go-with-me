import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/config/service_config.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/features/geo/data/nominatim_geocoding.dart';
import 'package:gowithme/features/geo/data/osrm_routing.dart';
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
const _hit = '[{"lat":"13.7462","lon":"100.5347","display_name":"สยามพารากอน"}]';

http.Response _json(String body, [int status = 200, Map<String, String> h = const {}]) =>
    http.Response.bytes(utf8.encode(body), status, headers: h);

Future<AppFailure> _failure(Future<Object?> f) async {
  try {
    await f;
  } on AppFailure catch (e) {
    return e;
  }
  fail('expected AppFailure');
}

void main() {
  group('NominatimGeocoding', () {
    test('sends UA + Thai params, parses results, second call is cached', () async {
      final c = _Clock();
      var calls = 0;
      late http.Request seen;
      final g = NominatimGeocoding(
        MockClient((r) async {
          calls++;
          seen = r;
          return _json(_hit);
        }),
        _cfg,
        clock: c.call,
        sleep: c.sleep,
      );
      final a = await g.search('  สยาม  ');
      final b = await g.search('สยาม');
      expect(a.single.label, 'สยามพารากอน');
      expect(a.single.point, const LatLng(13.7462, 100.5347));
      expect(b, same(a));
      expect(calls, 1);
      expect(seen.headers['User-Agent'], contains('GoWithMe'));
      expect(seen.url.queryParameters['countrycodes'], 'th');
      expect(seen.url.queryParameters['accept-language'], 'th');
      expect(seen.url.host, 'nominatim.openstreetmap.org');
    });

    test('base URL is swappable via config', () async {
      late Uri seen;
      final g = NominatimGeocoding(
        MockClient((r) async {
          seen = r.url;
          return _json('[]');
        }),
        const ServiceConfig(nominatimBaseUrl: 'https://geo.example.org'),
      );
      await g.search('abc');
      expect(seen.host, 'geo.example.org');
    });

    test('requests are >= 1.1 s apart (1 req/s policy)', () async {
      final c = _Clock();
      final starts = <DateTime>[];
      final g = NominatimGeocoding(
        MockClient((r) async {
          starts.add(c.now);
          return _json(_hit);
        }),
        _cfg,
        clock: c.call,
        sleep: c.sleep,
      );
      await Future.wait([g.search('aaa'), g.search('bbb'), g.search('ccc')]);
      expect(starts.length, 3);
      expect(starts[1].difference(starts[0]), greaterThanOrEqualTo(const Duration(milliseconds: 1100)));
      expect(starts[2].difference(starts[1]), greaterThanOrEqualTo(const Duration(milliseconds: 1100)));
    });

    test('empty result is a normal outcome and is cached', () async {
      var calls = 0;
      final g = NominatimGeocoding(
        MockClient((r) async {
          calls++;
          return _json('[]');
        }),
        _cfg,
      );
      expect(await g.search('zzzz'), isEmpty);
      expect(await g.search('zzzz'), isEmpty);
      expect(calls, 1);
    });

    test('retries once on 503 then succeeds', () async {
      final c = _Clock();
      var calls = 0;
      final g = NominatimGeocoding(
        MockClient((r) async {
          calls++;
          return calls == 1 ? _json('', 503) : _json(_hit);
        }),
        _cfg,
        clock: c.call,
        sleep: c.sleep,
      );
      expect((await g.search('siam')).length, 1);
      expect(calls, 2);
    });

    test('429 is not retried, maps to rateLimited and starts a cooldown', () async {
      final c = _Clock();
      var calls = 0;
      final g = NominatimGeocoding(
        MockClient((r) async {
          calls++;
          return _json('', 429, {'retry-after': '30'});
        }),
        _cfg,
        clock: c.call,
        sleep: c.sleep,
      );
      final f = await _failure(g.search('siam'));
      expect(f.code, FailureCode.rateLimited);
      expect(f.retryAfter, const Duration(seconds: 30));
      expect(calls, 1);
      // Within the cooldown no request leaves the device.
      final f2 = await _failure(g.search('other'));
      expect(f2.code, FailureCode.rateLimited);
      expect(calls, 1);
    });

    test('timeouts map to networkTimeout; breaker then fails fast without HTTP calls', () async {
      final c = _Clock();
      var calls = 0;
      final g = NominatimGeocoding(
        MockClient((r) async {
          calls++;
          throw TimeoutException('slow');
        }),
        _cfg,
        clock: c.call,
        sleep: c.sleep,
      );
      // Each search = 2 attempts (one retry) and counts as one breaker failure.
      expect((await _failure(g.search('aaa'))).code, FailureCode.networkTimeout);
      expect((await _failure(g.search('bbb'))).code, FailureCode.networkTimeout);
      expect((await _failure(g.search('ccc'))).code, FailureCode.networkTimeout);
      final before = calls;
      expect((await _failure(g.search('ddd'))).code, FailureCode.serverUnavailable);
      expect(calls, before);
    });

    test('reverse geocode is cached by rounded coordinates', () async {
      var calls = 0;
      final g = NominatimGeocoding(
        MockClient((r) async {
          calls++;
          return _json('{"display_name":"ถนนสุขุมวิท"}');
        }),
        _cfg,
      );
      expect(await g.reverse(const LatLng(13.745501, 100.534501)), 'ถนนสุขุมวิท');
      expect(await g.reverse(const LatLng(13.745502, 100.534502)), 'ถนนสุขุมวิท');
      expect(calls, 1);
    });
  });

  group('OsrmRouting', () {
    String ok(double dist, double dur) => jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'distance': dist,
              'duration': dur,
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [100.5345, 13.7455],
                  [100.55, 13.80],
                  [100.6, 13.9],
                ],
              },
            },
          ],
        });

    test('walk uses the foot host, lng-first path, parses result', () async {
      late Uri seen;
      final r = OsrmRouting(
        MockClient((req) async {
          seen = req.url;
          return _json(ok(8400.4, 1500.2));
        }),
        _cfg,
      );
      final res = await r.route(
        mode: TravelMode.walk,
        from: const LatLng(13.7455, 100.5345),
        to: const LatLng(13.9, 100.6),
      );
      expect(seen.host, 'routing.openstreetmap.de');
      expect(seen.path, contains('/route/v1/foot/100.5345,13.7455;100.6,13.9'));
      expect(seen.queryParameters['geometries'], 'geojson');
      expect(res.distanceM, 8400);
      expect(res.durationS, 1500);
      expect(res.geometry.first, const LatLng(13.7455, 100.5345));
    });

    test('car/taxi/transit use the driving host', () async {
      final urls = <Uri>[];
      final r = OsrmRouting(
        MockClient((req) async {
          urls.add(req.url);
          return _json(ok(1000, 100));
        }),
        _cfg,
      );
      for (final m in [TravelMode.car, TravelMode.taxi, TravelMode.transit]) {
        await r.route(mode: m, from: LatLng(13.7 + m.index * 0.01, 100.5), to: const LatLng(13.9, 100.6));
      }
      expect(urls.map((u) => u.host).toSet(), {'router.project-osrm.org'});
      expect(urls.every((u) => u.path.contains('/route/v1/driving/')), isTrue);
    });

    test('same request is served from cache', () async {
      var calls = 0;
      final r = OsrmRouting(
        MockClient((req) async {
          calls++;
          return _json(ok(1000, 100));
        }),
        _cfg,
      );
      const a = LatLng(13.7455, 100.5345);
      const b = LatLng(13.9, 100.6);
      await r.route(mode: TravelMode.car, from: a, to: b);
      await r.route(mode: TravelMode.taxi, from: a, to: b); // same profile
      expect(calls, 1);
    });

    test('NoRoute -> ROUTE_NOT_FOUND without retry', () async {
      var calls = 0;
      final r = OsrmRouting(
        MockClient((req) async {
          calls++;
          return _json('{"code":"NoRoute","message":"x"}', 400);
        }),
        _cfg,
        sleep: (_) async {},
      );
      final f = await _failure(r.route(
        mode: TravelMode.car,
        from: const LatLng(1, 1),
        to: const LatLng(2, 2),
      ));
      expect(f.code, FailureCode.routeNotFound);
      expect(calls, 1);
    });

    test('5xx is retried once then reported as serverUnavailable', () async {
      var calls = 0;
      final r = OsrmRouting(
        MockClient((req) async {
          calls++;
          return _json('', 502);
        }),
        _cfg,
        sleep: (_) async {},
      );
      final f = await _failure(r.route(
        mode: TravelMode.car,
        from: const LatLng(1, 1),
        to: const LatLng(2, 2),
      ));
      expect(f.code, FailureCode.serverUnavailable);
      expect(calls, 2);
    });

    test('parseOsrmResponse rejects malformed bodies', () {
      expect(() => parseOsrmResponse({'code': 'Ok', 'routes': []}), throwsA(isA<AppFailure>()));
      expect(() => parseOsrmResponse('nope'), throwsA(isA<AppFailure>()));
    });
  });
}
