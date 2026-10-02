// US-50 (round 7 Stage D): end-to-end deck-invite tests for the client-side
// PRECISE (OSRM) detour calculation wired into `NearbyController.request`
// (lib/features/matching/presentation/matching_providers.dart), exercised the
// same way the round 6 deck tests exercise `request_match` failures.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';

const _siam = LatLng(13.7455, 100.5345);
const _riderDest = LatLng(13.9, 100.6); // close to the driver's own destination below
const _driverDestNear = LatLng(13.902, 100.602); // ~300 m from _riderDest: radial path already qualifies
const _driverDestFar = LatLng(14.5, 101.5); // tens of km from _riderDest: only the detour-tolerance path can pass

Trip _riderTrip() => Trip(
      id: 'trip-1',
      mode: TravelMode.car,
      role: TripRole.rider,
      status: TripStatus.scheduled,
      origin: _siam,
      dest: _riderDest,
      originLabel: 'สยาม',
      destLabel: 'ปลายทางของฉัน',
      route: const [_siam, _riderDest],
      distanceM: 20000,
      durationS: 1800,
      departAt: DateTime.now().add(const Duration(minutes: 10)),
    );

MatchCandidate _driverCandidate({required LatLng dest, required int maxDropoffM}) => MatchCandidate(
      tripId: 'a',
      displayName: 'คนขับ',
      role: TripRole.driver,
      badges: const [VerificationBadge(kind: 'email')],
      mode: TravelMode.car,
      departAt: DateTime.now().add(const Duration(minutes: 15)),
      timeDiffMin: 5,
      overlapPct: 72,
      approxDistanceM: 1500,
      score: 80,
      approxOrigin: _siam,
      approxDest: dest,
      requestStatus: null,
      maxDropoffM: maxDropoffM,
    );

Future<Fakes> _openDeck(WidgetTester tester, Fakes f) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await buildTestApp(
    repo: FakeAuthRepository(initial: testUser),
    prefs: {'onboarding_done': true, 'gwm.nearbyView': 'deck'},
    fakes: f,
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text(S.tabNearby));
  await tester.pumpAndSettle();
  return f;
}

Future<void> _tapInvite(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('deck-invite')));
  await tester.pumpAndSettle();
}

void main() {
  group('precise (OSRM) detour at request_match time (US-50, migration 0016)', () {
    testWidgets('detour-only candidate: OSRM succeeds, p_client_detour_m computed and sent, request succeeds',
        (tester) async {
      final f = Fakes()
        ..trips.active = _riderTrip()
        ..finder.result = [_driverCandidate(dest: _driverDestFar, maxDropoffM: 1000)];
      await _openDeck(tester, f);
      await _tapInvite(tester);

      expect(f.routing.calls, 3, reason: 'direct + origin->rider + rider->dest, exactly per 0016\'s formula');
      expect(f.matches.requests, [('trip-1', 'a')]);
      expect(f.matches.requestDetourM.single, isNotNull);
      expect(f.matches.requestDetourM.single, greaterThan(0));
      // Request succeeded: the invite banner/undo window is up, no failure notice.
      expect(find.byKey(const Key('undo-banner')), findsOneWidget);
    });

    testWidgets('candidate already qualifies via the radial max_dropoff_m path: no OSRM calls, '
        'p_client_detour_m omitted', (tester) async {
      final f = Fakes()
        ..trips.active = _riderTrip()
        ..finder.result = [_driverCandidate(dest: _driverDestNear, maxDropoffM: 1000)];
      await _openDeck(tester, f);
      await _tapInvite(tester);

      expect(f.routing.calls, 0);
      expect(f.matches.requests, [('trip-1', 'a')]);
      expect(f.matches.requestDetourM.single, isNull);
      expect(find.byKey(const Key('undo-banner')), findsOneWidget);
    });

    testWidgets('OSRM failure at request time: request_match is never called, a clear "ลองใหม่อีกครั้ง" '
        'notice shows, and the card stays (not a permanent rule failure)', (tester) async {
      final f = Fakes()
        ..trips.active = _riderTrip()
        ..finder.result = [_driverCandidate(dest: _driverDestFar, maxDropoffM: 1000)]
        ..routing.failure = const AppFailure(FailureCode.networkTimeout, retryable: true);
      await _openDeck(tester, f);
      await _tapInvite(tester);

      expect(f.matches.requests, isEmpty, reason: 'never guesses a number, never calls the RPC without one');
      expect(find.textContaining('ลองใหม่อีกครั้ง'), findsOneWidget);
      expect(find.byKey(const Key('commute-card-a')), findsOneWidget, reason: 'a retry-able hiccup, not a rule failure');
      expect(find.byKey(const Key('undo-banner')), findsNothing);
      // The invite button is usable again (not permanently disabled by this transient failure).
      expect(tester.widget<FilledButton>(find.byKey(const Key('deck-invite'))).onPressed, isNotNull);
    });
  });
}
