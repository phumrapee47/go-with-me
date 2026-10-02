import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/core/l10n/strings_p4.dart';
import 'package:gowithme/core/l10n/strings_roles.dart';
import 'package:gowithme/core/l10n/strings_trip.dart';
import 'package:gowithme/demo/demo_data.dart';
import 'package:gowithme/demo/demo_fakes.dart';
import 'package:gowithme/demo/demo_hub_screen.dart';
import 'package:gowithme/demo/demo_overrides.dart';
import 'package:gowithme/features/geo/presentation/geo_providers.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/domain/trip_state_machine.dart';
import 'package:gowithme/features/trip/presentation/trip_lifecycle_providers.dart';
import 'package:gowithme/features/trip/presentation/unified_ride_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/p4_helpers.dart';
import '../support/ride_helpers.dart';

/// Wires the demo fakes exactly like demo_overrides does, without the UI.
({DemoTripRepository trips, DemoMatchRepository matches, DemoVehicleRepository vehicles}) _wire(
  DemoScenario s,
) {
  final trips = DemoTripRepository()..reset(s);
  final matches = DemoMatchRepository(trips)..reset(s);
  trips.hasBoardedRider = (id) =>
      matches.matches.any((m) => m.myTripId == id && m.iAmDriver && m.boarded && m.status == MatchStatus.accepted);
  final vehicles = DemoVehicleRepository(matches, trips)..reset(s);
  return (trips: trips, matches: matches, vehicles: vehicles);
}

V _ok<V>(Result<V> r) => r.when(ok: (v) => v, err: (f) => throw StateError('unexpected ${f.code}'));
String _err<V>(Result<V> r) => r.when(ok: (_) => throw StateError('expected an error'), err: (f) => f.code);

