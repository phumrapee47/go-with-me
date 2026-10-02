import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_dual.dart';
import 'package:gowithme/core/l10n/strings_trip.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/core/theme/tone.dart';
import 'package:gowithme/demo/demo_data.dart';
import 'package:gowithme/demo/demo_fakes.dart';
import 'package:gowithme/demo/demo_fakes_roles.dart';
import 'package:gowithme/demo/demo_hub_screen.dart';
import 'package:gowithme/demo/demo_overrides.dart';
import 'package:gowithme/features/geo/presentation/geo_providers.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/roles/domain/role_state.dart';
import 'package:gowithme/features/roles/presentation/role_providers.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/domain/trip_state_machine.dart';
import 'package:gowithme/features/trip/presentation/trip_providers.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/p4_helpers.dart';

({DemoTripRepository trips, DemoMatchRepository matches, DemoVehicleRepository vehicles, DemoRoleRepository roles}) _wire(
  DemoScenario s,
) {
  final trips = DemoTripRepository()..reset(s);
  final matches = DemoMatchRepository(trips)..reset(s);
  final vehicles = DemoVehicleRepository(matches, trips)..reset(s);
  final roles = DemoRoleRepository(vehicles, trips, matches)..reset(s);
  return (trips: trips, matches: matches, vehicles: vehicles, roles: roles);
}

V _ok<V>(Result<V> r) => r.when(ok: (v) => v, err: (f) => throw StateError('unexpected ${f.code}'));
String _err<V>(Result<V> r) => r.when(ok: (_) => throw StateError('expected an error'), err: (f) => f.code);

Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final steps = d.inMilliseconds ~/ 250;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _goTab(WidgetTester tester, String path) async {
  final ctx = tester.element(find.byType(Scaffold).first);
  GoRouter.of(ctx).go(path);
  await _pumpFor(tester, const Duration(seconds: 1));
}

