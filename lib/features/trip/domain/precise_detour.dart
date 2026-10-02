import 'package:latlong2/latlong.dart';

import '../../../core/geo/geo.dart' show haversineM;
import '../../geo/domain/geo_services.dart';
import 'travel_mode.dart';

/// US-50 (round 7 Stage D): client-side PRECISE (OSRM road-distance) detour
/// calculation, computed only at `request_match` time for a specific
/// Driver/Rider pair — see docs/flow-us50-detour.md step 3 and
/// docs/design-roles.md §16. Kept free of Riverpod/Supabase types so it is
/// unit-testable with a fake [RoutingService].
///
/// ## Which candidates need this
/// Only a car Rider requesting a car Driver candidate can compute this at
/// all: the OSRM legs need the Driver's origin/destination, which the Rider
/// only ever sees as the SAME blurred points already shown on the candidate
/// card (`MatchCandidate.approxOrigin`/`approxDest` — server never reveals a
/// Driver's exact coordinates pre-match, same as post-match `get_trip_card`).
/// The reverse direction (a Driver requesting a Rider candidate) cannot
/// compute this client-side at all: `find_matches` NEVER returns a Rider
/// candidate's destination (`o.mode='car' and o.role='rider' -> dest null`,
/// 0016 PART 2 comment), so the Driver's app has no `riderDest` to route
/// through before a match exists. That direction always omits
/// `p_client_detour_m`; if the detour path was the only one that would have
/// qualified, the server answers `GWM_NOT_ELIGIBLE` (see design-roles.md
/// §16.7, an open/unresolved gap, not a bug in this file).
///
/// ## Which path applies (mirrors `_car_detour_path_used`, migration 0016)
/// `needsDetourPath` mirrors the server's
/// `ST_Distance(driverDest, riderDest) > _car_dropoff_limit(driverMaxDropoff)`
/// check using the SAME effective limit the server already computed for us
/// (`MatchCandidate.maxDropoffM` IS `_car_dropoff_limit(...)`, no need to
/// duplicate that formula/config value client-side) and a straight-line
/// distance over the same (blurred) points the deck already shows. This is
/// approximate (blur can shift the straight-line distance by up to the blur
/// cell radius) but only decides whether to SPEND 3 extra OSRM calls before
/// sending the request:
///   - false positive ("needs it" when the radial path alone would have
///     passed): harmless — `request_match` ignores `p_client_detour_m`
///     whenever the radial path already qualifies (0016's `if v_needs_detour`
///     gate), so 3 wasted OSRM calls are the only cost.
///   - false negative (radial looks like it passes when it would not have):
///     `p_client_detour_m` is omitted and the server answers
///     `GWM_NOT_ELIGIBLE` — same user-visible outcome as "not a candidate",
///     recoverable by retrying (blur is small relative to typical margins).
bool needsDetourPath({
  required LatLng driverDest,
  required LatLng riderDest,
  required int? effectiveDropoffLimitM,
}) {
  if (effectiveDropoffLimitM == null) return false;
  return haversineM(driverDest, riderDest) > effectiveDropoffLimitM;
}

/// The exact server formula this function's OUTPUT must always exceed (proof
/// in migration 0016, `_car_detour_floor_m`, reproduced here so a future
/// change to that SQL function is caught by `precise_detour_test.dart`):
///
///   floor_m = |driverOrigin - riderDest| + |riderDest - driverDest|
///             - route(driverOrigin, driverDest)
///
/// (triangle inequality applied to two independent legs, `route(A,Z)` being
/// the one leg the server knows EXACTLY from `trips.route`.)
///
/// This function computes the CLAIMED value the same way, except every leg
/// is a REAL OSRM road route instead of a straight line:
///
///   delta_m = route(driverOrigin, riderDest) + route(riderDest, driverDest)
///             - route(driverOrigin, driverDest)
///
/// Since `route(X,Y) >= |XY|` always (the defining property the server's own
/// comment relies on), an honestly-computed `delta_m` is provably >= the
/// straight-line floor built from the SAME two legs — the only source of
/// possible false rejection is the coordinate BLUR discussed above, not the
/// formula itself.
///
/// Returns null (fail-closed) when ANY of the 3 OSRM calls fails or times
/// out — the caller must NOT fall back to a guessed number (see
/// `FailureCode.detourCalcFailed`); a failed calculation is a "try again"
/// state, never a silently-omitted-but-still-attempted request.
Future<double?> computePreciseDetourM({
  required RoutingService routing,
  required TravelMode mode,
  required LatLng driverOrigin,
  required LatLng driverDest,
  required LatLng riderDest,
}) async {
  try {
    final direct = await routing.route(mode: mode, from: driverOrigin, to: driverDest);
    final toRider = await routing.route(mode: mode, from: driverOrigin, to: riderDest);
    final fromRider = await routing.route(mode: mode, from: riderDest, to: driverDest);
    final delta = (toRider.distanceM + fromRider.distanceM - direct.distanceM).toDouble();
    // Never claim a negative detour (a real route can only add distance);
    // clamp defensively even though a genuine OSRM answer should not go below 0.
    return delta < 0 ? 0 : delta;
  } catch (_) {
    return null;
  }
}
