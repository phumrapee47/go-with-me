import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/service_config.dart';
import '../data/geolocator_location_service.dart';
import '../data/nominatim_geocoding.dart';
import '../data/open_meteo_weather.dart';
import '../data/osrm_road_snap.dart';
import '../data/osrm_routing.dart';
import '../domain/geo_services.dart';
import '../domain/location_service.dart';

final serviceConfigProvider = Provider<ServiceConfig>((ref) => ServiceConfig.fromEnvironment());

final httpClientProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

/// One instance for the whole app so the 1 req/s throttle and cache are shared.
final geocodingServiceProvider = Provider<GeocodingService>(
  (ref) => NominatimGeocoding(ref.watch(httpClientProvider), ref.watch(serviceConfigProvider)),
);

final routingServiceProvider = Provider<RoutingService>(
  (ref) => OsrmRouting(ref.watch(httpClientProvider), ref.watch(serviceConfigProvider)),
);

/// US-43 (R7.11): OSRM `nearest`, called once per "เสนอจุดนี้" tap.
final roadSnapServiceProvider = Provider<RoadSnapService>(
  (ref) => OsrmRoadSnap(ref.watch(httpClientProvider), ref.watch(serviceConfigProvider)),
);

final locationServiceProvider = Provider<LocationService>((ref) => const GeolocatorLocationService());

final weatherServiceProvider = Provider<WeatherService>(
  (ref) => OpenMeteoWeather(ref.watch(httpClientProvider), ref.watch(serviceConfigProvider)),
);

/// Tests turn this off so no tile requests are attempted.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

/// Most recent position seen while a trip is active (also used by SOS as the
/// instant fallback before a fresh GPS read completes).
final lastFixProvider = StateProvider<LocationFix?>((ref) => null);
