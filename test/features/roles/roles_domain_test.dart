import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/error/error_mapper.dart';
import 'package:gowithme/core/error/failure_messages.dart';
import 'package:gowithme/core/geo/geo.dart';
import 'package:gowithme/core/notify/local_notifier.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/matching/presentation/car_match_widgets.dart';
import 'package:gowithme/features/matching/presentation/matching_providers.dart';
import 'package:gowithme/features/safety/domain/safety_models.dart';
import 'package:gowithme/features/sharing/domain/share_companion.dart';
import 'package:gowithme/features/sharing/domain/trip_share.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/domain/trip_form.dart';
import 'package:gowithme/features/vehicle/domain/vehicle.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../support/fake_repos.dart';

void main() {
  group('TripRole and compatibility (client mirror of the server rule)', () {
    test('parses only the two roles; car seats are fixed at 1', () {
      expect(TripRole.fromDb('driver'), TripRole.driver);
      expect(TripRole.fromDb('rider'), TripRole.rider);
      expect(TripRole.fromDb('passenger'), isNull);
      expect(TripRole.fromDb(null), isNull);
      expect(TripRole.driver.opposite, TripRole.rider);
      expect(carSeats, 1);
    });

    test('car pairs need opposite roles; car never meets other modes; peers stay peers', () {
      bool ok(TravelMode a, TripRole? ra, TravelMode b, TripRole? rb) =>
          tripsCompatible(myMode: a, myRole: ra, otherMode: b, otherRole: rb);
      const car = TravelMode.car;
      expect(ok(car, TripRole.driver, car, TripRole.rider), isTrue);
      expect(ok(car, TripRole.rider, car, TripRole.driver), isTrue);
      expect(ok(car, TripRole.driver, car, TripRole.driver), isFalse);
      expect(ok(car, TripRole.rider, car, TripRole.rider), isFalse);
      expect(ok(car, TripRole.driver, car, null), isFalse, reason: 'legacy car trip has no role');
      expect(ok(car, TripRole.driver, TravelMode.walk, null), isFalse);
      expect(ok(TravelMode.taxi, null, car, TripRole.driver), isFalse);
      // Walk / transit / taxi: unchanged peer behaviour.
      expect(ok(TravelMode.walk, null, TravelMode.transit, null), isTrue);
      expect(ok(TravelMode.taxi, null, TravelMode.taxi, null), isTrue);
    });

    test('Trip.fromJson keeps the role only for car and tolerates unknown values', () {
      Map<String, dynamic> row(String mode, Object? role) => {
            'id': 't1',
            'mode': mode,
            'status': 'scheduled',
            'origin': {'type': 'Point', 'coordinates': [100.5, 13.7]},
            'dest': {'type': 'Point', 'coordinates': [100.6, 13.8]},
            'depart_at': '2026-09-25T13:00:00Z',
            'role': role,
          };
      expect(Trip.fromJson(row('car', 'driver'))!.role, TripRole.driver);
      expect(Trip.fromJson(row('walk', 'driver'))!.role, isNull);
      final legacy = Trip.fromJson(row('car', null))!;
      expect(legacy.isLegacyCarWithoutRole, isTrue);
      expect(Trip.fromJson(row('car', 'weird'))!.role, isNull);
      expect(legacy.copyWith(status: TripStatus.inProgress).role, isNull);
      expect(sampleTrip(mode: TravelMode.car, role: TripRole.rider).copyWith(status: TripStatus.inProgress).role,
          TripRole.rider);
    });

    test('form: car needs a role, a Driver also needs a vehicle; other modes ignore both', () {
      final now = DateTime(2026, 9, 25, 18);
      TripFormIssue? v(TravelMode m, {TripRole? role, bool vehicle = true}) =>
          TripFormValidator.validateOptions(mode: m, departAt: null, now: now, role: role, hasVehicle: vehicle);
      expect(v(TravelMode.car), TripFormIssue.roleMissing);
      expect(v(TravelMode.car, role: TripRole.driver, vehicle: false), TripFormIssue.vehicleMissing);
      expect(v(TravelMode.car, role: TripRole.driver), isNull);
      expect(v(TravelMode.car, role: TripRole.rider, vehicle: false), isNull);
      expect(v(TravelMode.walk, vehicle: false), isNull);
    });
  });

  group('vehicle', () {
    test('validation: required after trim, server length limits, no control characters', () {
      Map<VehicleField, VehicleIssue> check(String p, String m, String c) =>
          VehicleValidator.validate(VehicleInput(plate: p, model: m, color: c));
      expect(check('1กก 1234', 'Toyota Yaris', 'ขาว'), isEmpty);
      expect(check('  ', '', ' '), {
        VehicleField.plate: VehicleIssue.required,
        VehicleField.model: VehicleIssue.required,
        VehicleField.color: VehicleIssue.required,
      });
      expect(check('ก' * 26, 'm', 'c')[VehicleField.plate], VehicleIssue.tooLong);
      expect(check('ก' * 25, 'm', 'c'), isEmpty);
      expect(check('p', 'm' * 61, 'c')[VehicleField.model], VehicleIssue.tooLong);
      expect(check('p', 'm', 'c' * 31)[VehicleField.color], VehicleIssue.tooLong);
      expect(check('p\u0007', 'm', 'c')[VehicleField.plate], VehicleIssue.tooLong);
      expect(VehicleValidator.normalise('  1กก   1234 '), '1กก 1234');
    });

    test('consent defaults to OFF and comes only from share_consent_at', () {
      final v = Vehicle.fromJson({'plate': 'ก 1', 'model': 'm', 'color': 'c'})!;
      expect(v.shareConsent, isFalse);
      expect(Vehicle.fromJson({'plate': 'ก 1', 'model': 'm', 'color': 'c', 'share_consent_at': '2026-01-01T00:00:00Z'})!
          .shareConsent, isTrue);
      expect(Vehicle.fromJson(null), isNull);
      expect(Vehicle.fromJson({'plate': 'x'}), isNull);
      expect(v.copyWith(shareConsent: true).plate, 'ก 1');
    });

    test('get_match_vehicle row maps share_allowed; missing fields are dropped', () {
      final v = VehicleView.fromJson({'plate': 'ก 1', 'model': 'm', 'color': 'c', 'verified': false, 'share_allowed': true})!;
      expect(v.shareAllowed, isTrue);
      expect(VehicleView.fromJson({'plate': 'ก 1', 'model': 'm', 'color': 'c'})!.shareAllowed, isFalse);
      expect(VehicleView.fromJson({'plate': 'ก 1'}), isNull);
    });

    test('returnTo accepts in-app paths only', () {
      expect(safeReturnTo('/trip/new/options'), '/trip/new/options');
      expect(safeReturnTo(null), isNull);
      expect(safeReturnTo(''), isNull);
      expect(safeReturnTo('//evil.example'), isNull);
      expect(safeReturnTo('https://evil.example'), isNull);
      expect(safeReturnTo('trip/new'), isNull);
      expect(safeReturnTo('/a\\b'), isNull);
    });
  });

  group('match models', () {
    test('candidate: role parsed for car only; no vehicle fields exist on the type', () {
      Map<String, dynamic> row(String mode, Object? role) => {
            'trip_id': 'c1',
            'display_name': 'นุ่น',
            'badges': const [],
            'mode': mode,
            'depart_at': '2026-09-25T13:00:00Z',
            'time_diff_min': 3,
            'overlap_pct': 80,
            'approx_distance_m': 500,
            'score': 90,
            'approx_origin_lat': 13.7,
            'approx_origin_lng': 100.5,
            'approx_dest_lat': 13.8,
            'approx_dest_lng': 100.6,
            'role': role,
          };
      expect(MatchCandidate.fromJson(row('car', 'driver'))!.role, TripRole.driver);
      expect(MatchCandidate.fromJson(row('transit', 'driver'))!.role, isNull);
      expect(MatchCandidate.fromJson(row('car', null))!.role, isNull);
    });

    test('summary getters: roles, boarded, ended vs auto-closed', () {
      final m = sampleMatch(status: MatchStatus.accepted, myRole: TripRole.rider);
      expect(m.isCar, isTrue);
      expect(m.iAmRider, isTrue);
      expect(m.iAmDriver, isFalse);
      expect(m.partnerRole, TripRole.driver);
      expect(m.boarded, isFalse);
      final boarded = m.copyWith(boardedAt: DateTime(2026, 9, 25, 18, 42));
      expect(boarded.boarded, isTrue);
      expect(boarded.myRole, TripRole.rider, reason: 'copyWith keeps roles');
      expect(sampleMatch(status: MatchStatus.cancelled, myRole: TripRole.driver).isEnded, isTrue);
      expect(sampleMatch(status: MatchStatus.cancelled, myRole: TripRole.driver, autoClosed: true).isEnded, isFalse,
          reason: 'auto-closed is neutral "closed", not an ended match');
      expect(sampleMatch().isCar, isFalse, reason: 'peer matches have no role');
    });

    test('defensive candidate filter drops same-role / non-car rows for a car trip', () {
      final trip = sampleTrip(mode: TravelMode.car, role: TripRole.driver);
      final list = [
        sampleCandidate(tripId: 'ok', mode: TravelMode.car, role: TripRole.rider),
        sampleCandidate(tripId: 'same', mode: TravelMode.car, role: TripRole.driver),
        sampleCandidate(tripId: 'norole', mode: TravelMode.car),
        sampleCandidate(tripId: 'walk', mode: TravelMode.walk),
      ];
      expect([for (final c in filterCandidates(trip, list)) c.tripId], ['ok']);
      final peer = sampleTrip();
      expect([for (final c in filterCandidates(peer, list)) c.tripId], ['walk'],
          reason: 'peer trips never see car trips');
    });

    test('pickup is editable only while accepted, not boarded and before either trip started', () {
      final m = sampleMatch(status: MatchStatus.accepted, myRole: TripRole.driver, partnerTripStatus: TripStatus.scheduled);
      expect(pickupEditable(m, myTripStatus: TripStatus.scheduled), isTrue);
      expect(pickupEditable(m, myTripStatus: TripStatus.inProgress), isFalse);
      expect(pickupEditable(m.copyWith(partnerTripStatus: TripStatus.inProgress)), isFalse);
      expect(pickupEditable(m.copyWith(boardedAt: DateTime.now())), isFalse);
      expect(pickupEditable(m.copyWith(status: MatchStatus.cancelled)), isFalse);
    });
  });

  group('error mapping (Thai, never the server text)', () {
    final generic = failureMessage(const AppFailure(FailureCode.unknown));
    const codes = [
      'GWM_ROLE_REQUIRED',
      'GWM_ROLE_NOT_ALLOWED',
      'GWM_ROLE_IMMUTABLE',
      'GWM_VEHICLE_REQUIRED',
      'GWM_VEHICLE_INVALID',
      'GWM_VEHICLE_IN_USE',
      'GWM_NOT_RIDER',
      'GWM_TRIP_NOT_STARTED',
      'GWM_ALREADY_BOARDED',
      'GWM_NO_SHOW_NOT_ALLOWED',
      'GWM_PICKUP_DRIVER_FIRST',
    ];
    for (final code in codes) {
      test(code, () {
        final f = mapError(PostgrestException(message: code, code: 'P0001'));
        expect(f.code, code);
        final text = failureMessage(f);
        expect(text, isNot(generic));
        expect(text, isNot(contains('GWM_')));
        for (final banned in ['ค่าโดยสาร', 'ค่าบริการ', 'รับจ้าง', 'ราคา']) {
          expect(text, isNot(contains(banned)));
        }
      });
    }

    test('car match limit reads as "you already have a partner"', () {
      expect(failureMessage(const AppFailure('GWM_MATCH_LIMIT')), 'คุณมีคู่ร่วมทางแล้ว');
    });
  });

  group('share / SOS text: plate only, and only when allowed', () {
    final trip = sampleTrip(mode: TravelMode.car, role: TripRole.rider);
    final now = DateTime(2026, 9, 25, 18);

    String text(ShareCompanion c) => buildTripShareText(name: 'มิ้นท์', trip: trip, now: now, companion: c);

    test('Rider text: driver name always; plate only with the Driver consent', () {
      final allowed = text(const ShareCompanion.rider(partnerName: 'สมชาย', plate: '1กก 1234', plateAllowed: true));
      expect(allowed, contains('คนขับ: สมชาย'));
      expect(allowed, contains('ทะเบียนรถ: 1กก 1234'));
      final denied = text(const ShareCompanion.rider(partnerName: 'สมชาย', plate: '1กก 1234'));
      expect(denied, contains('คนขับ: สมชาย'));
      expect(denied, isNot(contains('1กก 1234')), reason: 'plate without consent must never be in the text');
      expect(denied, isNot(contains('ทะเบียน')));
    });

    test('a plate is dropped even if a caller passes one while consent is unknown or off', () {
      const unknown = ShareCompanion.rider(partnerName: 'สมชาย', plate: '1กก 1234', statusKnown: false);
      expect(companionLines(unknown).join(' '), isNot(contains('1กก 1234')));
    });

    test('no match: nothing added; Driver text carries own plate + rider name, never model/colour', () {
      expect(text(const ShareCompanion.none()), isNot(contains('คนขับ')));
      final d = text(const ShareCompanion.driver(partnerName: 'ใจดี', plate: 'ขข 5678'));
      expect(d, contains('ทะเบียนรถ: ขข 5678'));
      expect(d, contains('คนนั่ง: ใจดี'));
      expect(d, isNot(contains('Toyota')));
    });

    test('SOS text appends the companion lines without changing the base sentence', () {
      final base = buildSosMessage(name: 'มิ้นท์', at: now);
      final withLines = buildSosMessage(
        name: 'มิ้นท์',
        at: now,
        location: const LatLng(13.7, 100.5),
        extraLines: companionLines(const ShareCompanion.rider(partnerName: 'สมชาย', plate: 'ก 1', plateAllowed: true)),
      );
      expect(base, isNot(contains('\n')));
      expect(withLines, contains('คนขับ: สมชาย'));
      expect(withLines, contains('ทะเบียนรถ: ก 1'));
      expect(withLines, contains('openstreetmap.org'));
    });

    test('preview lines: with / without plate, driver, fallback when the status is unknown', () {
      expect(sharePreviewLine(const ShareCompanion.none()), isNull);
      expect(sharePreviewLine(const ShareCompanion.rider(partnerName: 'ส', plate: 'ก', plateAllowed: true)),
          'ข้อความนี้จะมี: ชื่อคนขับ และทะเบียนรถ');
      expect(sharePreviewLine(const ShareCompanion.rider(partnerName: 'ส')),
          contains('ไม่มีทะเบียนรถ เพราะคนขับไม่ได้อนุญาต'));
      expect(sharePreviewLine(const ShareCompanion.driver(partnerName: 'ส', plate: 'ก')), contains('ทะเบียนรถของคุณ'));
      expect(sosPreviewLine(const ShareCompanion.rider(partnerName: 'ส', statusKnown: false)),
          'ข้อความ SOS จะมีชื่อคนขับ');
      expect(sosPreviewLine(const ShareCompanion.rider(partnerName: 'ส', plate: 'ก', plateAllowed: true)),
          'ข้อความ SOS จะมีชื่อและทะเบียนรถของคนขับ');
    });

    test('sameTextAs compares what would actually be sent', () {
      const a = ShareCompanion.rider(partnerName: 'ส', plate: 'ก', plateAllowed: true);
      const b = ShareCompanion.rider(partnerName: 'ส');
      expect(a.sameTextAs(a), isTrue);
      expect(a.sameTextAs(b), isFalse);
    });
  });

  group('pickup geometry and notices', () {
    // A straight north-south route along lng 100.5.
    const route = [LatLng(13.70, 100.5), LatLng(13.80, 100.5)];

    test('distanceToRouteM: on the line ~0, 1 km east ~1 km, past the end measured to the end point', () {
      expect(distanceToRouteM(const LatLng(13.75, 100.5), route), lessThan(1));
      expect(distanceToRouteM(const LatLng(13.75, 100.509), route), inInclusiveRange(950, 1050));
      expect(distanceToRouteM(const LatLng(13.81, 100.5), route), inInclusiveRange(1050, 1150));
      expect(distanceToRouteM(const LatLng(13.75, 100.5), const []), double.infinity);
    });

    test('a local notice can carry no plate, name or place (fixed neutral copy)', () {
      const n = LocalNotice(LocalNoticeKind.matchEndedDuringTrip);
      expect(n.title, isNotEmpty);
      expect(n.body, isNotEmpty);
      for (final leak in ['ทะเบียน', 'ชื่อ', 'ตำแหน่ง']) {
        expect(n.body, isNot(contains(leak)));
      }
    });
  });
}
