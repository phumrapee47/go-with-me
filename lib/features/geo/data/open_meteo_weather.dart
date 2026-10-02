import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/config/service_config.dart';
import '../domain/geo_services.dart';

/// Open-Meteo current weather (free, no API key). Fail-open: any error just
/// means "not raining" — this only drives a cosmetic mascot state, never a
/// real decision the user relies on.
class OpenMeteoWeather implements WeatherService {
  OpenMeteoWeather(this._http, this._cfg);

  final http.Client _http;
  final ServiceConfig _cfg;

  @override
  Future<bool> isRainingAt(LatLng point) async {
    final uri = Uri.parse(
      '${_cfg.weatherBaseUrl}/v1/forecast'
      '?latitude=${point.latitude}&longitude=${point.longitude}&current=weather_code',
    );
    try {
      final res = await _http.get(uri).timeout(_cfg.weatherTimeout);
      if (res.statusCode != 200) return false;
      final body = json.decode(res.body);
      if (body is! Map) return false;
      final current = body['current'];
      final code = current is Map ? current['weather_code'] : null;
      return isRainWeatherCode(code is num ? code.toInt() : null);
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    } on http.ClientException {
      return false;
    } on FormatException {
      return false;
    }
  }
}

/// WMO weather codes: 51-67 drizzle/rain/freezing rain, 80-82 rain showers,
/// 95-99 thunderstorm. Exposed for tests.
bool isRainWeatherCode(int? code) {
  if (code == null) return false;
  return (code >= 51 && code <= 67) || (code >= 80 && code <= 99);
}
