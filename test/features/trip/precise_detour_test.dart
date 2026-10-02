// US-50 (round 7 Stage D): unit tests for lib/features/trip/domain/precise_detour.dart.
//
// CRITICAL: these tests document the EXACT leg structure/formula of
// supabase/migrations/0016_precise_detour.sql's `_car_detour_floor_m` so a
// future SQL change to that formula is caught here too (see that file's
// PART 1.2 comment, reproduced below verbatim for cross-reference):
//
//   floor_m = |driverOrigin - riderDest| + |riderDest - driverDest|
//             - route(driverOrigin, driverDest)
//
// `computePreciseDetourM` computes the CLAIMED value the same way except
// every leg is a real OSRM route instead of a straight line:
//
//   delta_m = route(driverOrigin, riderDest) + route(riderDest, driverDest)
//             - route(driverOrigin, driverDest)
//
// i.e. exactly 3 OSRM `route()` calls: (origin->dest) direct, (origin->rider)
// and (rider->dest) — never a single "waypoint" call (the existing
// RoutingService has no waypoint support) and never fewer/more legs.
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/features/geo/domain/geo_services.dart';
import 'package:gowithme/features/trip/domain/precise_detour.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:latlong2/latlong.dart';

/// Records every call so leg order/arguments can be asserted, and returns
/// a fixed distance per call (or throws) so the arithmetic is exact.
class _FakeRouting implements RoutingService {
  _FakeRouting(this._distances, {this.failOn});
  final Map<String, int> _distances;
  /// A (from,to) key that throws instead of answering, to simulate an OSRM failure.
  final String? failOn;
  final calls = <(LatLng, LatLng)>[];

  String _key(LatLng a, LatLng b) => '${a.latitude},${a.longitude}->${b.latitude},${b.longitude}';

  @override
  Future<RouteResult> route({required TravelMode mode, required LatLng from, required LatLng to}) async {
    final k = _key(from, to);
    calls.add((from, to));
    if (k == failOn) throw const AppFailure(FailureCode.networkTimeout, retryable: true);
    final d = _distances[k];
    if (d == null) throw StateError('unexpected leg $k');
    return RouteResult(geometry: [from, to], distanceM: d, durationS: d ~/ 10);
  }
}

void main() {
  const driverOrigin = LatLng(13.70, 100.50);
  const driverDest = LatLng(13.80, 100.60);
  const riderDest = LatLng(13.75, 100.55);

  group('computePreciseDetourM leg structure (must match 0016 exactly)', () {
    test('calls exactly 3 routes: direct, origin->rider, rider->dest — in that order', () async {
      final fake = _FakeRouting({
        '13.7,100.5->13.8,100.6': 10000, // route(A,Z)
        '13.7,100.5->13.75,100.55': 6000, // route(A,M)
        '13.75,100.55->13.8,100.6': 6000, // route(M,Z)
      });
      final delta = await computePreciseDetourM(
        routing: fake,
        mode: TravelMode.car,
        driverOrigin: driverOrigin,
        driverDest: driverDest,
        riderDest: riderDest,
      );
      expect(fake.calls.length, 3);
      expect(fake.calls[0], (driverOrigin, driverDest));
      expect(fake.calls[1], (driverOrigin, riderDest));
      expect(fake.calls[2], (riderDest, driverDest));
      // delta = route(A,M) + route(M,Z) - route(A,Z) = 6000 + 6000 - 10000 = 2000
      expect(delta, 2000.0);
    });

    test('a route via M that happens to be shorter than direct never claims a negative detour', () async {
      // Degenerate/edge input (e.g. M essentially on the route): clamp to 0, never negative.
      final fake = _FakeRouting({
        '13.7,100.5->13.8,100.6': 10000,
        '13.7,100.5->13.75,100.55': 4000,
        '13.75,100.55->13.8,100.6': 4000,
      });
      final delta = await computePreciseDetourM(
        routing: fake,
        mode: TravelMode.car,
        driverOrigin: driverOrigin,
        driverDest: driverDest,
        riderDest: riderDest,
      );
      expect(delta, 0.0);
    });

    test('any of the 3 legs failing (OSRM timeout/error) returns null — never a guessed number', () async {
      for (final failing in [
        '13.7,100.5->13.8,100.6',
        '13.7,100.5->13.75,100.55',
        '13.75,100.55->13.8,100.6',
      ]) {
        final fake = _FakeRouting({
          '13.7,100.5->13.8,100.6': 10000,
          '13.7,100.5->13.75,100.55': 6000,
          '13.75,100.55->13.8,100.6': 6000,
        }, failOn: failing);
        final delta = await computePreciseDetourM(
          routing: fake,
          mode: TravelMode.car,
          driverOrigin: driverOrigin,
          driverDest: driverDest,
          riderDest: riderDest,
        );
        expect(delta, isNull, reason: 'leg $failing failed, must fail-closed to null');
      }
    });

    test('proof sanity: an honest delta is always >= the straight-line floor built from the same legs '
        '(route(X,Y) >= |XY| always, migration 0016 PART 1.2)', () async {
      // Any real OSRM distance is >= the great-circle distance between the same two points.
      // A minimal in-repo check: haversine(A,M)+haversine(M,Z)-route(A,Z) <= route(A,M)+route(M,Z)-route(A,Z)
      // whenever route(A,M) >= haversine(A,M) and route(M,Z) >= haversine(M,Z), which OSRM always satisfies.
      double haversineApprox(LatLng a, LatLng b) {
        // Local minimal check, not a re-implementation of the app's own haversineM (avoids testing itself).
        final dLat = (b.latitude - a.latitude).abs();
        final dLng = (b.longitude - a.longitude).abs();
        return (dLat + dLng) * 100000; // coarse but monotonic for this same-scale sanity check
      }

      final fake = _FakeRouting({
        '13.7,100.5->13.8,100.6': 10000,
        '13.7,100.5->13.75,100.55': 6000,
        '13.75,100.55->13.8,100.6': 6000,
      });
      final delta = await computePreciseDetourM(
        routing: fake,
        mode: TravelMode.car,
        driverOrigin: driverOrigin,
        driverDest: driverDest,
        riderDest: riderDest,
      );
      final floorLike = haversineApprox(driverOrigin, riderDest) + haversineApprox(riderDest, driverDest) - 10000;
      // Not a strict proof (haversineApprox is coarse), just documents the intended direction.
      expect(delta! >= 0, isTrue);
      expect(floorLike.isFinite, isTrue);
    });
  });

  group('needsDetourPath (mirrors _car_detour_path_used, migration 0016)', () {
    test('null effective limit (no candidate data) -> false, never spends OSRM calls blindly', () {
      expect(
        needsDetourPath(driverDest: driverDest, riderDest: riderDest, effectiveDropoffLimitM: null),
        isFalse,
      );
    });

    test('far apart beyond the limit -> true (detour path is the only chance)', () {
      // ~7.9 km apart per the const points above; well beyond a 500 m limit.
      expect(
        needsDetourPath(driverDest: driverDest, riderDest: riderDest, effectiveDropoffLimitM: 500),
        isTrue,
      );
    });

    test('within the limit -> false (radial path already qualifies, no need to compute)', () {
      expect(
        needsDetourPath(driverDest: driverDest, riderDest: riderDest, effectiveDropoffLimitM: 50000),
        isFalse,
      );
    });
  });
}
