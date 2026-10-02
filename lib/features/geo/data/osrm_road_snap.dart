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

/// OSRM `nearest` client (US-43, R7.11). Mirrors [OsrmRouting]'s style
/// (config-swappable host, short timeout, one retry, circuit breaker, cache)
/// but is called at most once per "เสนอจุดนี้" tap (Q4) — never on every
/// marker drag — so the cache/breaker mostly protect against repeated taps
/// on the same spot, not high call volume.
class OsrmRoadSnap implements RoadSnapService {
  OsrmRoadSnap(this._http, this._cfg, {Clock? clock, Sleeper? sleep})
      : _sleep = sleep ?? realSleep,
        _cache = LruCache(capacity: 30, ttl: const Duration(minutes: 10), clock: clock),
        _breakers = {
          'foot': CircuitBreaker(clock: clock),
          'driving': CircuitBreaker(clock: clock),
        };

  final http.Client _http;
  final ServiceConfig _cfg;
  final Sleeper _sleep;
  final LruCache<String, SnapResult> _cache;
  final Map<String, CircuitBreaker> _breakers;

  @override
  Future<SnapResult> nearest({required TravelMode mode, required LatLng point}) async {
    final profile = mode.osrmProfile;
    final key = '$profile|${coordKey(point, places: 5)}';
    final cached = _cache.get(key);
    if (cached != null) return cached;

    final base = profile == 'foot' ? _cfg.osrmFootBaseUrl : _cfg.osrmCarBaseUrl;
    final uri = Uri.parse(
      '$base/nearest/v1/$profile/${point.longitude},${point.latitude}?number=1',
    );
    final breaker = _breakers[profile]!;
    if (breaker.isOpen) {
      throw const AppFailure(FailureCode.serverUnavailable, retryable: true);
    }

    try {
      final result = await retryTransient(
        () => _fetch(uri, point),
        maxRetries: 1,
        base: const Duration(milliseconds: 300),
        sleep: _sleep,
      );
      breaker.recordSuccess();
      _cache.put(key, result);
      return result;
    } on AppFailure catch (e) {
      if (e.code != FailureCode.routeNotFound && e.code != FailureCode.rateLimited) {
        breaker.recordFailure();
      }
      rethrow;
    }
  }

  Future<SnapResult> _fetch(Uri uri, LatLng raw) async {
    try {
      final res = await _http
          .get(uri, headers: {if (!kIsWeb) 'User-Agent': _cfg.userAgent})
          .timeout(_cfg.snapTimeout);
      if (res.statusCode == 200) {
        return parseOsrmNearestResponse(json.decode(utf8.decode(res.bodyBytes)), raw);
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

/// Pure mapping of an OSRM `/nearest` response; exposed for tests.
/// The deviation is recomputed locally (haversine from [raw]) rather than
/// trusted from OSRM's own `distance` field, so callers get one consistent
/// unit regardless of server version.
SnapResult parseOsrmNearestResponse(Object? body, LatLng raw) {
  if (body is! Map || body['code'] != 'Ok') {
    throw const AppFailure(FailureCode.routeNotFound);
  }
  final waypoints = body['waypoints'];
  if (waypoints is! List || waypoints.isEmpty || waypoints.first is! Map) {
    throw const AppFailure(FailureCode.routeNotFound);
  }
  final w = waypoints.first as Map;
  final loc = w['location'];
  if (loc is! List || loc.length < 2) {
    throw const AppFailure(FailureCode.routeNotFound);
  }
  final lng = loc[0];
  final lat = loc[1];
  if (lng is! num || lat is! num || !isValidLatLng(lat.toDouble(), lng.toDouble())) {
    throw const AppFailure(FailureCode.routeNotFound);
  }
  final snapped = LatLng(lat.toDouble(), lng.toDouble());
  return SnapResult(point: snapped, deviationM: haversineM(raw, snapped));
}
