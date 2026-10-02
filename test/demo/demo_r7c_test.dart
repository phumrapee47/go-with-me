import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/demo/demo_data.dart';
import 'package:gowithme/demo/demo_fakes.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('US-49: DemoMatchRepository.cancelNoFault mirrors the server contract', () {
    Future<DemoMatchRepository> driverWithAcceptedCarMatch() async {
      final trips = DemoTripRepository()..reset(DemoScenario.driver);
      final matches = DemoMatchRepository(trips)..reset(DemoScenario.driver);
      // demoCarMatches seeds ONE incoming pending request; accept it so it becomes a car match.
      await matches.respond('demo-match-pending', accept: true);
      expect(matches.acceptedCar, isNotNull);
      return matches;
    }

    test('default: the client hint is never trusted -> GWM_NOT_OVERDUE', () async {
      final matches = await driverWithAcceptedCarMatch();
      final res = await matches.cancelNoFault(matches.acceptedCar!.id);
      expect(res.failureOrNull?.code, 'GWM_NOT_OVERDUE');
      expect(matches.acceptedCar, isNotNull, reason: 'nothing changed');
    });

    test('once the server confirms overdue: cancels with no-fault, idempotent on repeat', () async {
      final matches = await driverWithAcceptedCarMatch();
      final id = matches.acceptedCar!.id;
      matches.demoServerConfirmsOverdue = true;
      final first = await matches.cancelNoFault(id);
      expect(first.valueOrNull, 'cancelled');
      expect(matches.acceptedCar, isNull);
      final again = await matches.cancelNoFault(id);
      expect(again.valueOrNull, 'already_cancelled', reason: 'Q12: first-write-wins, no error on repeat');
    });

    test('unknown match id: GWM_MATCH_NOT_FOUND', () async {
      final trips = DemoTripRepository()..reset(DemoScenario.driver);
      final matches = DemoMatchRepository(trips)..reset(DemoScenario.driver);
      final res = await matches.cancelNoFault('no-such-match');
      expect(res.failureOrNull?.code, 'GWM_MATCH_NOT_FOUND');
    });

    test('a non-car (peer) match is never eligible: GWM_NOT_ELIGIBLE even when "overdue" is forced', () async {
      final trips = DemoTripRepository()..reset(DemoScenario.peer);
      final matches = DemoMatchRepository(trips)..reset(DemoScenario.peer)..demoServerConfirmsOverdue = true;
      final res = await matches.cancelNoFault('demo-match-accepted');
      expect(res.failureOrNull?.code, 'GWM_NOT_ELIGIBLE');
    });
  });

  group('US-50: detour tolerance updates + demo matching OR logic', () {
    test('DemoTripRepository.updateDetourTolerance enforces the same shape of server errors as max_dropoff_m',
        () async {
      final trips = DemoTripRepository()..reset(DemoScenario.driver);
      expect((await trips.updateDetourTolerance('demo-trip-me', 250)).failureOrNull?.code, 'GWM_DETOUR_INVALID');
      expect((await trips.updateDetourTolerance('demo-trip-me', 2500)).failureOrNull?.code, 'GWM_DETOUR_INVALID');
      trips.hasOpenMatch = (_) => true;
      expect((await trips.updateDetourTolerance('demo-trip-me', 1000)).failureOrNull?.code, 'GWM_TRIP_HAS_MATCHES');
      final rider = DemoTripRepository()..reset(DemoScenario.rider);
      expect((await rider.updateDetourTolerance('demo-trip-me', 1000)).failureOrNull?.code, 'GWM_DETOUR_NOT_ALLOWED');
    });

    test('a driver trip defaults to 500 m detour tolerance', () async {
      final trips = DemoTripRepository()..reset(DemoScenario.driver);
      expect(trips.active?.detourToleranceM, 500);
    });

    test('OR logic: a rider destination that fails max_dropoff_m alone can still match via detour tolerance',
        () async {
      // Candidate index 0: destGap 800 m, detourApprox 300 m (see demo_data.dart).
      final narrowDropoffOnly = demoCarCandidates(TripRole.driver, driverLimitM: 500, driverDetourM: 0);
      expect(narrowDropoffOnly, isEmpty, reason: 'max_dropoff_m=500 alone rejects the 800 m gap candidate');

      final withDetour = demoCarCandidates(TripRole.driver, driverLimitM: 500, driverDetourM: 300);
      expect(withDetour, isNotEmpty, reason: 'detour tolerance 300 m OR-matches the same candidate');
    });

    test('a WIDE detour tolerance surfaces more candidates than a NARROW one (same max_dropoff_m)', () async {
      final narrow = demoCarCandidates(TripRole.driver, driverLimitM: 500, driverDetourM: 300);
      final wide = demoCarCandidates(TripRole.driver, driverLimitM: 500, driverDetourM: 2000);
      expect(wide.length, greaterThan(narrow.length));
    });

    test('findMatches wires the driver trip\'s own detourToleranceM into the OR predicate', () async {
      final trips = DemoTripRepository()..reset(DemoScenario.driver);
      final matches = DemoMatchRepository(trips)..reset(DemoScenario.driver);
      await trips.updateMaxDropoff('demo-trip-me', 500);
      final narrow = (await matches.findMatches('demo-trip-me')).valueOrNull!.length;
      await trips.updateDetourTolerance('demo-trip-me', 2000);
      final wide = (await matches.findMatches('demo-trip-me')).valueOrNull!.length;
      expect(wide, greaterThanOrEqualTo(narrow));
    });
  });

  group('US-50/BUG-R7-01 (round 7 Stage D): demo detour-only candidate + vibe/mood', () {
    test('demoDetourOnlyCandidate is opt-in: absent by default, present with includeDetourOnly, '
        'never shown to a Driver (it is a Driver candidate itself)', () {
      expect(demoCarCandidates(TripRole.rider).any((c) => c.tripId == demoDetourOnlyCandidateId), isFalse);
      final withIt = demoCarCandidates(TripRole.rider, includeDetourOnly: true);
      expect(withIt.any((c) => c.tripId == demoDetourOnlyCandidateId), isTrue);
      expect(demoCarCandidates(TripRole.driver, includeDetourOnly: true).any((c) => c.tripId == demoDetourOnlyCandidateId),
          isFalse);
    });

    test('carries vibe/mood so the demo also proves BUG-R7-01 end-to-end', () {
      final c = demoDetourOnlyCandidate();
      expect(c.vibeTags, isNotEmpty);
      expect(c.moodText, isNotNull);
    });

    test('hub toggle: DemoMatchRepository.showDetourOnlyCandidate wires it into findMatches/request', () async {
      final trips = DemoTripRepository()..reset(DemoScenario.rider);
      final matches = DemoMatchRepository(trips)..reset(DemoScenario.rider);
      var list = (await matches.findMatches('demo-trip-me')).valueOrNull!;
      expect(list.any((c) => c.tripId == demoDetourOnlyCandidateId), isFalse);

      matches.showDetourOnlyCandidate = true;
      list = (await matches.findMatches('demo-trip-me')).valueOrNull!;
      expect(list.any((c) => c.tripId == demoDetourOnlyCandidateId), isTrue);

      final res = await matches.request(myTripId: 'demo-trip-me', targetTripId: demoDetourOnlyCandidateId);
      expect(res.valueOrNull, isNotNull, reason: 'the demo repo itself never validates a detour value (real OSRM '
          'calc + p_client_detour_m happen client-side in NearbyController, see precise_detour_request_test.dart)');
    });

    test('DemoRouting.failNextRoute throws exactly once then resets (drives the hub\'s OSRM-failure toggle)', () async {
      final routing = DemoRouting()..failNextRoute = true;
      await expectLater(
        routing.route(mode: TravelMode.car, from: const LatLng(13.7, 100.5), to: const LatLng(13.8, 100.6)),
        throwsA(isA<AppFailure>()),
      );
      expect(routing.failNextRoute, isFalse);
      // The next call succeeds normally.
      final r = await routing.route(mode: TravelMode.car, from: const LatLng(13.7, 100.5), to: const LatLng(13.8, 100.6));
      expect(r.distanceM, greaterThan(0));
    });
  });
}
