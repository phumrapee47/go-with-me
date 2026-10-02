/// External service endpoints and limits (T1.7 / design-api section 9.1).
/// Every value is swappable with --dart-define; nothing outside this file
/// hard-codes a host. Public OSM/OSRM/Nominatim servers have no SLA and
/// usage policies: swap to a self-hosted provider before real traffic.
class ServiceConfig {
  const ServiceConfig({
    this.nominatimBaseUrl = _nominatim,
    this.osrmFootBaseUrl = _osrmFoot,
    this.osrmCarBaseUrl = _osrmCar,
    this.tileUrlTemplate = _tiles,
    this.tileUrlTemplateDark = _tilesDark,
    this.userAgent = _userAgent,
    this.tileUserAgentPackage = 'com.gowithme.app',
    this.geoTimeout = const Duration(seconds: 6),
    this.routeTimeout = const Duration(seconds: 8),
    this.geoMinInterval = const Duration(milliseconds: 1100),
    this.pickupMaxDeviationM = _pickupMaxDeviationM,
    this.snapTimeout = const Duration(seconds: 2),
    this.snapMaxDeviationM = _snapMaxDeviationM,
    this.weatherBaseUrl = _weatherBaseUrl,
    this.weatherTimeout = const Duration(seconds: 5),
  });

  factory ServiceConfig.fromEnvironment() => const ServiceConfig();

  static const _nominatim =
      String.fromEnvironment('NOMINATIM_BASE_URL', defaultValue: 'https://nominatim.openstreetmap.org');
  static const _osrmFoot = String.fromEnvironment(
    'OSRM_BASE_URL_FOOT',
    defaultValue: 'https://routing.openstreetmap.de/routed-foot',
  );
  static const _osrmCar =
      String.fromEnvironment('OSRM_BASE_URL_CAR', defaultValue: 'https://router.project-osrm.org');
  static const _tiles =
      String.fromEnvironment('TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
  // US-46 (round 7): optional self-hosted/paid dark tile provider, swappable
  // the same way as `_tiles`. No default: free third-party dark-tile services
  // (e.g. CARTO's basemaps.cartocdn.com) have started requiring an API key,
  // so with no override the app instead renders the light OSM tiles through
  // a colour-invert filter (see app_map.dart) — zero external dependency,
  // never breaks from a third party's policy change. Set TILE_URL_DARK to
  // use a real dark tile server instead once one is available.
  static const _tilesDark = String.fromEnvironment('TILE_URL_DARK', defaultValue: '');
  // Mirrors app_config `match.pickup_max_deviation_m` (R3-2, warn only). The
  // server decides for Riders (boolean); the Driver's own app may also use it
  // to show the distance from the Driver's own route.
  static const _pickupMaxDeviationM = int.fromEnvironment('PICKUP_MAX_DEVIATION_M', defaultValue: 500);
  // US-43 (R7.11): OSRM `nearest` result is rejected (raw point kept) when the
  // snap moves the pin further than this from where the user actually dropped
  // it (e.g. snapped onto a bridge/highway across a river). Independent of
  // `pickupMaxDeviationM` above (that one warns about the Driver's own route).
  static const _snapMaxDeviationM = int.fromEnvironment('ROAD_SNAP_MAX_DEVIATION_M', defaultValue: 40);
  // Nominatim policy requires an identifying UA with contact info.
  static const _userAgent = String.fromEnvironment(
    'GEO_USER_AGENT',
    defaultValue: 'GoWithMe/0.1 (contact: set GEO_USER_AGENT)',
  );
  // Free, no API key required (mascot rain-mode trigger only — decorative,
  // never blocks anything if this host is unreachable).
  static const _weatherBaseUrl =
      String.fromEnvironment('WEATHER_BASE_URL', defaultValue: 'https://api.open-meteo.com');

  final String nominatimBaseUrl;

  /// Public demo OSRM is driving-only; walking needs its own host.
  final String osrmFootBaseUrl;
  final String osrmCarBaseUrl;
  final String tileUrlTemplate;

  /// US-46 (round 7): used instead of [tileUrlTemplate] when the effective app brightness is dark.
  final String tileUrlTemplateDark;
  final String userAgent;
  final String tileUserAgentPackage;
  /// Warning threshold in metres for pickup points off the Driver's route.
  final int pickupMaxDeviationM;
  final Duration geoTimeout;
  final Duration routeTimeout;

  /// Short timeout for the once-only OSRM `nearest` call (US-43/Q4): a slow
  /// answer must fall back to the raw point quickly, never block the user.
  final Duration snapTimeout;

  /// Max metres the snapped point may move from the raw drop before it is
  /// rejected (fail-open: keep the raw point instead).
  final int snapMaxDeviationM;

  /// Minimum spacing between Nominatim calls (policy: <= 1 req/s).
  final Duration geoMinInterval;

  final String weatherBaseUrl;
  final Duration weatherTimeout;
}
