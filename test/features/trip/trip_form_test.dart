import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/domain/trip_form.dart';
import 'package:latlong2/latlong.dart';

const _siam = Place(point: LatLng(13.7455, 100.5345), label: 'สยาม');
const _rangsit = Place(point: LatLng(13.9, 100.6), label: 'รังสิต');
final _now = DateTime(2026, 9, 25, 18, 0);

void main() {
  group('validatePlaces', () {
    test('requires both places', () {
      expect(TripFormValidator.validatePlaces(null, _rangsit), TripFormIssue.originMissing);
      expect(TripFormValidator.validatePlaces(_siam, null), TripFormIssue.destMissing);
    });

    test('rejects places closer than 200 m, accepts >= 200 m', () {
      const near = Place(point: LatLng(13.74565, 100.5345), label: 'ใกล้');
      expect(TripFormValidator.validatePlaces(_siam, near), TripFormIssue.tooClose);
      const edge = Place(point: LatLng(13.7455 + 0.0019, 100.5345), label: 'ห่าง ~211 ม.');
      expect(TripFormValidator.validatePlaces(_siam, edge), isNull);
      expect(TripFormValidator.validatePlaces(_siam, _rangsit), isNull);
    });
  });

  group('validateOptions', () {
    test('mode is required (exactly one)', () {
      expect(TripFormValidator.validateOptions(mode: null, departAt: null, now: _now),
          TripFormIssue.modeMissing);
      expect(TripFormValidator.validateOptions(mode: TravelMode.walk, departAt: null, now: _now), isNull);
    });

    test('past departure rejected beyond the 5 minute grace', () {
      expect(
        TripFormValidator.validateOptions(
          mode: TravelMode.car,
          role: TripRole.rider,
          departAt: _now.subtract(const Duration(minutes: 30)),
          now: _now,
        ),
        TripFormIssue.departInPast,
      );
      expect(
        TripFormValidator.validateOptions(
          mode: TravelMode.car,
          role: TripRole.rider,
          departAt: _now.subtract(const Duration(minutes: 3)),
          now: _now,
        ),
        isNull,
      );
      expect(
        TripFormValidator.validateOptions(
          mode: TravelMode.car,
          role: TripRole.rider,
          departAt: _now.add(const Duration(hours: 5)),
          now: _now,
        ),
        isNull,
      );
    });
  });

  test('formatDeparture: today, tomorrow (crossing midnight) and later dates', () {
    expect(formatDeparture(DateTime(2026, 9, 25, 18, 5), _now), 'วันนี้ 18:05');
    expect(formatDeparture(DateTime(2026, 9, 26, 0, 30), _now), 'พรุ่งนี้ 00:30');
    expect(formatDeparture(DateTime(2026, 9, 28, 8, 0), _now), '28 ก.ย. 08:00');
  });

  test('formatRouteSummary', () {
    expect(formatRouteSummary(8400, 1500), 'ประมาณ 8.4 กม. ราว 25 นาที');
    expect(formatRouteSummary(450, 20), 'ประมาณ 450 ม. ราว 1 นาที');
  });

  test('Trip.fromJson parses PostgREST rows (GeoJSON) and rejects bad ones', () {
    final row = {
      'id': 't1',
      'mode': 'walk',
      'status': 'scheduled',
      'origin': {
        'type': 'Point',
        'coordinates': [100.5345, 13.7455],
      },
      'dest': {
        'type': 'Point',
        'coordinates': [100.6, 13.9],
      },
      'origin_label': 'สยาม',
      'dest_label': 'รังสิต',
      'route': {
        'type': 'LineString',
        'coordinates': [
          [100.5345, 13.7455],
          [100.6, 13.9],
        ],
      },
      'route_distance_m': 20000,
      'route_duration_s': 1800,
      'depart_at': '2026-09-25T13:00:00Z',
    };
    final t = Trip.fromJson(row)!;
    expect(t.origin, const LatLng(13.7455, 100.5345));
    expect(t.route.length, 2);
    expect(t.status.isActive, isTrue);
    expect(Trip.fromJson({...row, 'origin': null}), isNull);
    expect(Trip.fromJson({...row, 'mode': 'boat'}), isNull);
  });
}
