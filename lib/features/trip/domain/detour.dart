/// US-50 (round 7 Stage C): driver-only "route detour tolerance" — a SECOND,
/// independent matching path alongside `trips.max_dropoff_m` (round 5). Both
/// mechanisms measure different things and are OR'd together server-side
/// (`_car_rule_eval`, migration 0014): a rider destination that is too far
/// under `max_dropoff_m` can still match if the extra ROUND-TRIP road
/// distance to detour there stays within this value. See
/// docs/design-roles.md #15.5.
///
/// Bounds mirror `trips_detour_tolerance_guard` (0014): 200..2000 m, step 100,
/// default 500. The 2000 ceiling is also a server config (`match.detour_tolerance_max_m`)
/// so this is a client-side mirror only, never the authority.
const int detourMinM = 200;
const int detourMaxM = 2000;
const int detourStepM = 100;
const int detourDefaultM = 500;
const List<int> detourChipsM = [200, 500, 1000, 2000];

/// Snaps to the 0014 rule: 200..2000 in steps of 100.
int clampDetour(int m) => ((m.clamp(detourMinM, detourMaxM)) / detourStepM).round() * detourStepM;
