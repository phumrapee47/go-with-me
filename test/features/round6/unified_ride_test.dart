import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings_p4.dart';
import 'package:gowithme/core/l10n/strings_r5.dart';
import 'package:gowithme/core/l10n/strings_r6.dart';
import 'package:gowithme/core/l10n/strings_roles.dart';
import 'package:gowithme/core/notify/local_notifier.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/chat/domain/chat_models.dart';
import 'package:gowithme/features/geo/domain/location_service.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/matching/presentation/matching_providers.dart';
import 'package:gowithme/features/safety/domain/safety_models.dart';
import 'package:gowithme/features/trip/domain/live_location.dart';
import 'package:gowithme/features/trip/domain/ride_logic.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/presentation/unified_ride_screen.dart';
import 'package:gowithme/features/vehicle/domain/vehicle.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';
import '../../support/ride_helpers.dart';

const _plateView = VehicleView(plate: 'ขข 5678', model: 'Honda City', color: 'เทา/เงิน', shareAllowed: true);
const _pickup = LatLng(13.75, 100.53);
const _phone = Size(390, 844);

Trip _car(TripRole role, {TripStatus status = TripStatus.inProgress}) =>
    sampleTrip(mode: TravelMode.car, role: role, status: status)
        .copyWith(startedAt: status == TripStatus.inProgress ? DateTime.now() : null);

MatchSummary _rider({DateTime? boarded, TripStatus partner = TripStatus.inProgress, bool pickup = true, MatchStatus status = MatchStatus.accepted}) {
  final m = sampleMatch(status: status, myRole: TripRole.rider, boardedAt: boarded, partnerTripStatus: partner, name: 'สมชาย');
  return pickup ? m.copyWith(meetingPoint: _pickup, meetingLabel: 'หน้าสถานี') : m;
}

MatchSummary _driver({DateTime? boarded, bool pickup = true, MatchStatus status = MatchStatus.accepted}) {
  final m = sampleMatch(status: status, myRole: TripRole.driver, boardedAt: boarded, name: 'มะปราง');
  return pickup ? m.copyWith(meetingPoint: _pickup, meetingLabel: 'หน้าสถานี') : m;
}

Fakes _base({required Trip trip, List<MatchSummary> matches = const []}) {
  final f = Fakes()
    ..vehicles.view = _plateView
    ..vehicles.vehicle = const Vehicle(plate: 'ก', model: 'm', color: 'c')
    ..trips.active = trip
    ..matches.matches = matches;
  f.location.state = LocationPermissionState.granted;
  f.contacts.items.add(const EmergencyContact(id: 'c1', name: 'แม่', phone: '0812345678'));
  return f;
}

LocationFix _fixAt(LatLng p) => LocationFix(point: p, at: DateTime.now(), accuracyM: 8);
LatLng _north(LatLng p, double metres) => LatLng(p.latitude + metres / 111194.9, p.longitude);

Finder get _sos => find.byKey(const Key('ride-sos'));

