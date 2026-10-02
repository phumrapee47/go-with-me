import 'package:latlong2/latlong.dart';

import '../../trip/domain/travel_mode.dart';

class PlaceSuggestion {
  const PlaceSuggestion({required this.label, required this.point});
  final String label;
  final LatLng point;
}

class RouteResult {
  const RouteResult({required this.geometry, required this.distanceM, required this.durationS});
  final List<LatLng> geometry;
  final int distanceM;
  final int durationS;
}

/// Swappable geocoder (design-api section 9.4). Methods throw AppFailure.
abstract interface class GeocodingService {
  /// Empty list = no result (a normal outcome, not an error).
  Future<List<PlaceSuggestion>> search(String query);

  /// Throws AppFailure when no label can be found; callers fall back to
  /// coordinates so saving a trip is never blocked.
  Future<String> reverse(LatLng p);
}

abstract interface class RoutingService {
  Future<RouteResult> route({required TravelMode mode, required LatLng from, required LatLng to});
}

/// Result of a road-snap lookup (US-43, R7.11).
class SnapResult {
  const SnapResult({required this.point, required this.deviationM});
  final LatLng point;
  final double deviationM;
}

/// Swappable OSRM `nearest` client (US-43). Snaps a raw point to the closest
/// routable road segment. Callers must fail-open on any [AppFailure]: never
/// block proposing a pickup point on this service's availability.
abstract interface class RoadSnapService {
  Future<SnapResult> nearest({required TravelMode mode, required LatLng point});
}

/// Purely decorative (mascot rain-mode trigger): never throws, always
/// resolves — a failed/unreachable host just means "not raining" (fail-open).
abstract interface class WeatherService {
  Future<bool> isRainingAt(LatLng point);
}
