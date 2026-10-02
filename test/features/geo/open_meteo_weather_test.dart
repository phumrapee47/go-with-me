import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/config/service_config.dart';
import 'package:gowithme/features/geo/data/open_meteo_weather.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

const _cfg = ServiceConfig(userAgent: 'GoWithMe/test (contact: t@example.com)');
const _point = LatLng(13.7563, 100.5018);

http.Response _weatherCode(int code) =>
    http.Response(jsonEncode({'current': {'weather_code': code}}), 200);

void main() {
  group('isRainWeatherCode', () {
    test('clear/cloudy codes are not rain', () {
      expect(isRainWeatherCode(0), isFalse); // clear sky
      expect(isRainWeatherCode(2), isFalse); // partly cloudy
      expect(isRainWeatherCode(45), isFalse); // fog
    });

    test('drizzle/rain/freezing-rain codes (51-67) are rain', () {
      expect(isRainWeatherCode(51), isTrue);
      expect(isRainWeatherCode(61), isTrue);
      expect(isRainWeatherCode(67), isTrue);
    });

    test('rain shower codes (80-82) are rain', () {
      expect(isRainWeatherCode(80), isTrue);
      expect(isRainWeatherCode(82), isTrue);
    });

    test('thunderstorm codes (95-99) are rain', () {
      expect(isRainWeatherCode(95), isTrue);
      expect(isRainWeatherCode(99), isTrue);
    });

    test('null code (missing/unparseable) is not rain', () {
      expect(isRainWeatherCode(null), isFalse);
    });
  });

  group('OpenMeteoWeather', () {
    test('API reports rain (code 61) -> isRainingAt is true', () async {
      final w = OpenMeteoWeather(MockClient((r) async => _weatherCode(61)), _cfg);
      expect(await w.isRainingAt(_point), isTrue);
    });

    test('API reports clear (code 0) -> isRainingAt is false', () async {
      final w = OpenMeteoWeather(MockClient((r) async => _weatherCode(0)), _cfg);
      expect(await w.isRainingAt(_point), isFalse);
    });

    test('sends latitude/longitude in the request', () async {
      late Uri seen;
      final w = OpenMeteoWeather(
        MockClient((r) async {
          seen = r.url;
          return _weatherCode(61);
        }),
        _cfg,
      );
      await w.isRainingAt(_point);
      expect(seen.queryParameters['latitude'], '13.7563');
      expect(seen.queryParameters['longitude'], '100.5018');
    });

    test('fail-open: non-200 response is treated as not raining', () async {
      final w = OpenMeteoWeather(MockClient((r) async => http.Response('', 503)), _cfg);
      expect(await w.isRainingAt(_point), isFalse);
    });

    test('fail-open: malformed body is treated as not raining', () async {
      final w = OpenMeteoWeather(MockClient((r) async => http.Response('not json', 200)), _cfg);
      expect(await w.isRainingAt(_point), isFalse);
    });

    test('fail-open: request throws is treated as not raining', () async {
      final w = OpenMeteoWeather(MockClient((r) async => throw http.ClientException('down')), _cfg);
      expect(await w.isRainingAt(_point), isFalse);
    });
  });
}