void main() {
  group('SOS at every sheet level (US-30, P-8, P-10)', () {
    for (final level in SheetLevel.values) {
      testWidgets('Rider on the way, sheet ${level.name}: SOS is visible, tappable, not covered, opens in 1 tap', (tester) async {
        final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
        await openApp(tester, f, size: _phone);
        await goTo(tester, Routes.tripActive('trip-1'));
        await sheetTo(tester, level);

        expect(_sos, findsOneWidget);
        expect(_sos.hitTestable(), findsOneWidget, reason: 'nothing (sheet, slider, keyboard) covers it');
        final r = tester.getRect(_sos);
        expect(r.height, greaterThanOrEqualTo(48), reason: 'tap target is not smaller than before');
        expect(r.right, lessThanOrEqualTo(_phone.width));
        expect(r.top, lessThan(120), reason: 'fixed at the top edge, independent of the sheet height');

        await tester.tap(_sos);
        await tester.pumpAndSettle();
        expect(find.text(P.sosTitle), findsOneWidget, reason: 'one tap opens the SOS screen (with its own confirm step)');
      });
    }

    testWidgets('its position does not move when the sheet moves', (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.collapsed);
      final a = tester.getRect(_sos);
      await sheetTo(tester, SheetLevel.full);
      expect(tester.getRect(_sos), a);
    });

    testWidgets('present from the scheduled state, both roles, and after boarding; gone once arrived', (tester) async {
      for (final (trip, matches) in [
        (_car(TripRole.driver, status: TripStatus.scheduled), [_driver()]),
        (_car(TripRole.rider, status: TripStatus.scheduled), [_rider(partner: TripStatus.scheduled)]),
        (_car(TripRole.rider), [_rider(boarded: DateTime.now())]),
        (_car(TripRole.driver), [_driver(boarded: DateTime.now())]),
        (sampleTrip(status: TripStatus.inProgress), <MatchSummary>[]),
      ]) {
        final f = _base(trip: trip, matches: matches);
        await openApp(tester, f, size: _phone);
        await goTo(tester, Routes.tripActive('trip-1'));
        expect(_sos.hitTestable(), findsOneWidget, reason: '${trip.role} ${trip.status}');
        await tester.pumpWidget(const SizedBox());
      }
      // arrived: my own trip is over, no floating SOS (the Safety tab still has it)
      final f = _base(trip: sampleTrip(), matches: []);
      f.trips.active = null;
      f.trips.finished.add(sampleTrip().copyWith(status: TripStatus.completed, startedAt: DateTime.now(), endedAt: DateTime.now()));
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripArrived('trip-1'));
      expect(_sos, findsNothing);
    });

    testWidgets('text scale 2.0 on a 390 px screen: SOS and slider are not clipped or covered', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      for (final level in SheetLevel.values) {
        await sheetTo(tester, level);
        expect(tester.takeException(), isNull, reason: level.name);
        expect(_sos.hitTestable(), findsOneWidget, reason: level.name);
        final r = tester.getRect(_sos);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(_phone.width));
      }
      await sheetTo(tester, SheetLevel.collapsed);
      expect(find.byKey(sliderBoardKey).hitTestable(), findsOneWidget, reason: 'the slider is reachable at Collapsed');
    });

    testWidgets('keyboard open in the Full chat: SOS still on top and tappable', (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.full);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(_sos.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('routes (US-41)', () {
    testWidgets('/trips/active, the old /trips/:id/active and /matches/:id/live all open the unified screen', (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActiveNow);
      expect(find.byType(UnifiedRideScreen), findsOneWidget);
      await goBack(tester);

      await goTo(tester, '/trips/trip-1/active'); // old deep link
      expect(find.byType(UnifiedRideScreen), findsOneWidget);
      await goBack(tester);

      await goTo(tester, Routes.live('m1'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(UnifiedRideScreen), findsOneWidget);
      expect(find.byKey(const Key('ctl-follow')), findsOneWidget, reason: 'map controls are there');
    });

    testWidgets('/matches/:id/live keeps the old guard: not accepted -> back to the match page with a neutral message',
        (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider(status: MatchStatus.pending)]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.live('m1'));
      await tester.pumpAndSettle();
      expect(find.text(R5.liveUnavailable), findsOneWidget);
      expect(find.byType(UnifiedRideScreen), findsNothing);
    });

    testWidgets('no active trip: a calm empty state with a way home (not an error)', (tester) async {
      final f = Fakes();
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActiveNow);
      expect(find.text(R6.tripNotFound), findsOneWidget);
      await tester.tap(find.text(P.backHome));
      await tester.pumpAndSettle();
      expect(find.byType(UnifiedRideScreen), findsNothing);
    });

    testWidgets('/trips/:id/arrived aliases the Arrived state: summary, no slider, no floating SOS', (tester) async {
      final f = Fakes();
      f.trips.finished.add(sampleTrip().copyWith(status: TripStatus.completed, startedAt: DateTime.now(), endedAt: DateTime.now()));
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripArrived('trip-1'));
      expect(find.byType(UnifiedRideScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('slider-arrive')), findsNothing);
      expect(find.text(R6.arrivedDest), findsOneWidget);
      expect(find.text(P.arrivedBody), findsOneWidget);
      expect(find.byKey(const Key('ride-level-half')), findsOneWidget, reason: 'Arrived opens at Half');
    });
  });

  group('sheet (F-2)', () {
    testWidgets('three levels: the handle cycles, content appears level by level and Collapsed hides the rest', (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      // in progress starts Collapsed: peer row + primary slider only
      expect(find.byKey(const Key('ride-level-collapsed')), findsOneWidget);
      expect(find.byKey(sliderBoardKey), findsOneWidget);
      expect(find.byKey(const Key('quick-chips')), findsNothing);
      expect(find.byKey(const Key('ride-chat-input')), findsNothing);

      await sheetTo(tester, SheetLevel.half);
      expect(find.byKey(const Key('quick-chips')), findsOneWidget);
      expect(find.byKey(const Key('vehicle-compact-line')), findsOneWidget);
      expect(find.byKey(const Key('ride-chat-input')), findsNothing, reason: 'chat lives in Full');

      await sheetTo(tester, SheetLevel.full);
      expect(find.byKey(const Key('ride-chat-input')), findsOneWidget);
      expect(find.byKey(const Key('ride-share')), findsOneWidget);
      expect(find.byKey(const Key('ride-sos-tile')), findsOneWidget);

      await sheetTo(tester, SheetLevel.collapsed);
      expect(find.byKey(const Key('ride-chat-input')), findsNothing);
    });

    testWidgets('default level per state: scheduled = Half, on the way = Collapsed', (tester) async {
      var f = _base(trip: _car(TripRole.driver, status: TripStatus.scheduled), matches: [_driver()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.byKey(const Key('ride-level-half')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      f = _base(trip: _car(TripRole.driver), matches: [_driver()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.byKey(const Key('ride-level-collapsed')), findsOneWidget);
    });

    testWidgets('the system back button steps Full -> Half -> Collapsed before leaving', (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.full);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ride-level-half')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ride-level-collapsed')), findsOneWidget);
      expect(find.byType(UnifiedRideScreen), findsOneWidget);
    });

    testWidgets('the level survives rotating the screen', (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ride-level-half')), findsOneWidget);
      expect(_sos.hitTestable(), findsOneWidget);
    });

    testWidgets('dragging the sheet up snaps to a level (touch, not only the handle)', (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await tester.fling(find.byKey(const Key('ride-sheet-handle')), const Offset(0, -400), 1500);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ride-level-collapsed')), findsNothing);
      expect(_sos.hitTestable(), findsOneWidget);
    });

    testWidgets('semantics: the handle is a button "แผ่นข้อมูลการเดินทาง" with the level and expand/collapse actions',
        (tester) async {
      final h = tester.ensureSemantics();
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      final node = tester.getSemantics(find.byKey(const Key('ride-sheet-handle')));
      expect(node.label, R6.sheetLabel);
      expect(node.value, R6.sheetLevelCollapsed);
      expect(node, isSemantics(isButton: true));
      final expand = CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: R6.sheetExpand));
      expect(node.getSemanticsData().customSemanticsActionIds, contains(expand));
      h.dispose();
    });
  });

  group('role x state matrix (F.3.4)', () {
    testWidgets('Rider, scheduled: the start slider, no board slider, no pickup button', (tester) async {
      final f = _base(trip: _car(TripRole.rider, status: TripStatus.scheduled), matches: [_rider(partner: TripStatus.scheduled)]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.byKey(sliderStartKey), findsOneWidget);
      expect(find.text(R6.sliderStart), findsOneWidget);
      expect(find.byKey(sliderBoardKey), findsNothing);
      expect(find.byKey(sliderArriveKey), findsNothing);
      expect(find.byKey(const Key('arrived-at-pickup')), findsNothing);
    });

    testWidgets('Driver, scheduled: the start slider, no "arrived at pickup" yet', (tester) async {
      final f = _base(trip: _car(TripRole.driver, status: TripStatus.scheduled), matches: [_driver()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.byKey(sliderStartKey), findsOneWidget);
      expect(find.byKey(const Key('arrived-at-pickup')), findsNothing);
    });

    testWidgets('Rider on the way: board slider is primary; arrive slider is reachable at Half; vehicle only for the Rider',
        (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.byKey(sliderBoardKey), findsOneWidget);
      expect(find.byKey(sliderArriveKey), findsNothing);
      expect(find.byKey(const Key('arrived-at-pickup')), findsNothing, reason: 'Driver-only');
      await sheetTo(tester, SheetLevel.half);
      expect(find.byKey(sliderArriveKey), findsOneWidget);
      expect(find.textContaining('5678'), findsOneWidget, reason: 'the accepted Rider sees the plate (US-17)');
      expect(find.text(R.boardShareNote), findsOneWidget);
    });

    testWidgets('Driver on the way: "arrived at pickup" is primary, no board slider, NO plate of the own car shown as a partner',
        (tester) async {
      final f = _base(trip: _car(TripRole.driver), matches: [_driver()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.byKey(const Key('arrived-at-pickup')), findsOneWidget);
      expect(find.byKey(sliderBoardKey), findsNothing);
      await sheetTo(tester, SheetLevel.half);
      expect(find.byKey(sliderArriveKey), findsOneWidget, reason: 'arrive is always reachable (US-12)');
      expect(find.textContaining('5678'), findsNothing);
      expect(find.byKey(const Key('vehicle-compact-line')), findsNothing);
      expect(find.text(R.driverStatusWaiting), findsWidgets);
    });

    testWidgets('boarded Rider: arrive slider only, the "location stopped" explanation, Driver text for the Driver',
        (tester) async {
      var f = _base(trip: _car(TripRole.rider), matches: [_rider(boarded: DateTime.now())]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.byKey(sliderArriveKey), findsOneWidget);
      expect(find.byKey(sliderBoardKey), findsNothing);
      expect(find.text(R5.liveStatusTogether), findsOneWidget);
      await sheetTo(tester, SheetLevel.half);
      expect(find.byKey(const Key('board-location-stopped')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      f = _base(trip: _car(TripRole.driver), matches: [_driver(boarded: DateTime.now())]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.byKey(sliderArriveKey), findsOneWidget);
      expect(find.byKey(const Key('arrived-at-pickup')), findsNothing, reason: 'hidden once the Rider boarded');
      expect(find.text(R5.liveRiderBoarded), findsOneWidget);
      await sheetTo(tester, SheetLevel.half);
      expect(find.text(R.riderInCar), findsOneWidget);
    });

    testWidgets('trip without a partner (solo / Peer): no partner row, no chat, no vehicle, and no error', (tester) async {
      final f = _base(trip: sampleTrip(status: TripStatus.inProgress).copyWith(startedAt: DateTime.now()));
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.text(R6.soloTitle), findsOneWidget);
      expect(find.byKey(const Key('live-chat')), findsNothing);
      expect(find.byKey(sliderArriveKey), findsOneWidget);
      await sheetTo(tester, SheetLevel.full);
      expect(find.byKey(const Key('ride-chat-input')), findsNothing);
      expect(find.byKey(const Key('vehicle-compact-line')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('partner ended the match (Driver side): neutral text, arrive slider stays, SOS stays, peer chat is gone', (tester) async {
      final f = _base(trip: _car(TripRole.driver), matches: [_driver(status: MatchStatus.cancelled)]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.byKey(const Key('live-chat')), findsNothing, reason: 'the partner icon/chat go away at once');
      expect(find.byKey(sliderArriveKey), findsOneWidget);
      expect(_sos.hitTestable(), findsOneWidget);
      await sheetTo(tester, SheetLevel.half);
      expect(find.text(R.endedDriverSide), findsOneWidget);
    });

    testWidgets('the Driver never gets the Rider destination or coordinates on this screen', (tester) async {
      final f = _base(trip: _car(TripRole.driver), matches: [_driver()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.full);
      // Only MY origin/destination rows exist; no coordinate text anywhere.
      expect(find.text('รังสิต'), findsOneWidget);
      expect(find.textContaining('13.9'), findsNothing);
      expect(find.textContaining('100.6'), findsNothing);
    });
  });

  group('routine status changes use the slider (US-31)', () {
    testWidgets('start: sliding starts the trip once, no confirm dialog, then the arrive slider takes over', (tester) async {
      final f = _base(trip: sampleTrip());
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await dragSlider(tester, sliderStartKey, dx: 50); // early release: nothing
      expect(f.trips.transitions, isEmpty);
      await dragSlider(tester, sliderStartKey);
      expect(f.trips.transitions.single.$2.name, 'start');
      expect(find.byType(AlertDialog), findsNothing);
      expect(f.trips.active!.status, TripStatus.inProgress);
      expect(find.byKey(sliderArriveKey), findsOneWidget);
    });

    testWidgets('start: choosing "set up contacts now" in the nudge starts nothing and leaves the slider calm', (tester) async {
      final f = Fakes()..trips.active = sampleTrip();
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await dragSlider(tester, sliderStartKey, settle: false);
      // the slider spins while the flow waits for the user, so pump by time instead of settling
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(P.noContactsTitle), findsOneWidget, reason: 'prerequisite dialogs stay');
      await tester.tap(find.text(P.noContactsSetup));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text(P.contactsAdd), findsOneWidget);
      expect(f.trips.transitions, isEmpty);
      await goBack(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slider-error')), findsNothing);
    });

    testWidgets('start failure: the flow tells why (snackbar) and the trip stays scheduled', (tester) async {
      final f = _base(trip: sampleTrip());
      f.trips.transitionFailure = const AppFailure('GWM_INVALID_TRIP_TRANSITION');
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await dragSlider(tester, sliderStartKey);
      expect(find.text('ตอนนี้เปลี่ยนสถานะทริปนี้ไม่ได้'), findsOneWidget);
      expect(f.trips.active!.status, TripStatus.scheduled);
    });

    testWidgets('routine changes never used on SOS / cancel: those keep their dialogs', (tester) async {
      final f = _base(trip: _car(TripRole.driver, status: TripStatus.scheduled), matches: [_driver()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.full);
      await tester.dragUntilVisible(
        find.byKey(const Key('ride-cancel-trip')),
        find.byKey(const Key('ride-sheet')),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ride-cancel-trip')));
      await tester.pumpAndSettle();
      expect(find.text(P.cancelTripTitle), findsOneWidget, reason: 'cancel keeps the confirm dialog');
      expect(f.trips.transitions, isEmpty);
    });
  });

  group('arrival wording (Q5)', () {
    testWidgets('unknown Home (stage D not built): generic label and generic sentence, with an emoji-free screen-reader text',
        (tester) async {
      final h = tester.ensureSemantics();
      final f = _base(trip: sampleTrip(status: TripStatus.inProgress).copyWith(startedAt: DateTime.now()));
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.text(R6.sliderArriveDest), findsOneWidget);
      expect(find.text(R6.sliderArriveHome), findsNothing);
      await dragSlider(tester, sliderArriveKey);
      expect(find.text(R6.arrivedDest), findsOneWidget);
      expect(find.text(R6.arrivedHome), findsNothing);
      expect(find.bySemanticsLabel(R6.arrivedDestSemantics), findsOneWidget);
      h.dispose();
    });

    testWidgets('destination = saved Home: "home" label and sentence', (tester) async {
      final h = tester.ensureSemantics();
      final f = _base(trip: sampleTrip(status: TripStatus.inProgress).copyWith(startedAt: DateTime.now()));
      f.overrides.add(homeDestinationMatcherProvider.overrideWithValue(_Matcher(HomeMatch.home)));
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.text(R6.sliderArriveHome), findsOneWidget);
      expect(find.text(R6.sliderArriveDest), findsNothing);
      await dragSlider(tester, sliderArriveKey);
      expect(find.text(R6.arrivedHome), findsOneWidget);
      expect(find.bySemanticsLabel(R6.arrivedHomeSemantics), findsOneWidget);
      h.dispose();
    });

    testWidgets('a destination that is NOT Home keeps the generic wording', (tester) async {
      final f = _base(trip: sampleTrip(status: TripStatus.inProgress).copyWith(startedAt: DateTime.now()));
      f.overrides.add(homeDestinationMatcherProvider.overrideWithValue(_Matcher(HomeMatch.notHome)));
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.text(R6.sliderArriveDest), findsOneWidget);
    });
  });

  group('geofence highlight on the slider (US-32)', () {
    testWidgets('board slider: 149 m from the agreed pickup highlights, 151 m does not; the slider works either way', (tester) async {
      var f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      f.location.fixes.add(_fixAt(_north(_pickup, 151)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slider-near')), findsNothing);
      await tester.pumpWidget(const SizedBox());

      f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      f.location.fixes.add(_fixAt(_north(_pickup, 149)));
      await tester.pumpAndSettle();
      expect(find.text(R6.sliderNearPickup), findsOneWidget);
      expect(f.matches.boarded, isEmpty, reason: 'highlight only: nothing happens by itself');
    });

    testWidgets('arrive slider uses MY destination: 149 m yes / 150 m no; no location permission = no highlight and no error',
        (tester) async {
      final trip = sampleTrip(status: TripStatus.inProgress).copyWith(startedAt: DateTime.now());
      var f = _base(trip: trip);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      f.location.fixes.add(_fixAt(_north(trip.dest, 149)));
      await tester.pumpAndSettle();
      expect(find.text(R6.sliderNearDest), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      f = _base(trip: trip);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      f.location.fixes.add(_fixAt(_north(trip.dest, 150.5)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slider-near')), findsNothing);
      await tester.pumpWidget(const SizedBox());

      f = _base(trip: trip);
      f.consent.locationGranted = false;
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      f.location.fixes.add(_fixAt(_north(trip.dest, 20)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slider-near')), findsNothing, reason: 'no permission: nothing highlighted');
      expect(find.byKey(const Key('slider-error')), findsNothing);
    });
  });

  group('Driver "arrived at pickup" (US-33)', () {
    testWidgets('one tap sends the ready-made sentence through the chat, then a 60 s cooldown; nothing else is attached',
        (tester) async {
      final f = _base(trip: _car(TripRole.driver), matches: [_driver()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      final btn = find.byKey(const Key('arrived-at-pickup'));
      expect(find.text(R6.arrivedAtPickupButton), findsOneWidget);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(f.chat.sent, hasLength(1));
      expect(f.chat.sent.single.$1, 'm1');
      expect(f.chat.sent.single.$2, 'คนขับมารอที่จุดรับแล้วนะ', reason: 'exactly the fixed sentence, no coordinates, no destination');
      expect(find.text(R6.arrivedAtPickupSent), findsOneWidget);
      expect(find.textContaining('ส่งซ้ำได้ใน'), findsOneWidget);
      expect(find.byKey(const Key('arrived-at-pickup')), findsOneWidget);
      // a second tap inside the minute is not sent (button is disabled)
      await tester.tap(btn, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(f.chat.sent, hasLength(1));
      expect(f.trips.transitions, isEmpty, reason: 'no new trip state');
    });

    testWidgets('after the cooldown it is available again', (tester) async {
      var now = DateTime(2026, 1, 1, 18);
      final f = _base(trip: _car(TripRole.driver), matches: [_driver()]);
      f.overrides.add(refreshClockProvider.overrideWithValue(() => now));
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await tester.tap(find.byKey(const Key('arrived-at-pickup')));
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 6));
      expect(find.textContaining('ส่งซ้ำได้ใน 30'), findsOneWidget);
      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 6)); // the 5 s screen clock refreshes the button
      expect(find.text(R6.arrivedAtPickupButton), findsOneWidget);
      await tester.tap(find.byKey(const Key('arrived-at-pickup')));
      await tester.pumpAndSettle();
      expect(f.chat.sent, hasLength(2));
    });

    testWidgets('a failed send says so and can be retried at once', (tester) async {
      final f = _base(trip: _car(TripRole.driver), matches: [_driver()]);
      f.chat.sendFailure = const AppFailure(FailureCode.networkOffline, retryable: true);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await tester.tap(find.byKey(const Key('arrived-at-pickup')));
      await tester.pumpAndSettle();
      expect(find.text(R6.arrivedAtPickupFailed), findsOneWidget);
      f.chat.sendFailure = null;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle(); // snackbar gone
      await tester.tap(find.byKey(const Key('arrived-at-pickup')));
      await tester.pumpAndSettle();
      expect(f.chat.sent, hasLength(2));
      expect(find.text(R6.arrivedAtPickupSent), findsOneWidget);
    });

    testWidgets('no agreed pickup: disabled with a visible reason; nothing is sent', (tester) async {
      final f = _base(trip: _car(TripRole.driver), matches: [_driver(pickup: false)]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.text(R6.arrivedAtPickupNoPoint), findsOneWidget);
      await tester.tap(find.byKey(const Key('arrived-at-pickup')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(f.chat.sent, isEmpty);
    });

    testWidgets('semantics: a button named "แจ้งคนนั่งว่าถึงจุดรับแล้ว"', (tester) async {
      final h = tester.ensureSemantics();
      final f = _base(trip: _car(TripRole.driver), matches: [_driver()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      expect(find.bySemanticsLabel(R6.arrivedAtPickupSemantics), findsOneWidget);
      h.dispose();
    });

    testWidgets('Rider side: the sentence in the chat becomes the status line + one local notification with a fixed text',
        (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()])
        ..live.partner = PartnerLocation(point: const LatLng(13.748, 100.532), recordedAt: DateTime.now());
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(R5.liveStatusComingToYou), findsOneWidget);
      f.chat.push(ChatMessage(
        id: 'srv-x',
        matchId: 'm1',
        senderId: 'driver-user',
        body: R6.arrivedAtPickupMessage,
        createdAt: DateTime.now(),
      ));
      await tester.pumpAndSettle();
      expect(find.text(R6.driverArrivedStatus), findsOneWidget);
      expect(f.notifier.shown.where((n) => n.kind == LocalNoticeKind.driverArrivedAtPickup), hasLength(1));
      final n = f.notifier.shown.singleWhere((n) => n.kind == LocalNoticeKind.driverArrivedAtPickup);
      expect(n.body, R6.arrivedAtPickupMessage);
      expect(n.title, isNot(contains('สมชาย')), reason: 'no name, plate or location in a notification');
      // pumping again does not notify twice
      await tester.pump(const Duration(seconds: 6));
      expect(f.notifier.shown.where((n) => n.kind == LocalNoticeKind.driverArrivedAtPickup), hasLength(1));
    });
  });

  group('chat in the Full sheet and quick replies', () {
    testWidgets('the typed text survives changing the level; a quick reply fills the box, opens Full, sends nothing', (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.half);
      // below the fold at Half: dragging the sheet up first expands it (DraggableScrollableSheet behaviour)
      await tester.dragUntilVisible(
        find.byKey(Key('quick-${R5.quickReplies.first}')),
        find.byKey(const Key('ride-sheet')),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('quick-${R5.quickReplies.first}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ride-level-full')), findsOneWidget);
      expect(find.widgetWithText(TextField, R5.quickReplies.first), findsOneWidget);
      expect(f.chat.sent, isEmpty, reason: 'never auto-sent');

      await tester.enterText(find.byKey(const Key('ride-chat-input')), 'ถึงแล้วนะ');
      await sheetTo(tester, SheetLevel.collapsed);
      await sheetTo(tester, SheetLevel.full);
      expect(find.widgetWithText(TextField, 'ถึงแล้วนะ'), findsOneWidget, reason: 'half-typed message is not lost');

      await tester.dragUntilVisible(find.byKey(const Key('ride-chat-send')), find.byKey(const Key('ride-sheet')), const Offset(0, -150));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ride-chat-send')));
      await tester.pumpAndSettle();
      expect(f.chat.sent.single.$2, 'ถึงแล้วนะ');
    });

    testWidgets('a blocked / closed chat is a read-only banner, never a composer', (tester) async {
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      f.chat.chatState = ChatState.blocked;
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await sheetTo(tester, SheetLevel.full);
      expect(find.byKey(const Key('ride-chat-readonly')), findsOneWidget);
      expect(find.byKey(const Key('ride-chat-input')), findsNothing);
    });
  });

  group('layout: 390 px, text scale 1.0 / 1.4 / 2.0, every level', () {
    for (final scale in [1.0, 1.4, 2.0]) {
      testWidgets('Rider and Driver at scale $scale: nothing overflows', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        for (final (trip, matches) in [
          (_car(TripRole.rider), [_rider()]),
          (_car(TripRole.driver), [_driver()]),
        ]) {
          final f = _base(trip: trip, matches: matches);
          f.location.fixes.add(_fixAt(_north(_pickup, 100)));
          await openApp(tester, f, size: _phone);
          await goTo(tester, Routes.tripActive('trip-1'));
          for (final level in [SheetLevel.collapsed, SheetLevel.half, SheetLevel.full]) {
            await sheetTo(tester, level);
            expect(tester.takeException(), isNull, reason: '${trip.role} $scale ${level.name}');
          }
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  });

  group('reduce motion', () {
    testWidgets('the sheet jumps without animation and the slider still works', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final f = _base(trip: _car(TripRole.rider), matches: [_rider()]);
      await openApp(tester, f, size: _phone);
      await goTo(tester, Routes.tripActive('trip-1'));
      await tester.tap(find.byKey(const Key('ride-sheet-handle')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('ride-level-half')), findsOneWidget);
      await sheetTo(tester, SheetLevel.collapsed);
      await dragSlider(tester, sliderBoardKey);
      expect(f.matches.boarded, ['m1']);
    });
  });

  test('unused import guard', () {
    expect(GoRouter, isNotNull);
    expect(unawaited, isNotNull);
  });
}

class _Matcher implements HomeDestinationMatcher {
  _Matcher(this.result);
  final HomeMatch result;
  @override
  HomeMatch match(Trip trip) => result;
}
