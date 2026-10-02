import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

const _earthRadiusM = 6371008.8;

/// Great-circle distance in metres.
double haversineM(LatLng a, LatLng b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
}

double _rad(double d) => d * math.pi / 180;

/// Rounds a coordinate to [places] decimals; used for cache keys
/// (4 places is roughly 11 m).
String coordKey(LatLng p, {int places = 4}) =>
    '${p.latitude.toStringAsFixed(places)},${p.longitude.toStringAsFixed(places)}';

/// Short human label used when reverse geocoding fails: "13.7455, 100.5345".
String coordLabel(LatLng p) => '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';

bool isValidLatLng(double lat, double lng) =>
    lat.isFinite && lng.isFinite && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

// ---- PostGIS wire formats ---------------------------------------------------

/// EWKT for insert. PostGIS order is lng first (design-api section 2).
String pointEwkt(LatLng p) => 'SRID=4326;POINT(${_n(p.longitude)} ${_n(p.latitude)})';

String lineEwkt(List<LatLng> pts) =>
    'SRID=4326;LINESTRING(${pts.map((p) => '${_n(p.longitude)} ${_n(p.latitude)}').join(', ')})';

String _n(double v) => v.toStringAsFixed(6);

/// Parses what PostgREST returns for a geography value: a GeoJSON object or
/// (for geography, which has no JSON cast) a hex-encoded EWKB string.
/// Returns null when the value cannot be understood.
LatLng? parsePoint(Object? v) {
  if (v is Map) {
    final c = v['coordinates'];
    if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
      return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
    }
    return null;
  }
  if (v is String) {
    final pts = _ewkbCoords(v);
    if (pts != null && pts.isNotEmpty) return pts.first;
  }
  return null;
}

List<LatLng>? parseLine(Object? v) {
  if (v is Map) {
    final c = v['coordinates'];
    if (c is List) {
      final out = <LatLng>[];
      for (final p in c) {
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
          out.add(LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()));
        }
      }
      return out;
    }
    return null;
  }
  if (v is String) return _ewkbCoords(v);
  return null;
}

/// Minimal little/big-endian EWKB reader for Point and LineString (2D).
List<LatLng>? _ewkbCoords(String hex) {
  try {
    if (hex.length < 10 || hex.length.isOdd) return null;
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    final data = ByteData.sublistView(bytes);
    final endian = bytes[0] == 1 ? Endian.little : Endian.big;
    var off = 1;
    final type = data.getUint32(off, endian);
    off += 4;
    if (type & 0x20000000 != 0) off += 4; // SRID
    final base = type & 0xFF;
    // Z/M flags would change the stride; not used by this schema.
    if (type & 0x80000000 != 0 || type & 0x40000000 != 0) return null;
    LatLng read() {
      final x = data.getFloat64(off, endian);
      final y = data.getFloat64(off + 8, endian);
      off += 16;
      return LatLng(y, x);
    }

    if (base == 1) return [read()];
    if (base == 2) {
      final n = data.getUint32(off, endian);
      off += 4;
      return [for (var i = 0; i < n; i++) read()];
    }
    return null;
  } catch (_) {
    return null;
  }
}

// ---- Route simplification ---------------------------------------------------

/// Douglas-Peucker simplification in a local equirectangular projection.
/// Keeps first/last points. If the result still exceeds [maxPoints] the
/// tolerance is doubled until it fits (design-api section 9.3: <= 500 points).
List<LatLng> simplifyRoute(List<LatLng> pts, {double toleranceM = 10, int maxPoints = 500}) {
  if (pts.length <= 2) return List.of(pts);
  final lat0 = pts.first.latitude;
  final kx = 111320.0 * math.cos(_rad(lat0));
  const ky = 110540.0;
  final xy = [for (final p in pts) (p.longitude * kx, p.latitude * ky)];

  var tol = toleranceM;
  while (true) {
    final keep = List<bool>.filled(pts.length, false)
      ..[0] = true
      ..[pts.length - 1] = true;
    final stack = <(int, int)>[(0, pts.length - 1)];
    while (stack.isNotEmpty) {
      final (a, b) = stack.removeLast();
      var maxD = 0.0;
      var idx = -1;
      for (var i = a + 1; i < b; i++) {
        final d = _segDist(xy[i], xy[a], xy[b]);
        if (d > maxD) {
          maxD = d;
          idx = i;
        }
      }
      if (idx != -1 && maxD > tol) {
        keep[idx] = true;
        stack..add((a, idx))..add((idx, b));
      }
    }
    final out = <LatLng>[for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
    if (out.length <= maxPoints) return out;
    tol *= 2;
  }
}

double _segDist((double, double) p, (double, double) a, (double, double) b) {
  final dx = b.$1 - a.$1;
  final dy = b.$2 - a.$2;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) return math.sqrt(math.pow(p.$1 - a.$1, 2) + math.pow(p.$2 - a.$2, 2));
  final t = (((p.$1 - a.$1) * dx + (p.$2 - a.$2) * dy) / len2).clamp(0.0, 1.0);
  final cx = a.$1 + t * dx;
  final cy = a.$2 + t * dy;
  return math.sqrt(math.pow(p.$1 - cx, 2) + math.pow(p.$2 - cy, 2));
}

/// Shortest distance in metres from [p] to the polyline [route] (equirectangular
/// approximation, fine for the sub-kilometre checks it is used for). Infinity
/// for an empty route.
double distanceToRouteM(LatLng p, List<LatLng> route) {
  if (route.isEmpty) return double.infinity;
  if (route.length == 1) return haversineM(p, route.first);
  final cosLat = math.cos(_rad(p.latitude));
  (double, double) xy(LatLng q) => (
        _rad(q.longitude - p.longitude) * cosLat * 6371000.0,
        _rad(q.latitude - p.latitude) * 6371000.0,
      );
  var best = double.infinity;
  for (var i = 0; i < route.length - 1; i++) {
    final d = _segDist((0, 0), xy(route[i]), xy(route[i + 1]));
    if (d < best) best = d;
  }
  return best;
}