void main() {
  group('demo role fakes follow the same rules as the server', () {
    test('Rider-only account: cannot switch to Driver, registers with a vehicle in one step, mode stays Rider', () async {
      final w = _wire(DemoScenario.rider);
      final s0 = _ok(await w.roles.getMyRoleState());
      expect(s0.registered, isFalse);
      expect(s0.activeRole, ActiveRole.rider);
      expect(_err(await w.roles.setActiveRole(ActiveRole.driver)), 'GWM_NOT_A_DRIVER');

      final s1 = _ok(await w.roles.registerDriver(
        plate: '1กก 1234',
        model: 'Toyota Yaris',
        colour: 'ขาว',
        declarationVersion: driverDeclarationVersion,
      ));
      expect(s1.registered, isTrue);
      expect(s1.hasVehicle, isTrue, reason: 'vehicle and registration are one step');
      expect(s1.activeRole, ActiveRole.rider, reason: 'registering never switches');
      expect(_ok(await w.roles.setActiveRole(ActiveRole.driver)).activeRole, ActiveRole.driver);
      expect(_ok(await w.roles.setActiveRole(ActiveRole.rider)).activeRole, ActiveRole.rider);
    });

    test('registration refuses a stale declaration and bad vehicle data', () async {
      final w = _wire(DemoScenario.rider);
      expect(
        _err(await w.roles.registerDriver(plate: 'a', model: 'b', colour: 'c', declarationVersion: 'old')),
        'GWM_DECLARATION_VERSION_STALE',
      );
      expect(
        _err(await w.roles.registerDriver(plate: ' ', model: 'b', colour: 'c', declarationVersion: driverDeclarationVersion)),
        'GWM_VEHICLE_INVALID',
      );
      expect(_ok(await w.roles.getMyRoleState()).registered, isFalse);
    });

    test('unregister is refused while a Driver trip is active, allowed after it ended; the vehicle is kept', () async {
      final w = _wire(DemoScenario.driver);
      expect(_ok(await w.roles.getMyRoleState()).activeRole, ActiveRole.driver);
      expect(_err(await w.roles.unregisterDriver()), 'GWM_DRIVER_ACTIVE_TRIP');
      expect(w.roles.registered, isTrue);

      _ok(await w.trips.transition('demo-trip-me', TripAction.cancel));
      final s = _ok(await w.roles.unregisterDriver());
      expect(s.registered, isFalse);
      expect(s.activeRole, ActiveRole.rider);
      expect(s.hasVehicle, isTrue, reason: 'kept, owner only');
    });

    test('unregister is refused while a Driver-side match is accepted', () async {
      final w = _wire(DemoScenario.driver);
      final incoming = _ok(await w.matches.inbox()).firstWhere((m) => m.isIncomingPending);
      expect(_ok(await w.matches.respond(incoming.id, accept: true)), MatchStatus.accepted);
      // With the trip still active the trip reason comes first ...
      expect(_err(await w.roles.unregisterDriver()), 'GWM_DRIVER_ACTIVE_TRIP');
      // ... and when only the accepted Driver-side match is left (the demo does not cascade a cancel to the
      // match), that is the reason.
      _ok(await w.trips.transition('demo-trip-me', TripAction.cancel));
      expect(w.matches.acceptedCar?.iAmDriver, isTrue);
      expect(_err(await w.roles.unregisterDriver()), 'GWM_DRIVER_ACTIVE_MATCH');
      expect(w.roles.registered, isTrue);
    });

    test('a registered account cannot delete its vehicle (GWM_DRIVER_REGISTERED); after unregistering it can', () async {
      final w = _wire(DemoScenario.peer);
      w.trips.clear();
      expect(w.roles.registered, isTrue);
      expect(_err(await w.vehicles.deleteMine()), 'GWM_DRIVER_REGISTERED');
      _ok(await w.roles.unregisterDriver());
      _ok(await w.vehicles.deleteMine());
      expect(w.vehicles.hasVehicle, isFalse);
    });

    test('hub switches: offline fails every call with a network failure; "elsewhere" drops the registration', () async {
      final w = _wire(DemoScenario.driver);
      w.roles.offline.value = true;
      expect(_err(await w.roles.getMyRoleState()), 'NETWORK_OFFLINE');
      expect(_err(await w.roles.setActiveRole(ActiveRole.rider)), 'NETWORK_OFFLINE');
      w.roles.offline.value = false;
      w.roles.unregisterElsewhere();
      final s = _ok(await w.roles.getMyRoleState());
      expect(s.registered, isFalse);
      expect(s.activeRole, ActiveRole.rider);
    });
  });

  group('demo app: Rider -> register -> offered switch -> switch -> Driver trip -> unregister', () {
    Future<ProviderContainer> boot(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late Widget app;
      await runDemoApp((w) => app = w, extraOverrides: [mapTilesEnabledProvider.overrideWithValue(false)]);
      await tester.pumpWidget(app);
      await _pumpFor(tester, const Duration(seconds: 4));
      return containerOf(tester);
    }

    ToneColors toneOf(WidgetTester t) => Theme.of(t.element(find.byKey(const Key('role-strip')))).extension<ToneColors>()!;

    testWidgets('the whole journey, on the demo fakes', (tester) async {
      final c = await boot(tester);
      // Start as a plain Rider (hub control), with no trip in the way.
      c.read(demoRoleRepositoryProvider).asRiderOnly();
      c.read(demoTripRepositoryProvider).clear();
      c.invalidate(activeTripProvider);
      unawaited(c.read(roleControllerProvider.notifier).refresh());
      await _goTab(tester, Routes.me);
      expect(toneOf(tester).isDriver, isFalse);
      expect(find.byKey(const Key('role-switch')), findsNothing, reason: 'unregistered: badge only');
      expect(find.byKey(const Key('driver-register-card')), findsOneWidget);

      // Register from the Me tab.
      await tester.ensureVisible(find.byKey(const Key('driver-card-cta')));
      await tester.tap(find.byKey(const Key('driver-card-cta')));
      await _pumpFor(tester, const Duration(seconds: 1));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '1กก 1234');
      await tester.enterText(fields.at(1), 'Toyota Yaris');
      await tester.enterText(fields.at(2), 'ขาว');
      await tester.ensureVisible(find.byKey(const Key('declaration-checkbox')));
      await tester.tap(find.byKey(const Key('declaration-checkbox')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('register-submit')));
      await tester.tap(find.byKey(const Key('register-submit')));
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.byKey(const Key('register-success')), findsOneWidget);
      expect(c.read(roleControllerProvider).active, ActiveRole.rider, reason: 'offered, not switched');

      // Take the offered switch.
      await tester.tap(find.byKey(const Key('success-switch')));
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(c.read(roleControllerProvider).active, ActiveRole.driver);
      expect(toneOf(tester).isDriver, isTrue);
      expect(find.byKey(const Key('my-roles-card')), findsOneWidget);

      // Create a Driver trip: the role defaults to the active mode.
      c.read(tripFormProvider.notifier)
        ..setOrigin(const Place(point: LatLng(13.7455, 100.5345), label: 'สยาม'))
        ..setDest(const Place(point: LatLng(13.9, 100.6), label: 'รังสิต'));
      unawaited(GoRouter.of(tester.element(find.byType(Scaffold).first)).push<void>(Routes.tripOptions));
      await _pumpFor(tester, const Duration(seconds: 1));
      await tester.ensureVisible(find.text(TravelMode.car.label));
      await tester.tap(find.text(TravelMode.car.label));
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(c.read(tripFormProvider).role, TripRole.driver);
      await _pumpFor(tester, const Duration(seconds: 5)); // let the switch snackbar go
      await tester.tap(find.text(S.next));
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(find.byKey(const Key('confirm-role-row')), findsOneWidget);
      await tester.tap(find.text(T.createTrip));
      await _pumpFor(tester, const Duration(seconds: 2));
      final trip = c.read(demoTripRepositoryProvider).active!;
      expect(trip.role, TripRole.driver);

      await _pumpFor(tester, const Duration(seconds: 5)); // let the "trip created" snackbar go
      // Unregister while that trip is active: refused with the reason, still registered.
      await _goTab(tester, Routes.me);
      await tester.ensureVisible(find.byKey(const Key('unregister-row')));
      await tester.tap(find.byKey(const Key('unregister-row')));
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.byKey(const Key('blocked-reason')), findsOneWidget);
      expect(find.text(D.blockedTrip), findsOneWidget);
      await tester.tap(find.byKey(const Key('blocked-close')));
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(c.read(roleControllerProvider).registered, isTrue);

      // The Driver trip is over: unregistering now works and the tone returns to Rider.
      unawaited(c.read(demoTripRepositoryProvider).transition(trip.id, TripAction.cancel));
      await _pumpFor(tester, const Duration(seconds: 1));
      c.invalidate(activeTripProvider);
      await _pumpFor(tester, const Duration(seconds: 1));
      await tester.ensureVisible(find.byKey(const Key('unregister-row')));
      await tester.tap(find.byKey(const Key('unregister-row')));
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.byKey(const Key('unregister-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('unregister-confirm')));
      await _pumpFor(tester, const Duration(seconds: 2));
      expect(c.read(roleControllerProvider).registered, isFalse);
      expect(toneOf(tester).isDriver, isFalse);
      expect(find.byKey(const Key('driver-register-card')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hub controls are reachable and drive both accounts', (tester) async {
      await boot(tester);
      await goTo(tester, demoHubPath);
      final riderOnly = find.text('บัญชี: คนนั่งล้วน (ยังไม่ลงทะเบียน)');
      await tester.scrollUntilVisible(riderOnly, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(riderOnly);
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(containerOf(tester).read(roleControllerProvider).registered, isFalse);
      // The other account and the registration page shortcut are on the hub too.
      final both = find.text('บัญชี: สองบทบาท (ลงทะเบียนแล้ว)');
      await tester.scrollUntilVisible(both, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(both);
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(containerOf(tester).read(roleControllerProvider).registered, isTrue);
      await tester.scrollUntilVisible(find.text(D.regTitle), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text(D.regTitle), findsOneWidget);
    });
  });
}