/// Tabs live in the shell route: they must be reached with `go`, not `push`.
Future<void> _goTab(WidgetTester tester, String path) async {
  final ctx = tester.element(find.byType(Scaffold).first);
  GoRouter.of(ctx).go(path);
  await _pumpFor(tester, const Duration(seconds: 1));
}

Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final steps = d.inMilliseconds ~/ 250;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  group('demo fakes enforce the same role rules as the backend', () {
    test('Driver scenario: riders only, accept closes the other requests, one companion, then no search', () async {
      final w = _wire(DemoScenario.driver);
      expect(_ok(await w.trips.activeTrip())!.role, TripRole.driver);
      final found = _ok(await w.matches.findMatches('demo-trip-me'));
      expect(found, isNotEmpty);
      expect(found.every((c) => c.role == TripRole.rider), isTrue);
      expect(found.every((c) => c.mode.name == 'car'), isTrue);

      // Two riders ask; the Driver accepts one: the other is closed neutrally.
      const me = 'demo-trip-me';
      final sent = _ok(await w.matches.request(myTripId: me, targetTripId: 'demo-cand-1'));
      expect(sent.status, MatchStatus.pending);
      final inbox0 = _ok(await w.matches.inbox());
      final incoming = inbox0.firstWhere((m) => m.isIncomingPending);
      expect(_ok(await w.matches.respond(incoming.id, accept: true)), MatchStatus.accepted);
      final inbox1 = _ok(await w.matches.inbox());
      final closed = inbox1.firstWhere((m) => m.id == sent.matchId);
      expect(closed.status, MatchStatus.cancelled);
      expect(closed.autoClosed, isTrue);
      // Second accept / new request: refused, and the trip leaves the search.
      expect(_err(await w.matches.request(myTripId: me, targetTripId: 'demo-cand-2')), 'GWM_NOT_ELIGIBLE');
      expect(_ok(await w.matches.findMatches(me)), isEmpty);
    });

    test('pickup: Driver proposes, Rider confirms; a Rider cannot open it; off-route is only a boolean', () async {
      final w = _wire(DemoScenario.rider);
      final pending = _ok(await w.matches.inbox()).single;
      expect(pending.iAmRider, isTrue);
      expect(_ok(await w.matches.respond(pending.id, accept: true)), MatchStatus.accepted);
      // Rider cannot start the pickup handshake.
      expect(_err(await w.matches.proposeMeetingPoint(pending.id, const LatLng(13.75, 100.53), 'x')),
          'GWM_PICKUP_DRIVER_FIRST');
      expect(w.matches.partnerProposesPickup(), isTrue);
      final withProposal = _ok(await w.matches.inbox()).single;
      expect(withProposal.hasProposalFromPartner, isTrue);
      // Counter-proposal far from the route: saved, boolean true.
      final beyond = _ok(await w.matches.proposeMeetingPoint(pending.id, const LatLng(13.75, 100.75), 'ไกล'));
      expect(beyond, isTrue);
      final near = _ok(await w.matches.proposeMeetingPoint(pending.id, const LatLng(13.7453, 100.5340), 'ใกล้'));
      expect(near, isFalse);
    });

    test('boarding needs both trips started; after boarding: no cancel, no no-show, Driver cannot cancel the trip',
        () async {
      // Rider view.
      final w = _wire(DemoScenario.rider);
      final m = _ok(await w.matches.inbox()).single;
      _ok(await w.matches.respond(m.id, accept: true));
      expect(_err(await w.matches.markBoarded(m.id)), 'GWM_TRIP_NOT_STARTED');
      _ok(await w.trips.transition('demo-trip-me', TripAction.start));
      expect(_err(await w.matches.markBoarded(m.id)), 'GWM_TRIP_NOT_STARTED', reason: 'Driver has not started');
      w.matches.partnerStartsTrip();
      final at = _ok(await w.matches.markBoarded(m.id));
      expect(_ok(await w.matches.markBoarded(m.id)), at, reason: 'idempotent: same timestamp');
      expect(_err(await w.matches.cancel(m.id)), 'GWM_ALREADY_BOARDED');
      expect(w.matches.partnerEndsMatch(), isFalse, reason: 'the other side cannot cancel after boarding either');
      // Boarded Rider still gets the vehicle; a match that ended before boarding would not.
      expect(_ok(await w.vehicles.forMatch(m.id)), isNotNull);

      // Driver view.
      final d = _wire(DemoScenario.driver);
      final dm = _ok(await d.matches.inbox()).single;
      _ok(await d.matches.respond(dm.id, accept: true));
      _ok(await d.trips.transition('demo-trip-me', TripAction.start));
      expect(d.matches.partnerBoards(), isTrue);
      expect(_err(await d.matches.reportRiderNoShow(dm.id)), 'GWM_ALREADY_BOARDED');
      expect(_err(await d.trips.transition('demo-trip-me', TripAction.cancel)), 'GWM_ALREADY_BOARDED');
      // Finishing ("ถึงแล้ว") is always allowed.
      expect(_ok(await d.trips.transition('demo-trip-me', TripAction.complete)).status, TripStatus.completed);
    });

    test('no-show: only the Driver, only while their trip runs and before boarding; ends neutrally', () async {
      final d = _wire(DemoScenario.driver);
      final m = _ok(await d.matches.inbox()).single;
      _ok(await d.matches.respond(m.id, accept: true));
      expect(_err(await d.matches.reportRiderNoShow(m.id)), 'GWM_NO_SHOW_NOT_ALLOWED', reason: 'trip not started');
      _ok(await d.trips.transition('demo-trip-me', TripAction.start));
      _ok(await d.matches.reportRiderNoShow(m.id));
      final after = _ok(await d.matches.inbox()).single;
      expect(after.status, MatchStatus.cancelled);
      expect(after.autoClosed, isFalse);
      expect(_ok(await d.vehicles.forMatch(m.id)), isNull);

      final r = _wire(DemoScenario.rider);
      final rm = _ok(await r.matches.inbox()).single;
      _ok(await r.matches.respond(rm.id, accept: true));
      _ok(await r.trips.transition('demo-trip-me', TripAction.start));
      expect(_err(await r.matches.reportRiderNoShow(rm.id)), 'GWM_NO_SHOW_NOT_ALLOWED', reason: 'Riders cannot report');
    });

    test('vehicle: Driver starts with one, consent off by default, cannot be deleted while driving; Rider sees the '
        'partner vehicle only when accepted', () async {
      final d = _wire(DemoScenario.driver);
      final v = _ok(await d.vehicles.mine())!;
      expect(v.shareConsent, isFalse);
      expect(_err(await d.vehicles.deleteMine()), 'GWM_VEHICLE_IN_USE');
      _ok(await d.vehicles.setShareConsent(true));
      expect(_ok(await d.vehicles.mine())!.shareConsent, isTrue);

      final r = _wire(DemoScenario.rider);
      expect(_ok(await r.vehicles.mine()), isNull, reason: 'the Rider scenario starts without a vehicle');
      final m = _ok(await r.matches.inbox()).single;
      expect(_ok(await r.vehicles.forMatch(m.id)), isNull, reason: 'pending: nothing');
      _ok(await r.matches.respond(m.id, accept: true));
      final view = _ok(await r.vehicles.forMatch(m.id))!;
      expect(view.shareAllowed, isFalse);
      r.vehicles.partnerShareAllowed.value = true;
      expect(_ok(await r.vehicles.forMatch(m.id))!.shareAllowed, isTrue);
    });

    test('peer scenario is untouched: transit trip, no roles, peer candidates', () async {
      final p = _wire(DemoScenario.peer);
      final t = _ok(await p.trips.activeTrip())!;
      expect(t.role, isNull);
      final found = _ok(await p.matches.findMatches(t.id));
      expect(found.every((c) => c.role == null), isTrue);
      final inbox = _ok(await p.matches.inbox());
      expect(inbox.every((m) => !m.isCar), isTrue);
    });
  });

  group('demo app: role flows are reachable from the hub', () {
    Future<Widget> boot(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late Widget app;
      await runDemoApp((w) => app = w, extraOverrides: [mapTilesEnabledProvider.overrideWithValue(false)]);
      await tester.pumpWidget(app);
      await _pumpFor(tester, const Duration(seconds: 4));
      return app;
    }

    Future<void> switchScenario(WidgetTester tester, DemoScenario s) async {
      await goTo(tester, demoHubPath);
      final tile = find.text('สลับเป็น: ${s.label}');
      await tester.scrollUntilVisible(tile, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(tile);
      await _pumpFor(tester, const Duration(seconds: 1));
    }

    testWidgets('hub has the round 6 stage C+D section; the deck works with demo data (swipe = invite, undo)',
        (tester) async {
      await boot(tester);
      await goTo(tester, demoHubPath);
      await tester.scrollUntilVisible(find.text('รอบ 6 (ขั้น C+D): การ์ดเพื่อนร่วมทาง สถานที่โปรด ทางลัดกลับบ้าน'), 300,
          scrollable: find.byType(Scrollable).first);
      await goBack(tester);
      await switchScenario(tester, DemoScenario.rider);
      await _goTab(tester, '/nearby');
      await _pumpFor(tester, const Duration(seconds: 5)); // the hub's toast covers the bottom otherwise
      await tester.tap(find.byKey(const Key('deck-invite')));
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.byKey(const Key('undo-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('undo-button')));
      await _pumpFor(tester, const Duration(milliseconds: 1200));
      expect(find.text('เลิกชวนแล้ว'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hub switches to Rider: nearby lists drivers with badge + seat chip and no vehicle data',
        (tester) async {
      await boot(tester);
      await switchScenario(tester, DemoScenario.rider);
      await _goTab(tester, '/nearby');
      // Round 6: the deck is the default view; the list is one tap away (Q4).
      expect(find.byKey(const Key('view-toggle')), findsOneWidget);
      expect(find.byKey(const Key('deck-invite')), findsOneWidget);
      await tester.tap(find.byKey(const Key('view-list')));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text(R.listForRider), findsOneWidget);
      expect(find.text(R.roleBadgeDriver), findsWidgets);
      expect(find.text(R.seatOne), findsWidgets);
      expect(find.textContaining('Honda'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rider story: accept -> vehicle card -> pickup -> start -> Driver starts -> board', (tester) async {
      await boot(tester);
      await switchScenario(tester, DemoScenario.rider);

      // Accept the incoming request (role-specific dialog first).
      await goTo(tester, '/nearby/requests');
      await _pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.text(T.accept));
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text(R.acceptTitleRider), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(R.acceptConfirm)));
      await _pumpFor(tester, const Duration(seconds: 2));

      // Match page: vehicle of the driver (only now), consent status, waiting for a pickup proposal.
      expect(find.byKey(const Key('vehicle-plate')), findsOneWidget);
      expect(find.text('ขข 5678 กรุงเทพมหานคร'), findsOneWidget);
      expect(find.byKey(const Key('consent-denied')), findsOneWidget);
      expect(find.text(R.pickupWaitDriver), findsOneWidget);

      // The Driver proposes a pickup (hub) and the Rider confirms.
      final c = containerOf(tester);
      c.read(demoMatchRepositoryProvider).partnerProposesPickup();
      await _pumpFor(tester, const Duration(seconds: 1));
      await tester.ensureVisible(find.byKey(const Key('pickup-confirm')));
      await tester.tap(find.byKey(const Key('pickup-confirm')));
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.textContaining('ตกลงจุดรับแล้ว'), findsOneWidget);

      // Start my trip: first-time notice for car trips, then the active page.
      await goTo(tester, _tripDetailPath);
      await _pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.text(P.startTrip));
      await _pumpFor(tester, const Duration(seconds: 1));
      if (find.text(P.noContactsTitle).evaluate().isNotEmpty) {
        await tester.tap(find.text(P.noContactsSkip));
        await _pumpFor(tester, const Duration(seconds: 1));
      }
      expect(find.text(R.consentSheetBody), findsOneWidget);
      await tester.tap(find.text(R.consentSheetOk));
      await _pumpFor(tester, const Duration(seconds: 3));
      // Round 6: the unified ride screen with the board slider.
      expect(find.byKey(sliderBoardKey), findsOneWidget);

      // "ขึ้นรถแล้ว" is off until the Driver starts.
      expect(find.text(R.boardDisabledDriver), findsOneWidget);
      c.read(demoMatchRepositoryProvider).partnerStartsTrip();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.byKey(const Key('slider-disabled-reason')), findsNothing);
      // No confirm dialog any more: sliding is the confirmation.
      await tester.drag(thumbOf(sliderBoardKey), const Offset(700, 0));
      await _pumpFor(tester, const Duration(seconds: 3));
      expect(find.byType(AlertDialog), findsNothing);
      await sheetTo(tester, SheetLevel.half);
      expect(find.byKey(const Key('boarded-done')), findsOneWidget);
      expect(find.byKey(const Key('board-location-stopped')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rider: the partner ends the match mid-trip -> the alert shows on the active page', (tester) async {
      await boot(tester);
      await switchScenario(tester, DemoScenario.rider);
      final c = containerOf(tester);
      final matches = c.read(demoMatchRepositoryProvider);
      // Fake latencies only advance while pumping, so fire and pump (no awaits).
      unawaited(matches.respond('demo-match-pending', accept: true));
      unawaited(c.read(tripActionsProvider).run('demo-trip-me', TripAction.start));
      await _pumpFor(tester, const Duration(seconds: 1));
      matches.partnerStartsTrip();
      await goTo(tester, '/trips/demo-trip-me/active');
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(find.byKey(const Key('match-alert')), findsNothing);

      expect(matches.partnerEndsMatch(), isTrue);
      await _pumpFor(tester, const Duration(seconds: 3));
      expect(find.byKey(const Key('match-alert')), findsOneWidget);
      expect(find.text(R.alertTitle), findsOneWidget);
    });

    testWidgets('Driver scenario: role badge on the trip, vehicle preview in the create flow, seat note',
        (tester) async {
      await boot(tester);
      await switchScenario(tester, DemoScenario.driver);
      await _goTab(tester, '/trips');
      expect(find.text(R.roleBadgeDriver), findsWidgets);
      expect(find.text('จับคู่แล้ว 0/1'), findsOneWidget);
      await goTo(tester, '/me/vehicle');
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.byKey(const Key('vehicle-plate')), findsOneWidget);
      final sw = find.byKey(const Key('share-consent-switch'));
      await tester.ensureVisible(sw);
      expect(tester.widget<SwitchListTile>(sw).value, isFalse, reason: 'default OFF');
      expect(tester.takeException(), isNull);
    });
  });
}

// The demo trip always has this id.
const _tripDetailPath = '/trips/demo-trip-me';
