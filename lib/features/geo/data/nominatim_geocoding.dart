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
import '../domain/geo_services.dart';

/// Nominatim client: 1 req/s throttle, LRU cache, one retry on transient
/// errors, cooldown on 429/403, circuit breaker (design-api section 9.2).
class NominatimGeocoding implements GeocodingService {
  NominatimGeocoding(
    this._http,
    this._cfg, {
    Throttle? throttle,
    Clock? clock,
    Sleeper? sleep,
  })  : _clock = clock ?? DateTime.now,
        _sleep = sleep ?? realSleep,
        _throttle = throttle ?? Throttle(_cfg.geoMinInterval, clock: clock, sleep: sleep),
        _breaker = CircuitBreaker(clock: clock),
        _search = LruCache(capacity: 200, ttl: const Duration(hours: 24), clock: clock),
        _reverse = LruCache(capacity: 200, ttl: const Duration(hours: 24), clock: clock);

  final http.Client _http;
  final ServiceConfig _cfg;
  final Throttle _throttle;
  final Clock _clock;
  final Sleeper _sleep;
  final CircuitBreaker _breaker;
  final LruCache<String, List<PlaceSuggestion>> _search;
  final LruCache<String, String> _reverse;
  DateTime? _cooldownUntil;

  static String normalize(String q) => q.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  @override
  Future<List<PlaceSuggestion>> search(String query) async {
    final q = normalize(query);
    final cached = _search.get(q);
    if (cached != null) return cached;
    final uri = Uri.parse('${_cfg.nominatimBaseUrl}/search').replace(queryParameters: {
      'q': q,
      'format': 'jsonv2',
      'limit': '5',
      'countrycodes': 'th',
      'accept-language': 'th',
      'addressdetails': '0',
    });
    final body = await _get(uri);
    final list = body is List ? body : const [];
    final out = <PlaceSuggestion>[];
    for (final e in list) {
      if (e is! Map) continue;
      final lat = double.tryParse('${e['lat']}');
      final lon = double.tryParse('${e['lon']}');
      final name = e['display_name'];
      if (lat == null || lon == null || name is! String || !isValidLatLng(lat, lon)) continue;
      out.add(PlaceSuggestion(label: name, point: LatLng(lat, lon)));
    }
    // "Not found" is cached briefly so retyping does not hammer the server.
    _search.put(q, out, ttl: out.isEmpty ? const Duration(minutes: 10) : null);
    return out;
  }

  @override
  Future<String> reverse(LatLng p) async {
    final key = coordKey(p);
    final cached = _reverse.get(key);
    if (cached != null) return cached;
    final uri = Uri.parse('${_cfg.nominatimBaseUrl}/reverse').replace(queryParameters: {
      'lat': p.latitude.toStringAsFixed(6),
      'lon': p.longitude.toStringAsFixed(6),
      'format': 'jsonv2',
      'zoom': '18',
      'accept-language': 'th',
    });
    final body = await _get(uri);
    final name = body is Map ? body['display_name'] : null;
    if (name is! String || name.isEmpty) throw const AppFailure(FailureCode.notFound);
    _reverse.put(key, name);
    return name;
  }

  Future<Object?> _get(Uri uri) async {
    final until = _cooldownUntil;
    if (until != null && _clock().isBefore(until)) {
      throw AppFailure(FailureCode.rateLimited, retryAfter: until.difference(_clock()));
    }
    if (_breaker.isOpen) {
      throw const AppFailure(FailureCode.serverUnavailable, retryable: true);
    }
    try {
      Object? res;
      try {
        res = await _attempt(uri);
      } on AppFailure catch (e) {
        if (!e.retryable) rethrow;
        // One retry after ~900ms (network error/timeout/502-504 only).
        await _sleep(const Duration(milliseconds: 900));
        res = await _attempt(uri);
      }
      _breaker.recordSuccess();
      return res;
    } on AppFailure catch (e) {
      if (e.code == FailureCode.rateLimited) {
        _cooldownUntil = _clock().add(e.retryAfter ?? const Duration(seconds: 60));
      } else {
        _breaker.recordFailure();
      }
      rethrow;
    }
  }

  Future<Object?> _attempt(Uri uri) => _throttle.run(() async {
        try {
          final res = await _http.get(uri, headers: {
            if (!kIsWeb) 'User-Agent': _cfg.userAgent,
            'Accept-Language': 'th',
          }).timeout(_cfg.geoTimeout);
          if (res.statusCode == 200) return json.decode(utf8.decode(res.bodyBytes));
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
      });
}
