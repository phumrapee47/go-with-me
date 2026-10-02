/// US-47 (round 7 Stage C): shared impact card CO2 estimate. Pure client-side calculation (no
/// schema — see docs/design-roles.md #15.2): `trips.route_distance_m` (already readable from the
/// caller's own trip) x ~120 g/km, a made-up-for-inspiration constant, NOT a scientific/legal claim
/// (Q9: PM confirmed the "(โดยประมาณ)" label + a one-line disclaimer footnote is enough).
const double kgCo2PerKm = 0.120;

/// Returns null when [distanceM] is 0 or negative (AC: hide the number rather than show a
/// nonsensical "0 kg CO2").
double? co2KgFor(int distanceM) => distanceM <= 0 ? null : (distanceM / 1000.0) * kgCo2PerKm;

/// "~1.2 kg" / "~0.3 kg" (one decimal, always with the tilde per the AC's "~X kg").
String formatCo2Kg(double kg) => '~${kg.toStringAsFixed(1)} kg';
