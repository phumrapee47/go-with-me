import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings_p4.dart';
import 'package:gowithme/core/l10n/strings_r6.dart';
import 'package:gowithme/core/l10n/strings_roles.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/geo/domain/location_service.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/matching/presentation/matching_providers.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/domain/trip_state_machine.dart';
import 'package:gowithme/features/trip/presentation/trip_lifecycle_providers.dart';
import 'package:gowithme/features/trip/presentation/unified_ride_screen.dart';
import 'package:gowithme/features/vehicle/domain/vehicle.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';
import '../../support/ride_helpers.dart';

const _plateView = VehicleView(plate: 'ขข 5678', model: 'Honda City', color: 'เทา/เงิน', shareAllowed: true);

Trip _car(TripRole role, {TripStatus status = TripStatus.scheduled, String id = 'trip-1'}) =>
    sampleTrip(id: id, mode: TravelMode.car, role: role).copyWith(
      status: status,
      startedAt: status == TripStatus.inProgress ? DateTime.now() : null,
    );

MatchSummary _riderMatch({
  MatchStatus status = MatchStatus.accepted,
  DateTime? boardedAt,
  TripStatus partner = TripStatus.scheduled,
  LatLng? proposed,
  LatLng? meeting,
}) {
  final m = sampleMatch(
    status: status,
    myRole: TripRole.rider,
    boardedAt: boardedAt,
    partnerTripStatus: partner,
    proposed: proposed,
    name: 'สมชาย',
  );
  return meeting == null ? m : m.copyWith(meetingPoint: meeting, meetingLabel: 'หน้าสถานี');
}

MatchSummary _driverMatch({
  MatchStatus status = MatchStatus.accepted,
  DateTime? boardedAt,
  LatLng? proposed,
  bool proposedByMe = false,
  LatLng? meeting,
}) {
  final m = sampleMatch(
    status: status,
    myRole: TripRole.driver,
    boardedAt: boardedAt,
    proposed: proposed,
    proposedByMe: proposedByMe,
    name: 'ใจดี',
  );
  return meeting == null ? m : m.copyWith(meetingPoint: meeting, meetingLabel: 'หน้าสถานี');
}

