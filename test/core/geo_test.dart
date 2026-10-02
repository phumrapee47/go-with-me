import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/geo/geo.dart';
import 'package:latlong2/latlong.dart';

String _hexPoint(double x, double y, {bool srid = true}) {
  final b = ByteData(1 + 4 + (srid ? 4 : 0) + 16);
  var o = 0;
  b.setUint8(o++, 1); // little endian
  b.setUint32(o, srid ? 0x20000001 : 1, Endian.little);
  o += 4;
  if (srid) {
    b.setUint32(o, 4326, Endian.little);
    o += 4;
  }
  b.setFloat64(o, x, Endian.little);
  b.setFloat64(o + 8, y, Endian.little);
  return [for (final v in b.buffer.asUint8List()) v.toRadixString(16).padLeft(2, '0')].join();
}

void main() {
  test('haversine ~ known distance', () {
    // Siam -> Chatuchak is roughly 8-9 km.
    final d = haversineM(const LatLng(13.7455, 100.5345), const LatLng(13.8027, 100.5537));
    expect(d, inInclusiveRange(6000, 7500));
    expect(haversineM(const LatLng(1, 1), const LatLng(1, 1)), 0);
  });

  test('EWKT is lng-first', () {
    expect(pointEwkt(const LatLng(13.7455, 100.5345)), 'SRID=4326;POINT(100.534500 13.745500)');
    expect(
      lineEwkt(const [LatLng(1, 2), LatLng(3, 4)]),
      'SRID=4326;LINESTRING(2.000000 1.000000, 4.000000 3.000000)',
    );
  });

  test('parsePoint understands GeoJSON and hex EWKB (with/without SRID)', () {
    expect(parsePoint({'type': 'Point', 'coordinates': [100.5, 13.7]}), const LatLng(13.7, 100.5));
    expect(parsePoint(_hexPoint(100.5, 13.7)), const LatLng(13.7, 100.5));
    expect(parsePoint(_hexPoint(100.5, 13.7, srid: false)), const LatLng(13.7, 100.5));
    expect(parsePoint('zz'), isNull);
    expect(parsePoint(null), isNull);
    expect(parsePoint({'coordinates': 'x'}), isNull);
  });

  test('parseLine reads GeoJSON LineString', () {
    final l = parseLine(jsonDecode('{"type":"LineString","coordinates":[[100.1,13.1],[100.2,13.2]]}'));
    expect(l, const [LatLng(13.1, 100.1), LatLng(13.2, 100.2)]);
  });

  group('simplifyRoute', () {
    test('keeps endpoints and drops collinear points', () {
      final pts = [for (var i = 0; i <= 100; i++) LatLng(13.0 + i * 0.0001, 100.0)];
      final s = simplifyRoute(pts);
      expect(s.first, pts.first);
      expect(s.last, pts.last);
      expect(s.length, 2);
    });

    test('caps at maxPoints for a noisy zig-zag line', () {
      final pts = [
        for (var i = 0; i < 3000; i++) LatLng(13.0 + i * 0.0001, 100.0 + (i.isEven ? 0.0006 : 0)),
      ];
      final s = simplifyRoute(pts, maxPoints: 500);
      expect(s.length, lessThanOrEqualTo(500));
      expect(s.first, pts.first);
      expect(s.last, pts.last);
    });

    test('short input is returned unchanged', () {
      expect(simplifyRoute(const [LatLng(1, 1), LatLng(2, 2)]).length, 2);
    });
  });
}
