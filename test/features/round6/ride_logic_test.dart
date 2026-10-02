import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/geo/geo.dart';
import 'package:gowithme/core/l10n/strings_r6.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/trip/domain/ride_logic.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';

/// A point [metres] due north of [p] (good enough at these distances).
LatLng _north(LatLng p, double metres) => LatLng(p.latitude + metres / 111194.9, p.longitude);

void main() {
  const dest = LatLng(13.9, 100.6);
  final t0 = DateTime(2026, 1, 1, 18);

  group('geofence highlight (US-32): 150 m, presentation only', () {
    test('149 m highlights, 150 m and 151 m do not (boundary is exclusive)', () {
      // Sanity of the helper itself.
      expect(haversineM(_north(dest, 149), dest), closeTo(149, 1));
      for (final (m, expected) in [(149.0, true), (149.9, true), (150.0, false), (151.0, false), (400.0, false)]) {
        final g = NearGate();
        // haversine on a rounded latitude can differ by a millimetre: compare with the real distance
        final p = _north(dest, m);
        final d = haversineM(p, dest);
        expect(g.update(now: t0, me: p, target: dest), d < nearEnterM, reason: '$m m (measured $d)');
        if (m == 149.0 || m == 149.9) expect(expected, isTrue);
      }
      expect(nearEnterM, 150);
    });

    test('hysteresis: once near it stays near until 180 m AND 3 s have passed', () {
      final g = NearGate();
      expect(g.update(now: t0, me: _north(dest, 100), target: dest), isTrue);
      // GPS wobbles out to 170 m: still near (inside the 180 m exit ring)
      expect(g.update(now: t0.add(const Duration(seconds: 1)), me: _north(dest, 170), target: dest), isTrue);
      // beyond 180 m but only 2 s after entering: kept (no blinking)
      expect(g.update(now: t0.add(const Duration(seconds: 2)), me: _north(dest, 260), target: dest), isTrue);
      // beyond 180 m and >= 3 s: leaves
      expect(g.update(now: t0.add(const Duration(seconds: 4)), me: _north(dest, 260), target: dest), isFalse);
      // 160 m is NOT enough to come back in (needs < 150 m again)
      expect(g.update(now: t0.add(const Duration(seconds: 5)), me: _north(dest, 160), target: dest), isFalse);
      expect(g.update(now: t0.add(const Duration(seconds: 6)), me: _north(dest, 120), target: dest), isTrue);
    });

    test('no position / no target / bad accuracy: never highlights and never throws', () {
      final g = NearGate();
      expect(g.update(now: t0, me: null, target: dest), isFalse);
      expect(g.update(now: t0, me: _north(dest, 10), target: null), isFalse);
      expect(g.update(now: t0, me: _north(dest, 10), target: dest, accuracyM: 500), isFalse, reason: 'poor fix ignored');
      expect(g.update(now: t0, me: _north(dest, 10), target: dest, accuracyM: 15), isTrue);
      // the position disappears (permission revoked): the highlight is dropped at once
      expect(g.update(now: t0.add(const Duration(seconds: 1)), me: null, target: dest), isFalse);
    });
  });

  group('arrival wording (Q5 / P-4)', () {
    test('only an explicit "home" earns the home wording; unknown and not-home use the generic one', () {
      expect(arriveSliderLabel(HomeMatch.home), R6.sliderArriveHome);
      expect(arriveSliderLabel(HomeMatch.notHome), R6.sliderArriveDest);
      expect(arriveSliderLabel(HomeMatch.unknown), R6.sliderArriveDest);
      expect(arrivedMessage(HomeMatch.home), 'ถึงบ้านปลอดภัยแล้ว 🎉 ขอบคุณเพื่อนร่วมทาง');
      expect(arrivedMessage(HomeMatch.notHome), 'ถึงที่หมายปลอดภัยแล้ว 🎉 ขอบคุณเพื่อนร่วมทาง');
      expect(arrivedMessage(HomeMatch.unknown), 'ถึงที่หมายปลอดภัยแล้ว 🎉 ขอบคุณเพื่อนร่วมทาง');
    });

    test('screen-reader text carries the whole sentence without the emoji', () {
      for (final m in HomeMatch.values) {
        final spoken = arrivedMessageSemantics(m);
        expect(spoken.contains('🎉'), isFalse);
        expect(arrivedMessage(m).replaceAll(' 🎉', ''), spoken);
      }
      expect(R6.boardedSuccessSemantics.contains('🚗'), isFalse);
      expect(R6.boardedSuccess.replaceAll(' 🚗', ''), R6.boardedSuccessSemantics);
    });

    test('until presets exist (stage D) the default matcher answers "unknown"', () {
      const matcher = UnknownHomeDestinationMatcher();
      expect(matcher.match(sampleTrip()), HomeMatch.unknown);
    });
  });

  group('arrived-at-pickup cooldown (US-33)', () {
    test('once a minute: a second tap inside 60 s is refused, a failed send frees it', () {
      final g = CooldownGate();
      expect(g.tryAcquire(t0), isTrue);
      expect(g.tryAcquire(t0.add(const Duration(seconds: 30))), isFalse);
      expect(g.secondsLeft(t0.add(const Duration(seconds: 30))), 30);
      expect(g.tryAcquire(t0.add(const Duration(seconds: 61))), isTrue);
      g.release();
      expect(g.tryAcquire(t0.add(const Duration(seconds: 62))), isTrue, reason: 'a failed send does not burn the minute');
    });
  });

  group('role x state matrix (F.3.4): the primary action of the Collapsed sheet', () {
    Trip trip(TripStatus s, {TripRole? role}) =>
        sampleTrip(mode: role == null ? TravelMode.walk : TravelMode.car, role: role, status: s);
    MatchSummary match(TripRole? mine, {DateTime? boarded, MatchStatus status = MatchStatus.accepted}) =>
        sampleMatch(status: status, myRole: mine, boardedAt: boarded);

    test('scheduled: everybody gets the start slider (P-5)', () {
      expect(ridePrimaryFor(trip: trip(TripStatus.scheduled, role: TripRole.rider), match: match(TripRole.rider), arrivedState: false),
          RidePrimary.sliderStart);
      expect(ridePrimaryFor(trip: trip(TripStatus.scheduled, role: TripRole.driver), match: match(TripRole.driver), arrivedState: false),
          RidePrimary.sliderStart);
      expect(ridePrimaryFor(trip: trip(TripStatus.scheduled), match: null, arrivedState: false), RidePrimary.sliderStart);
    });

    test('in progress, before boarding: Rider = board slider, Driver = "arrived at pickup" button (P-9)', () {
      expect(ridePrimaryFor(trip: trip(TripStatus.inProgress, role: TripRole.rider), match: match(TripRole.rider), arrivedState: false),
          RidePrimary.sliderBoard);
      expect(ridePrimaryFor(trip: trip(TripStatus.inProgress, role: TripRole.driver), match: match(TripRole.driver), arrivedState: false),
          RidePrimary.arrivedAtPickup);
    });

    test('boarded, solo, Peer and ended matches: the arrive slider', () {
      final b = DateTime(2026);
      expect(ridePrimaryFor(trip: trip(TripStatus.inProgress, role: TripRole.rider), match: match(TripRole.rider, boarded: b), arrivedState: false),
          RidePrimary.sliderArrive);
      expect(ridePrimaryFor(trip: trip(TripStatus.inProgress, role: TripRole.driver), match: match(TripRole.driver, boarded: b), arrivedState: false),
          RidePrimary.sliderArrive);
      expect(ridePrimaryFor(trip: trip(TripStatus.inProgress), match: null, arrivedState: false), RidePrimary.sliderArrive);
      expect(ridePrimaryFor(trip: trip(TripStatus.inProgress), match: match(null), arrivedState: false), RidePrimary.sliderArrive,
          reason: 'Peer match: nobody is picked up');
      expect(
          ridePrimaryFor(
              trip: trip(TripStatus.inProgress, role: TripRole.driver),
              match: match(TripRole.driver, status: MatchStatus.cancelled),
              arrivedState: false),
          RidePrimary.sliderArrive,
          reason: 'peer ended: carry on');
    });

    test('arrived state has no slider', () {
      expect(ridePrimaryFor(trip: trip(TripStatus.completed), match: null, arrivedState: true), RidePrimary.arrivedSummary);
    });

    test('rideMatchFor: accepted first; an ended car match only while it matters (Driver / boarded Rider)', () {
      final t = trip(TripStatus.inProgress, role: TripRole.driver);
      final accepted = match(TripRole.driver);
      final ended = match(TripRole.driver, status: MatchStatus.cancelled);
      expect(rideMatchFor(t, [ended, accepted])?.status, MatchStatus.accepted);
      expect(rideMatchFor(t, [ended])?.status, MatchStatus.cancelled);
      // a Rider whose unboarded match ended gets nothing here (the app-wide alert covers it)
      final r = trip(TripStatus.inProgress, role: TripRole.rider);
      expect(rideMatchFor(r, [match(TripRole.rider, status: MatchStatus.cancelled)]), isNull);
      expect(rideMatchFor(r, [match(TripRole.rider, status: MatchStatus.cancelled, boarded: DateTime(2026))]), isNotNull);
      // another trip's match is never used
      expect(rideMatchFor(t, [sampleMatch(myTripId: 'other', status: MatchStatus.accepted, myRole: TripRole.driver)]), isNull);
    });
  });
}