/// The pick screen keeps a spinner running while a dialog waits for the user,
/// so pumpAndSettle would never settle there.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tapDialog(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  group('match page (car): Rider', () {
    testWidgets('accepted: role badge, vehicle card with the unverified label, consent status, cancel available',
        (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider)
        ..matches.matches = [_riderMatch()];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.text(R.roleBadgeDriver), findsWidgets);
      expect(find.byKey(const Key('vehicle-plate')), findsOneWidget);
      expect(find.text('ขข 5678'), findsOneWidget);
      expect(find.text('Honda City'), findsOneWidget);
      expect(find.textContaining('เทา/เงิน'), findsOneWidget, reason: 'colour is always written out');
      expect(find.text(R.unverified), findsOneWidget);
      expect(find.text(R.justMatched), findsOneWidget);
      expect(find.byKey(const Key('consent-allowed')), findsOneWidget);
      expect(find.text(R.plateShareAllowed), findsOneWidget);
      expect(find.text(R.pickupWaitDriver), findsOneWidget, reason: 'a Rider cannot open the proposal');
      expect(find.byKey(const Key('pickup-propose')), findsNothing);
      expect(find.byKey(const Key('cancel-match')), findsOneWidget);
    });

    testWidgets('driver did not allow the plate: the status says so and still reveals nothing extra', (tester) async {
      final f = Fakes()
        ..vehicles.view = const VehicleView(plate: 'ขข 5678', model: 'Honda City', color: 'ดำ')
        ..trips.active = _car(TripRole.rider)
        ..matches.matches = [_riderMatch()];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.byKey(const Key('consent-denied')), findsOneWidget);
      expect(find.text(R.plateShareDenied), findsOneWidget);
    });

    testWidgets('a pending request never shows a vehicle, not even a placeholder', (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider)
        ..matches.matches = [_riderMatch(status: MatchStatus.pending)];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.byKey(const Key('vehicle-plate')), findsNothing);
      expect(f.vehicles.forMatchCalls, isEmpty, reason: 'nothing is even requested before acceptance');
    });

    testWidgets('cancel: role wording incl. "your trip goes back to search", neutral confirmation afterwards',
        (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider)
        ..matches.matches = [_riderMatch()];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      await tester.ensureVisible(find.byKey(const Key('cancel-match')));
      await tester.tap(find.byKey(const Key('cancel-match')));
      await tester.pumpAndSettle();
      expect(find.text(R.cancelTitle), findsOneWidget);
      expect(find.text(R.cancelBodyRider), findsOneWidget);
      expect(find.textContaining('กลับไปอยู่ในการค้นหา'), findsOneWidget);
      await _tapDialog(tester, R.cancelKeep);
      expect(f.matches.matches.single.status, MatchStatus.accepted);

      await tester.tap(find.byKey(const Key('cancel-match')));
      await tester.pumpAndSettle();
      await _tapDialog(tester, R.cancel);
      expect(find.byKey(const Key('match-ended')), findsOneWidget);
      expect(find.text(R.endedByMe), findsWidgets);
      expect(find.text(R.endedBackToSearch), findsOneWidget);
      // Before boarding, the vehicle disappears at once.
      expect(find.byKey(const Key('vehicle-plate')), findsNothing);
      expect(find.byKey(const Key('vehicle-ended')), findsOneWidget);
    });

    testWidgets('after boarding there is no cancel; if the match ended the vehicle stays visible (Q-2)', (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_riderMatch(boardedAt: DateTime(2026, 9, 25, 18, 42), partner: TripStatus.inProgress)];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.byKey(const Key('cancel-match')), findsNothing);
      expect(find.byKey(const Key('no-cancel-after-boarded')), findsOneWidget);

      // The Driver finished first: match is over but the Rider had boarded.
      f.matches.matches = [
        _riderMatch(status: MatchStatus.cancelled, boardedAt: DateTime(2026, 9, 25, 18, 42), partner: TripStatus.inProgress),
      ];
      containerOf(tester).invalidate(inboxProvider);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vehicle-plate')), findsOneWidget, reason: 'boarded Rider keeps the vehicle info');
      expect(find.byKey(const Key('vehicle-ended')), findsNothing);
    });

    testWidgets('ended before boarding: vehicle hidden with a neutral explanation', (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider)
        ..matches.matches = [_riderMatch(status: MatchStatus.cancelled)];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.byKey(const Key('vehicle-plate')), findsNothing);
      expect(find.text(R.vehicleEnded), findsOneWidget);
      expect(find.text(R.ended), findsOneWidget);
      expect(find.text(R.endedBackToSearch), findsOneWidget);
      expect(f.vehicles.forMatchCalls, isEmpty);
    });

    testWidgets('driver late: warning + the cancel button', (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider);
      // Partner departure time is in the past.
      f.matches.matches = [
        MatchSummary(
          id: 'm1',
          status: MatchStatus.accepted,
          iAmRequester: false,
          myTripId: 'trip-1',
          partnerTripId: 'cand-1',
          partnerName: 'สมชาย',
          badges: const [],
          mode: TravelMode.car,
          departAt: DateTime.now().subtract(const Duration(minutes: 20)),
          overlapPct: 70,
          approxOrigin: null,
          approxDest: null,
          meetingPoint: null,
          meetingLabel: null,
          proposedPoint: null,
          proposedLabel: null,
          proposedByMe: false,
          createdAt: DateTime.now(),
          myRole: TripRole.rider,
          partnerRole: TripRole.driver,
          partnerTripStatus: TripStatus.scheduled,
        ),
      ];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.byKey(const Key('driver-late')), findsOneWidget);
      expect(find.text(R.driverLate), findsOneWidget);
      expect(find.byKey(const Key('cancel-match')), findsOneWidget);
    });
  });

  group('match page (car): Driver and the pickup handshake', () {
    testWidgets('Driver sees a preview of the vehicle Riders get, an edit link and can open the proposal',
        (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: '1กก 1234', model: 'Toyota Yaris', color: 'ขาว')
        ..trips.active = _car(TripRole.driver)
        ..matches.matches = [_driverMatch()];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.text(R.roleBadgeRider), findsWidgets);
      expect(find.text(R.ownerPreviewTitle), findsOneWidget);
      expect(find.byKey(const Key('edit-vehicle-link')), findsOneWidget);
      expect(find.byKey(const Key('consent-allowed')), findsNothing, reason: 'status row is for Riders');
      expect(find.text(R.pickupNone), findsOneWidget);
      expect(find.byKey(const Key('pickup-propose')), findsOneWidget);
      expect(f.vehicles.forMatchCalls, isEmpty);
    });

    testWidgets('Rider sees the Driver proposal and confirms it; counter-propose is offered', (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider)
        ..matches.matches = [_riderMatch(proposed: const LatLng(13.7453, 100.5340))];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.text(R.pickupProposedByDriver('หน้าสถานี')), findsOneWidget);
      expect(find.byKey(const Key('pickup-propose-again')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('pickup-confirm')));
      await tester.tap(find.byKey(const Key('pickup-confirm')));
      await tester.pumpAndSettle();
      expect(f.matches.matches.single.meetingPoint, isNotNull);
      expect(find.text(R.pickupAgreed('หน้าสถานี')), findsOneWidget);
    });

    testWidgets('the proposer sees "waiting" and cannot confirm their own proposal', (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver)
        ..matches.matches = [_driverMatch(proposed: const LatLng(13.75, 100.53), proposedByMe: true)];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.text(R.pickupWaitingOther(R.pickupWhoRider, 'หน้าสถานี')), findsOneWidget);
      expect(find.byKey(const Key('pickup-confirm')), findsNothing);
    });

    testWidgets('once the trip started the pickup card is read-only', (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver, status: TripStatus.inProgress)
        ..matches.matches = [_driverMatch(meeting: const LatLng(13.75, 100.53))];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.text(R.pickupAgreed('หน้าสถานี')), findsOneWidget);
      expect(find.byKey(const Key('pickup-propose-again')), findsNothing);
      expect(find.text(R.pickupReadOnly), findsOneWidget);
    });

    testWidgets('Driver progress row: rider not boarded yet -> boarded', (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver, status: TripStatus.inProgress)
        ..matches.matches = [_driverMatch()];
      await openApp(tester, f);
      await goTo(tester, Routes.match('m1'));
      expect(find.text(R.driverStatusWaiting), findsWidgets);
      expect(find.text('${R.tripStatusBoth}: ${R.partnerMoving}'), findsOneWidget);
    });
  });

  group('pickup proposal screen (S-34): soft warning only', () {
    testWidgets('Rider: server says "beyond the limit" (a boolean) -> warning, keep it, point was saved',
        (tester) async {
      final f = Fakes()
        ..trips.active = _car(TripRole.rider)
        ..matches.proposeBeyondLimit = true
        ..matches.matches = [_riderMatch(proposed: const LatLng(13.7453, 100.5340))];
      await openApp(tester, f);
      await goTo(tester, Routes.pickup('m1'));
      expect(find.byKey(const Key('pick-confirm')), findsOneWidget);
      expect(find.text(R.pickupSendNew), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-confirm')));
      await _settle(tester);
      expect(find.byKey(const Key('off-route-dialog')), findsOneWidget);
      expect(find.text(R.pickupOffRoute), findsOneWidget, reason: 'no distance is ever shown to a Rider');
      expect(find.textContaining('เมตร'), findsNothing);
      expect(f.matches.proposals, hasLength(1), reason: 'saved even though it is only a warning');
      await tester.tap(find.byKey(const Key('off-route-continue')));
      await _settle(tester);
      expect(find.byKey(const Key('pick-confirm')), findsNothing, reason: 'closed after keeping the point');
    });

    testWidgets('Rider: within the limit -> no warning at all', (tester) async {
      final f = Fakes()
        ..trips.active = _car(TripRole.rider)
        ..matches.matches = [_riderMatch(proposed: const LatLng(13.7453, 100.5340))];
      await openApp(tester, f);
      await goTo(tester, Routes.pickup('m1'));
      await tester.tap(find.byKey(const Key('pick-confirm')));
      await _settle(tester);
      expect(find.byKey(const Key('off-route-dialog')), findsNothing);
      expect(f.matches.proposals, hasLength(1));
    });

    testWidgets('Driver: own route lets the app show the distance BEFORE sending; "change" sends nothing',
        (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver)
        // Map starts 18 km east of the route.
        ..matches.matches = [_driverMatch(proposed: const LatLng(13.7455, 100.70))];
      await openApp(tester, f);
      await goTo(tester, Routes.pickup('m1'));
      expect(find.text(R.pickupSend), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-confirm')));
      await _settle(tester);
      expect(find.byKey(const Key('off-route-dialog')), findsOneWidget);
      expect(find.textContaining('เมตร'), findsOneWidget);
      expect(f.matches.proposals, isEmpty);

      await tester.tap(find.text(R.pickupOffRouteChange));
      await _settle(tester);
      expect(f.matches.proposals, isEmpty, reason: 'choosing another point sends nothing');

      await tester.tap(find.byKey(const Key('pick-confirm')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('off-route-continue')));
      await _settle(tester);
      expect(f.matches.proposals, hasLength(1), reason: 'the user can always continue');
    });

    testWidgets('server errors (driver first) are shown in Thai and the screen stays', (tester) async {
      final f = Fakes()
        ..trips.active = _car(TripRole.rider)
        ..matches.matches = [_riderMatch(proposed: const LatLng(13.7453, 100.5340))];
      await openApp(tester, f);
      await goTo(tester, Routes.pickup('m1'));
      f.matches.proposeFailure = const AppFailure('GWM_PICKUP_DRIVER_FIRST');
      await tester.tap(find.byKey(const Key('pick-confirm')));
      await _settle(tester);
      expect(find.textContaining('ให้คนขับเสนอจุดรับก่อน'), findsOneWidget);
      expect(find.byKey(const Key('pick-confirm')), findsOneWidget);
    });

    testWidgets('after the trip started the screen is read-only', (tester) async {
      final f = Fakes()
        ..trips.active = _car(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_riderMatch(proposed: const LatLng(13.7453, 100.5340))];
      await openApp(tester, f);
      await goTo(tester, Routes.pickup('m1'));
      expect(find.byKey(const Key('pick-confirm')), findsNothing);
      expect(find.text(R.pickupReadOnly), findsOneWidget);
    });
  });

  group('active trip: boarding, no-show, live location', () {
    testWidgets('Rider: button is disabled with a visible reason until the Driver started', (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_riderMatch()];
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      // Round 6: the board slider is disabled (lock icon) and the reason is visible text.
      expect(find.byKey(sliderBoardKey), findsOneWidget);
      expect(find.text(R.boardDisabledDriver), findsOneWidget);
      await dragSlider(tester, sliderBoardKey);
      expect(f.matches.boarded, isEmpty, reason: 'a disabled slider never calls the RPC');
      await sheetTo(tester, SheetLevel.half);
      expect(find.byKey(const Key('vehicle-compact-line')), findsOneWidget, reason: 'compact vehicle line');
      expect(find.byKey(sliderArriveKey), findsOneWidget, reason: '"arrived" never depends on boarding');
    });

    testWidgets('Rider boards: slide (no dialog) -> done text + location stopped note; no cancel afterwards',
        (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_riderMatch(partner: TripStatus.inProgress)];
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));

      // released early: springs back, nothing is sent, no dialog
      await dragSlider(tester, sliderBoardKey, dx: 60);
      expect(f.matches.boarded, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);

      // a plain tap does nothing (only a hint)
      await tester.tap(find.byKey(sliderBoardKey));
      await tester.pump(const Duration(milliseconds: 200));
      expect(f.matches.boarded, isEmpty);

      await dragSlider(tester, sliderBoardKey);
      expect(find.byType(AlertDialog), findsNothing, reason: 'the confirm dialog is gone for the routine change');
      expect(f.matches.boarded, ['m1']);
      expect(find.byKey(sliderBoardKey), findsNothing, reason: 'the state moved on: now the arrive slider');
      await sheetTo(tester, SheetLevel.half);
      expect(find.byKey(const Key('boarded-done')), findsOneWidget);
      expect(find.byKey(const Key('board-location-stopped')), findsOneWidget);
    });

    testWidgets('Rider boards with the screen-reader path (double tap) and with press-and-hold', (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_riderMatch(partner: TripStatus.inProgress)];
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));

      // press-and-hold released before 1.5 s: nothing happens
      await holdSlider(tester, sliderBoardKey, const Duration(milliseconds: 900));
      expect(f.matches.boarded, isEmpty);

      await activateSliderViaSemantics(tester, R6.sliderBoard);
      expect(f.matches.boarded, ['m1']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('boarding error from the server is shown (trip not started)', (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_riderMatch(partner: TripStatus.inProgress)];
      f.matches.boardFailure = const AppFailure('GWM_TRIP_NOT_STARTED');
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      await dragSlider(tester, sliderBoardKey);
      expect(find.byKey(const Key('slider-error')), findsOneWidget);
      expect(find.text(R.boardDisabledDriver), findsOneWidget);
      expect(find.byKey(const Key('boarded-done')), findsNothing);
      expect(find.byKey(sliderBoardKey), findsOneWidget, reason: 'back to idle, can be tried again');
    });

    testWidgets('boarded Rider stops sending positions to the Driver but still sees the Driver', (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_riderMatch(partner: TripStatus.inProgress)];
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      f.location.fixes.add(LocationFix(point: const LatLng(13.75, 100.53), at: DateTime.now(), accuracyM: 10));
      await tester.pumpAndSettle();
      expect(f.live.pushes, hasLength(1), reason: 'before boarding the Driver may see the Rider');

      // Boarded now.
      f.matches.matches = [_riderMatch(boardedAt: DateTime.now(), partner: TripStatus.inProgress)];
      containerOf(tester).invalidate(inboxProvider);
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(livePushPartnersProvider), isEmpty, reason: 'no push target any more');
      expect(containerOf(tester).read(sharingPartnersProvider).valueOrNull, ['m1'],
          reason: 'the Rider still receives the Driver position');
      f.location.fixes.add(LocationFix(point: const LatLng(13.751, 100.531), at: DateTime.now(), accuracyM: 10));
      await tester.pumpAndSettle();
      expect(f.live.pushes, hasLength(1), reason: 'nothing more is pushed for the Driver');
    });

    testWidgets('Driver: sees "rider not boarded", no-show needs confirmation and ends the match neutrally',
        (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver, status: TripStatus.inProgress)
        ..matches.matches = [_driverMatch()];
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half);
      expect(find.text(R.driverStatusWaiting), findsWidgets);
      await tester.ensureVisible(find.byKey(const Key('no-show-button')));
      await tester.tap(find.byKey(const Key('no-show-button')));
      await tester.pumpAndSettle();
      expect(find.text(R.noShowTitle), findsOneWidget);
      expect(find.text(R.noShowBody), findsOneWidget);
      await _tapDialog(tester, R.noShowKeep);
      expect(f.matches.noShows, isEmpty);

      await tester.tap(find.byKey(const Key('no-show-button')));
      await tester.pumpAndSettle();
      await _tapDialog(tester, R.noShowConfirm);
      expect(f.matches.noShows, ['m1']);
      expect(find.byKey(const Key('driver-match-ended')), findsOneWidget);
      expect(find.text(R.endedDriverSide), findsOneWidget);
      expect(find.byKey(const Key('no-show-button')), findsNothing);
      expect(find.byKey(sliderArriveKey), findsOneWidget, reason: 'the Driver simply carries on');
      // No reason and no blame text anywhere.
      expect(find.textContaining('ไม่มาตามนัด'), findsNothing);
    });

    testWidgets('Driver: after the Rider boarded there is no no-show button and no pin/position for the Rider',
        (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver, status: TripStatus.inProgress)
        ..matches.matches = [_driverMatch(boardedAt: DateTime.now())];
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half);
      expect(find.text(R.driverStatusDone), findsWidgets);
      expect(find.byKey(const Key('no-show-button')), findsNothing);
      expect(find.text(R.riderInCar), findsOneWidget);
    });

    testWidgets('Rider: Driver finished first -> "driver arrived" notice, own trip goes on', (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [
          _riderMatch(status: MatchStatus.cancelled, boardedAt: DateTime.now(), partner: TripStatus.inProgress),
        ];
      await openApp(tester, f);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half);
      expect(find.byKey(const Key('partner-arrived')), findsOneWidget);
      expect(find.byKey(sliderArriveKey), findsOneWidget);
    });
  });

  group('Driver cancelling the trip (Q-1)', () {
    testWidgets('after the Rider boarded: no cancel button, the reason is shown', (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver, status: TripStatus.inProgress)
        ..matches.matches = [_driverMatch(boardedAt: DateTime.now())];
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      expect(find.byKey(const Key('cancel-locked-boarded')), findsOneWidget);
      expect(find.text(R.cannotCancelAfterBoarded), findsOneWidget);
      expect(find.text(P.cancelTrip), findsNothing);
    });

    testWidgets('during the trip before boarding: the strong dialog, then the trip is cancelled', (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver, status: TripStatus.inProgress)
        ..matches.matches = [_driverMatch()];
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      await tester.ensureVisible(find.text(P.cancelTrip));
      await tester.tap(find.text(P.cancelTrip));
      await tester.pumpAndSettle();
      expect(find.text(R.cancelDuringTripTitle), findsOneWidget);
      expect(find.text(R.cancelDuringTripBody), findsOneWidget);
      await _tapDialog(tester, R.cancelDuringTripConfirm);
      expect(f.trips.transitions.last.$2.name, 'cancel');
    });

    testWidgets('a scheduled Driver trip with a match says the partner trip is NOT cancelled', (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver)
        ..matches.matches = [_driverMatch()];
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      await tester.ensureVisible(find.text(P.cancelTrip));
      await tester.tap(find.text(P.cancelTrip));
      await tester.pumpAndSettle();
      expect(find.text(R.cancelTripWithMatchBody), findsOneWidget);
    });

    testWidgets('the server refusal (GWM_ALREADY_BOARDED) is shown in Thai', (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver, status: TripStatus.inProgress)
        ..matches.matches = [_driverMatch()];
      f.trips.transitionFailure = const AppFailure('GWM_ALREADY_BOARDED');
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      await tester.ensureVisible(find.text(P.cancelTrip));
      await tester.tap(find.text(P.cancelTrip));
      await tester.pumpAndSettle();
      await _tapDialog(tester, R.cancelDuringTripConfirm);
      expect(find.textContaining('หลังคนนั่งขึ้นรถแล้ว'), findsOneWidget);
    });
  });

  group('start flow for car trips', () {
    testWidgets('first start: live-position notice once; Driver without agreed pickup gets a non-blocking reminder',
        (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver)
        ..matches.matches = [_driverMatch()];
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      // Contacts nudge (one-time, skippable) comes first.
      await tester.tap(find.text(P.startTrip));
      await tester.pumpAndSettle();
      if (find.text(P.noContactsTitle).evaluate().isNotEmpty) {
        await _tapDialog(tester, P.noContactsSkip);
      }
      expect(find.text(R.consentSheetBody), findsOneWidget);
      await _tapDialog(tester, R.consentSheetOk);
      expect(find.byKey(const Key('pickup-start-warning')), findsOneWidget);
      expect(find.text(R.pickupStartWarnBody), findsOneWidget);
      await _tapDialog(tester, R.pickupStartAnyway);
      expect(f.trips.transitions.any((t) => t.$2.name == 'start'), isTrue, reason: 'starting is never blocked');
    });

    testWidgets('declining the live-position notice does not start the trip', (tester) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider)
        ..matches.matches = [_riderMatch()];
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      await tester.tap(find.text(P.startTrip));
      await tester.pumpAndSettle();
      if (find.text(P.noContactsTitle).evaluate().isNotEmpty) {
        await _tapDialog(tester, P.noContactsSkip);
      }
      expect(find.text(R.consentSheetBody), findsOneWidget);
      await _tapDialog(tester, R.consentSheetBack);
      expect(f.trips.transitions, isEmpty);
    });

    testWidgets('a peer trip has neither dialog', (tester) async {
      final f = Fakes()..trips.active = sampleTrip();
      f.location.state = LocationPermissionState.granted;
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      await tester.tap(find.text(P.startTrip));
      await tester.pumpAndSettle();
      if (find.text(P.noContactsTitle).evaluate().isNotEmpty) {
        await _tapDialog(tester, P.noContactsSkip);
      }
      expect(find.text(R.consentSheetBody), findsNothing);
      expect(f.trips.transitions, hasLength(1));
    });
  });

  group('match-ended alert (Q-7): any screen, neutral, local notice', () {
    Future<Fakes> openRider(WidgetTester tester, {DateTime? boardedAt}) async {
      final f = Fakes()
        ..vehicles.view = _plateView
        ..trips.active = _car(TripRole.rider, status: TripStatus.inProgress)
        ..matches.matches = [_riderMatch(boardedAt: boardedAt, partner: TripStatus.inProgress)];
      await openApp(tester, f);
      await tester.pumpAndSettle();
      return f;
    }

    testWidgets('Driver ends the match before boarding: alert within ~3 s on ANY screen + one neutral local notice',
        (tester) async {
      final f = await openRider(tester);
      await goTo(tester, Routes.me); // not the match page, not the active trip
      expect(find.byKey(const Key('match-alert')), findsNothing);

      f.matches.matches = [_riderMatch(status: MatchStatus.cancelled, partner: TripStatus.inProgress)];
      f.matches.emitChange(); // Realtime `matches` event
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-alert')), findsOneWidget);
      expect(find.text(R.alertTitle), findsOneWidget);
      expect(find.text(R.alertSafety), findsOneWidget);
      // No name, plate or place in the alert.
      expect(find.textContaining('สมชาย'), findsNothing);
      expect(find.textContaining('ขข 5678'), findsNothing);
      expect(find.byKey(const Key('alert-sos')), findsOneWidget);
      expect(find.byKey(const Key('alert-share')), findsOneWidget);
      expect(find.byKey(const Key('alert-arrived')), findsOneWidget);
      expect(find.byKey(const Key('alert-cancel-trip')), findsOneWidget);

      expect(f.notifier.shown, hasLength(1));
      final n = f.notifier.shown.single;
      expect('${n.title} ${n.body}', isNot(anyOf(contains('สมชาย'), contains('ขข 5678'), contains('รังสิต'))));

      // Stays until acknowledged (no auto dismiss).
      await tester.pump(const Duration(seconds: 30));
      expect(find.byKey(const Key('match-alert')), findsOneWidget);
      await tester.tap(find.byKey(const Key('alert-ack')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-alert')), findsNothing);
    });

    testWidgets('shortcut SOS opens the SOS screen and dismisses the alert', (tester) async {
      final f = await openRider(tester);
      f.matches.matches = [_riderMatch(status: MatchStatus.cancelled, partner: TripStatus.inProgress)];
      f.matches.emitChange();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('alert-sos')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-alert')), findsNothing);
      expect(find.text(P.sosTapConfirm), findsOneWidget);
    });

    testWidgets('Rider who already boarded gets no alert (the Driver could not have cancelled)', (tester) async {
      final f = await openRider(tester, boardedAt: DateTime.now());
      f.matches.matches = [
        _riderMatch(status: MatchStatus.cancelled, boardedAt: DateTime.now(), partner: TripStatus.inProgress),
      ];
      f.matches.emitChange();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-alert')), findsNothing);
      expect(f.notifier.shown, isEmpty);
    });

    testWidgets('my own cancellation is not an alert', (tester) async {
      final f = await openRider(tester);
      await goTo(tester, Routes.match('m1'));
      await tester.ensureVisible(find.byKey(const Key('cancel-match')));
      await tester.tap(find.byKey(const Key('cancel-match')));
      await tester.pumpAndSettle();
      await _tapDialog(tester, R.cancel);
      expect(find.byKey(const Key('match-alert')), findsNothing);
      expect(f.notifier.shown, isEmpty);
    });

    testWidgets('finishing my own trip is not an alert either', (tester) async {
      final f = await openRider(tester);
      await containerOf(tester).read(tripActionsProvider).run('trip-1', TripAction.complete);
      f.matches.matches = [_riderMatch(status: MatchStatus.cancelled, partner: TripStatus.inProgress)];
      f.matches.emitChange();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-alert')), findsNothing);
    });

    testWidgets('the Driver side never gets the alert', (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
        ..trips.active = _car(TripRole.driver, status: TripStatus.inProgress)
        ..matches.matches = [_driverMatch()];
      await openApp(tester, f);
      f.matches.matches = [_driverMatch(status: MatchStatus.cancelled)];
      f.matches.emitChange();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-alert')), findsNothing);
    });

    testWidgets('coming back to the foreground refreshes the inbox at once', (tester) async {
      final f = await openRider(tester);
      final before = f.matches.inboxCalls;
      final c = containerOf(tester);
      c.read(appForegroundProvider.notifier).state = false;
      await tester.pump();
      c.read(appForegroundProvider.notifier).state = true;
      await tester.pumpAndSettle();
      expect(f.matches.inboxCalls, greaterThan(before));
    });

    testWidgets('a missed ending is noticed after resume (no Realtime event)', (tester) async {
      final f = await openRider(tester);
      f.matches.matches = [_riderMatch(status: MatchStatus.cancelled, partner: TripStatus.inProgress)];
      final c = containerOf(tester);
      c.read(appForegroundProvider.notifier).state = false;
      await tester.pump();
      c.read(appForegroundProvider.notifier).state = true;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('match-alert')), findsOneWidget);
    });
  });
}
