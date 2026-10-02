import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/config/service_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/geo/geo.dart';
import '../../../core/net/lru_cache.dart';
import '../../../core/net/retry.dart';
import '../../../core/net/throttle.dart';
import '../../trip/domain/travel_mode.dart';
import '../domain/geo_services.dart';

/// OSRM client. Walking uses a separate foot host because the public demo is
/// driving-only. Failure is fail-closed (no estimated route is ever saved).
class OsrmRouting implements RoutingService {
  OsrmRouting(this._http, this._cfg, {Clock? clock, Sleeper? sleep})
      : _sleep = sleep ?? realSleep,
        _cache = LruCache(capacity: 50, ttl: const Duration(minutes: 30), clock: clock),
        _breakers = {
          'foot': CircuitBreaker(clock: clock),
          'driving': CircuitBreaker(clock: clock),
        };

  final http.Client _http;
  final ServiceConfig _cfg;
  final Sleeper _sleep;
  final LruCache<String, RouteResult> _cache;
  final Map<String, CircuitBreaker> _breakers;

  @override
  Future<RouteResult> route({
    required TravelMode mode,
    required LatLng from,
    required LatLng to,
  }) async {
    final profile = mode.osrmProfile;
    final key = '$profile|${coordKey(from)}|${coordKey(to)}';
    final cached = _cache.get(key);
    if (cached != null) return cached;

    final base = profile == 'foot' ? _cfg.osrmFootBaseUrl : _cfg.osrmCarBaseUrl;
    final uri = Uri.parse(
      '$base/route/v1/$profile/${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson&steps=false&alternatives=false',
    );
    final breaker = _breakers[profile]!;
    if (breaker.isOpen) {
      throw const AppFailure(FailureCode.serverUnavailable, retryable: true);
    }

    try {
      final result = await retryTransient(
        () => _fetch(uri),
        maxRetries: 1,
        base: const Duration(milliseconds: 700),
        sleep: _sleep,
      );
      breaker.recordSuccess();
      _cache.put(key, result);
      return result;
    } on AppFailure catch (e) {
      // "No route" and throttling are valid answers, not service outages.
      if (e.code != FailureCode.routeNotFound && e.code != FailureCode.rateLimited) {
        breaker.recordFailure();
      }
      rethrow;
    }
  }

  Future<RouteResult> _fetch(Uri uri) async {
    try {
      final res =
          await _http
              .get(uri, headers: {if (!kIsWeb) 'User-Agent': _cfg.userAgent})
              .timeout(_cfg.routeTimeout);
      // OSRM answers 400 with code NoRoute/NoSegment for unroutable input.
      if (res.statusCode == 200 || res.statusCode == 400) {
        return parseOsrmResponse(json.decode(utf8.decode(res.bodyBytes)));
      }
      throw mapServiceHttpError(res.statusCode, retryAfterHeader: res.headers['retry-after']);
    } on TimeoutException {
      throw const AppFailure(FailureCode.networkTimeout, retryable: true);
    } on SocketException {
      throw const AppFailure(FailureCode.networkOffline, retryable: true);
    } on http.ClientException {
      throw const AppFailure(FailureCode.networkOffline, retryable: true);
    } on FormatException {
      throw const AppFailure(FailureCode.unknown);
    }
  }
}

/// Pure mapping of an OSRM route response; exposed for tests.
RouteResult parseOsrmResponse(Object? body) {
  if (body is! Map || body['code'] != 'Ok') {
    throw const AppFailure(FailureCode.routeNotFound);
  }
  final routes = body['routes'];
  if (routes is! List || routes.isEmpty || routes.first is! Map) {
    throw const AppFailure(FailureCode.routeNotFound);
  }
  final r = routes.first as Map;
  final line = parseLine(r['geometry']);
  final dist = r['distance'];
  final dur = r['duration'];
  if (line == null || line.length < 2 || dist is! num || dur is! num) {
    throw const AppFailure(FailureCode.routeNotFound);
  }
  return RouteResult(
    geometry: simplifyRoute(line),
    distanceM: dist.round().clamp(1, 1 << 30),
    durationS: dur.round().clamp(0, 1 << 30),
  );
}
