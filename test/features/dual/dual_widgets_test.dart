import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_dual.dart';
import 'package:gowithme/core/l10n/strings_roles.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/core/theme/tokens.dart';
import 'package:gowithme/core/theme/tone.dart';
import 'package:gowithme/core/widgets/app_button.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/roles/domain/role_state.dart';
import 'package:gowithme/features/roles/presentation/role_providers.dart';
import 'package:gowithme/features/safety/presentation/sos_widgets.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/presentation/trip_providers.dart';
import 'package:gowithme/features/vehicle/domain/vehicle.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';

const _siam = Place(point: LatLng(13.7455, 100.5345), label: 'สยาม');
const _rangsit = Place(point: LatLng(13.9, 100.6), label: 'รังสิต');
const _navy = Color(0xFF0B1B33);

ToneColors _toneAt(WidgetTester t, Finder f) => Theme.of(t.element(f)).extension<ToneColors>()!;

Future<Fakes> _open(WidgetTester tester, {bool registered = true, ActiveRole active = ActiveRole.rider, Size? size}) async {
  final f = Fakes();
  f.roles
    ..registered = registered
    ..active = registered ? active : ActiveRole.rider;
  await openApp(tester, f, size: size ?? const Size(800, 2000));
  return f;
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _toStep2(WidgetTester tester) async {
  containerOf(tester).read(tripFormProvider.notifier)
    ..setOrigin(_siam)
    ..setDest(_rangsit);
  await goTo(tester, Routes.tripOptions);
}

Future<void> _pickCar(WidgetTester tester) async {
  await tester.ensureVisible(find.text(TravelMode.car.label));
  await tester.tap(find.text(TravelMode.car.label));
  await tester.pumpAndSettle();
}

void main() {
  group('role strip + 1-tap switch (US-20)', () {
    testWidgets('registered Rider: Home capsule shows both roles, rider selected; one tap changes the tone', (tester) async {
      // Home tab (round 9 RC-6): the app-wide `role-strip`/`role-switch` was replaced here by
      // the floating `_RoleSwitchCapsule` (keys `home-role-capsule-driver`/`-rider`) — the strip
      // itself is unchanged and still covered by the other 4 tabs below.
      final f = await _open(tester);
      expect(find.byKey(const Key('home-role-capsule-driver')), findsOneWidget);
      expect(find.byKey(const Key('home-role-capsule-rider')), findsOneWidget);
      expect(_toneAt(tester, find.byKey(const Key('home-role-capsule-rider'))).isDriver, isFalse);

      await tester.tap(find.byKey(const Key('home-role-capsule-driver')));
      await tester.pumpAndSettle();
      expect(f.roles.switchCalls, [ActiveRole.driver], reason: 'exactly one call, no confirmation step');
      expect(_toneAt(tester, find.byKey(const Key('home-role-capsule-driver'))).isDriver, isTrue);
      expect(Theme.of(tester.element(find.byKey(const Key('home-role-capsule-driver')))).scaffoldBackgroundColor, _navy);
      expect(find.text(D.switchedDriver), findsOneWidget, reason: 'snackbar: applies to new trips only');
    });

    testWidgets('switching back to Rider is one tap too and needs no confirmation (Home capsule)', (tester) async {
      final f = await _open(tester, active: ActiveRole.driver);
      expect(_toneAt(tester, find.byKey(const Key('home-role-capsule-driver'))).isDriver, isTrue);
      await tester.tap(find.byKey(const Key('home-role-capsule-rider')));
      await tester.pumpAndSettle();
      expect(f.roles.switchCalls, [ActiveRole.rider]);
      expect(_toneAt(tester, find.byKey(const Key('home-role-capsule-rider'))).isDriver, isFalse);
      expect(find.text(D.switchedRider), findsOneWidget);
    });

    testWidgets('the strip is on the other 4 shell tabs (Home has the capsule instead) and a failed switch leaves the tone alone', (tester) async {
      final f = await _open(tester);
      expect(find.byKey(const Key('home-role-capsule-driver')), findsOneWidget, reason: S.tabHome);
      expect(find.byKey(const Key('home-role-capsule-rider')), findsOneWidget, reason: S.tabHome);
      for (final tab in [S.tabNearby, S.tabChats, S.tabTrips, S.tabMe]) {
        await _tapTab(tester, tab);
        expect(find.byKey(const Key('role-strip')), findsOneWidget, reason: tab);
      }
      f.roles.failNextSwitch = const AppFailure(FailureCode.networkOffline, retryable: true);
      await tester.tap(find.byKey(const Key('role-switch')));
      await tester.pumpAndSettle();
      expect(find.text(D.errOfflineDriver), findsOneWidget);
      expect(_toneAt(tester, find.byKey(const Key('role-strip'))).isDriver, isFalse);
      expect(find.byKey(const Key('mode-badge-rider')), findsOneWidget);

      f.roles.failNextSwitch = const AppFailure('GWM_RATE_LIMITED');
      await tester.tap(find.byKey(const Key('role-switch')));
      await tester.pumpAndSettle();
      expect(find.text(D.errSwitch), findsOneWidget);
      expect(_toneAt(tester, find.byKey(const Key('role-strip'))).isDriver, isFalse);
    });

    testWidgets('unregistered account: badge only, no permanent promotion (Q-D3); way in is the Me tab', (tester) async {
      await _open(tester, registered: false);
      expect(find.byKey(const Key('home-role-capsule-rider')), findsOneWidget);
      expect(find.byKey(const Key('role-switch')), findsNothing);
      await _tapTab(tester, S.tabMe);
      expect(find.byKey(const Key('driver-register-card')), findsOneWidget);
      expect(find.text(D.driverCardTitle), findsOneWidget);
      expect(find.text(D.driverCardNote), findsOneWidget, reason: 'self-declared, not checked');
      expect(find.byKey(const Key('my-roles-card')), findsNothing);
      expect(find.text(D.profileRoleRiderOnly), findsOneWidget);
    });

    testWidgets('registered account sees both roles on the Me tab with the segmented switch', (tester) async {
      final f = await _open(tester);
      await _tapTab(tester, S.tabMe);
      expect(find.byKey(const Key('my-roles-card')), findsOneWidget);
      expect(find.text(D.profileRoleBoth), findsOneWidget);
      await tester.tap(find.byKey(const Key('seg-driver')));
      await tester.pumpAndSettle();
      expect(f.roles.switchCalls, [ActiveRole.driver]);
      expect(_toneAt(tester, find.byKey(const Key('my-roles-card'))).isDriver, isTrue);
    });

    testWidgets('a mode the server no longer allows is reconciled to Rider with a polite notice (F-D8)', (tester) async {
      // Device believes Driver (cache), the account is not registered any more.
      final f = Fakes()..roles.registered = false;
      await tester.pumpWidget(await buildTestApp(
        repo: FakeAuthRepository(initial: testUser),
        prefs: {'onboarding_done': true, 'gwm.activeRole.u1': 'driver'},
        fakes: f,
      ));
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      expect(find.text(D.reconciled), findsOneWidget);
      expect(_toneAt(tester, find.byKey(const Key('home-role-capsule-rider'))).isDriver, isFalse);
      expect(find.byKey(const Key('home-role-capsule-rider')), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('badge + switch read the role name (Semantics)', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester);
      expect(find.bySemanticsLabel(D.a11yModeCurrent(D.roleWordRider)), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^${D.switchToDriver}')),
        findsOneWidget,
        reason: 'the switch names the destination and that it only affects new trips',
      );
      await tester.tap(find.byKey(const Key('role-switch')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(D.a11yModeCurrent(D.roleWordDriver)), findsOneWidget);
      handle.dispose();
    });

    for (final role in [ActiveRole.rider, ActiveRole.driver]) {
      testWidgets('text scale 2.0: ${role.name} strip keeps icon + full text and does not overflow', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _open(tester, active: role, size: const Size(390, 844));
        expect(tester.takeException(), isNull);
        final label = role == ActiveRole.driver ? D.modeDriver : D.modeRider;
        final target = role == ActiveRole.driver ? D.switchToRider : D.switchToDriver;
        expect(find.text(label), findsOneWidget);
        expect(find.text(target), findsOneWidget);
        expect(find.descendant(of: find.byKey(Key('mode-badge-${role.name}')), matching: find.byType(Icon)), findsOneWidget);
        // Never ellipsised: the text may wrap but is not cut.
        final text = tester.widget<Text>(find.text(label));
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        // Me tab (cards, segmented switch) at 2.0 as well.
        await _tapTab(tester, S.tabMe);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('unregistered picker: locked Driver reads "ต้องลงทะเบียนก่อน" (not a skipped disabled item)', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester, registered: false);
      await _toStep2(tester);
      await _pickCar(tester);
      expect(find.bySemanticsLabel('${R.roleDriver} ${D.pickerLocked}'), findsOneWidget);
      handle.dispose();
    });
  });

  group('trip screens keep the tone of the TRIP role', () {
    testWidgets('Rider trip opened while in Driver mode is Rider-toned, with the trip role badge', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip(id: 'trip-1', mode: TravelMode.car, role: TripRole.rider);
      f.roles.active = ActiveRole.driver;
      await openApp(tester, f);
      // Home tab (round 9 RC-6): app-level tone is read off the `_RoleSwitchCapsule`, not the
      // (no longer present on Home) `role-strip`.
      expect(_toneAt(tester, find.byKey(const Key('home-role-capsule-driver'))).isDriver, isTrue, reason: 'app-level page follows the mode');
      await goTo(tester, Routes.tripDetail('trip-1'));
      final bar = find.byType(AppBar).last;
      expect(_toneAt(tester, bar).isDriver, isFalse);
      expect(Theme.of(tester.element(bar)).scaffoldBackgroundColor, isNot(_navy));
      expect(find.text(R.roleBadgeRider), findsWidgets);
    });

    testWidgets('Driver trip opened while in Rider mode is Driver-toned; switching mode later does not change it', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip(id: 'trip-1', mode: TravelMode.car, role: TripRole.driver)
        ..vehicles.vehicle = const Vehicle(plate: '1กก 1234', model: 'Yaris', color: 'ขาว');
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      expect(_toneAt(tester, find.byType(AppBar).last).isDriver, isTrue);
      expect(find.text(R.roleBadgeDriver), findsWidgets);
      // The mode flips underneath (e.g. another screen/device): the open trip page keeps its role tone.
      await containerOf(tester).read(roleControllerProvider.notifier).switchTo(ActiveRole.driver);
      await containerOf(tester).read(roleControllerProvider.notifier).switchTo(ActiveRole.rider);
      await tester.pumpAndSettle();
      expect(_toneAt(tester, find.byType(AppBar).last).isDriver, isTrue);
    });

    testWidgets('a trip without a role (walk) uses the tone of the active mode and shows no role badge', (tester) async {
      final f = Fakes()..trips.active = sampleTrip(id: 'trip-1', mode: TravelMode.walk);
      f.roles.active = ActiveRole.driver;
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      expect(_toneAt(tester, find.byType(AppBar).last).isDriver, isTrue);
      expect(find.text(R.roleBadgeRider), findsNothing);
      expect(find.text(R.roleBadgeDriver), findsNothing);
    });

    testWidgets('a Rider trip card in Driver mode is an island: mint, not navy, with the role badge', (tester) async {
      final f = Fakes()..trips.active = sampleTrip(id: 'trip-1', mode: TravelMode.car, role: TripRole.rider);
      f.roles.active = ActiveRole.driver;
      await openApp(tester, f);
      await _tapTab(tester, S.tabTrips);
      final card = find.byType(Card).first;
      expect(tester.widget<Card>(card).color, ToneColors.rider.infoBg);
      expect(find.text(R.roleBadgeRider), findsWidgets);
    });

    for (final role in [ActiveRole.rider, ActiveRole.driver]) {
      testWidgets('SOS stays red in ${role.name} tone', (tester) async {
        final f = Fakes()..trips.active = runningTrip();
        f.roles.active = role;
        await openApp(tester, f);
        final btn = tester.widget<FilledButton>(find.descendant(of: find.byType(SosMiniButton), matching: find.byType(FilledButton)));
        expect(btn.style!.backgroundColor!.resolve({}), AppColors.danger);
        if (role == ActiveRole.driver) {
          expect(btn.style!.side!.resolve({})!.color, Colors.white, reason: 'white ring on navy');
        }
      });
    }
  });

  group('create-trip role picker (US-20, US-5)', () {
    testWidgets('default follows the active mode and the choice survives a mode change (roleTouched)', (tester) async {
      final f = await _open(tester, active: ActiveRole.driver);
      f.vehicles.vehicle = const Vehicle(plate: '1กก 1234', model: 'Yaris', color: 'ขาว');
      await _toStep2(tester);
      await _pickCar(tester);
      expect(containerOf(tester).read(tripFormProvider).role, TripRole.driver);
      expect(find.byKey(const Key('role-prefill-note')), findsOneWidget);
      expect(_toneAt(tester, find.byKey(const Key('creating-role-badge'))).isDriver, isTrue);

      // The user picks Rider: the form takes the Rider tone with a "this trip" badge.
      await tester.tap(find.byKey(const Key('role-rider')));
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(tripFormProvider).role, TripRole.rider);
      expect(_toneAt(tester, find.byKey(const Key('creating-role-badge'))).isDriver, isFalse);

      // The mode flips to Rider elsewhere: the user's choice is not touched.
      await containerOf(tester).read(roleControllerProvider.notifier).switchTo(ActiveRole.rider);
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(tripFormProvider).role, TripRole.rider);
    });

    testWidgets('untouched default follows a later change of mode', (tester) async {
      final f = await _open(tester);
      f.vehicles.vehicle = const Vehicle(plate: '1กก 1234', model: 'Yaris', color: 'ขาว');
      await _toStep2(tester);
      await _pickCar(tester);
      expect(containerOf(tester).read(tripFormProvider).role, TripRole.rider);
      await containerOf(tester).read(roleControllerProvider.notifier).switchTo(ActiveRole.driver);
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(tripFormProvider).role, TripRole.driver);
      expect(containerOf(tester).read(tripFormProvider).roleTouched, isFalse);
    });

    testWidgets('unregistered: Driver is locked with a way to register; tapping it does not choose it', (tester) async {
      await _open(tester, registered: false);
      await _toStep2(tester);
      await _pickCar(tester);
      expect(find.byKey(const Key('role-driver-locked')), findsOneWidget);
      expect(find.text(D.pickerLocked), findsOneWidget);
      await tester.tap(find.byKey(const Key('role-driver')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('driver-gate-card')), findsOneWidget);
      expect(find.text(D.pickerGate), findsOneWidget);
      expect(containerOf(tester).read(tripFormProvider).role, TripRole.rider, reason: 'still Rider');
      // "use as Rider" is a real choice.
      await tester.tap(find.byKey(const Key('gate-card-use-rider')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('driver-gate-card')), findsNothing);
      expect(containerOf(tester).read(tripFormProvider).roleTouched, isTrue);
    });

    testWidgets('the trip draft survives the detour through registration', (tester) async {
      final f = await _open(tester, registered: false);
      f.roles.onRegister = () => f.vehicles.vehicle = const Vehicle(plate: '1กก 1234', model: 'Yaris', color: 'ขาว');
      await _toStep2(tester);
      await _pickCar(tester);
      final before = containerOf(tester).read(tripFormProvider);

      await tester.tap(find.byKey(const Key('role-driver')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('gate-card-register')));
      await tester.tap(find.byKey(const Key('gate-card-register')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('register-submit')), findsOneWidget);
      // The full-screen registration page has no strip / bottom nav.
      expect(find.byKey(const Key('role-strip')), findsNothing);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '1กก 1234');
      await tester.enterText(fields.at(1), 'Toyota Yaris');
      await tester.enterText(fields.at(2), 'ขาว');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('declaration-checkbox')));
      await tester.tap(find.byKey(const Key('declaration-checkbox')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('register-success')), findsOneWidget);
      expect(find.text(D.successReturnTrip), findsOneWidget);
      expect(f.roles.switchCalls, isEmpty, reason: 'registering never switches by itself');

      await tester.tap(find.byKey(const Key('success-later')));
      await tester.pumpAndSettle();
      final after = containerOf(tester).read(tripFormProvider);
      expect(find.byKey(const Key('role-picker')), findsOneWidget);
      expect(after.origin?.label, before.origin?.label);
      expect(after.dest?.label, before.dest?.label);
      expect(after.mode, TravelMode.car);
      expect(find.byKey(const Key('role-driver-locked')), findsNothing, reason: 'Driver is unlocked now');
      expect(containerOf(tester).read(roleControllerProvider).active, ActiveRole.rider, reason: 'still Rider mode');
    });

    testWidgets('registering then switching returns to the form with Driver as the (untouched) default', (tester) async {
      final f = await _open(tester, registered: false);
      f.roles.onRegister = () => f.vehicles.vehicle = const Vehicle(plate: '1กก 1234', model: 'Yaris', color: 'ขาว');
      await _toStep2(tester);
      await _pickCar(tester);
      await tester.tap(find.byKey(const Key('role-driver')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gate-card-register')));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '1กก 1234');
      await tester.enterText(fields.at(1), 'Toyota Yaris');
      await tester.enterText(fields.at(2), 'ขาว');
      await tester.ensureVisible(find.byKey(const Key('declaration-checkbox')));
      await tester.tap(find.byKey(const Key('declaration-checkbox')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('success-switch')));
      await tester.pumpAndSettle();
      expect(f.roles.switchCalls, [ActiveRole.driver]);
      expect(containerOf(tester).read(tripFormProvider).role, TripRole.driver);
      expect(containerOf(tester).read(tripFormProvider).roleTouched, isFalse);
    });

    testWidgets('confirm step: big "role of this trip" row before creating', (tester) async {
      final f = await _open(tester);
      f.vehicles.vehicle = const Vehicle(plate: '1กก 1234', model: 'Yaris', color: 'ขาว');
      await _toStep2(tester);
      await _pickCar(tester);
      await tester.tap(find.text(S.next));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-role-row')), findsOneWidget);
      expect(find.text(D.confirmRow(TripRole.rider.label)), findsOneWidget);
    });
  });

  group('registration page', () {
    Future<void> openRegister(WidgetTester tester, Fakes f) async {
      await goTo(tester, Routes.driverRegister);
    }

    testWidgets('notice first (self-declared, 1 companion, no money), declaration not pre-ticked, submit off with a reason', (tester) async {
      final f = await _open(tester, registered: false);
      await openRegister(tester, f);
      expect(find.byKey(const Key('driver-notice')), findsOneWidget);
      expect(find.text(D.notice1), findsOneWidget);
      expect(find.text(D.notice2), findsOneWidget);
      expect(find.text(D.notice3), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('declaration-checkbox'))).value, isFalse);
      expect(tester.widget<AppButton>(find.byKey(const Key('register-submit'))).onPressed, isNull);
      expect(find.byKey(const Key('register-disabled-reason')), findsOneWidget);
      expect(find.text(D.declNote), findsOneWidget, reason: 'no licence number/photo is collected, said in plain text');
    });

    testWidgets('an existing (kept) vehicle is prefilled with a banner, and the declaration still starts unticked', (tester) async {
      final f = await _open(tester, registered: false);
      f.vehicles.vehicle = const Vehicle(plate: '9ขข 999', model: 'Honda City', color: 'ดำ');
      await openRegister(tester, f);
      expect(find.byKey(const Key('prefill-banner')), findsOneWidget);
      expect(find.text('9ขข 999'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('declaration-checkbox'))).value, isFalse);
      expect(tester.widget<AppButton>(find.byKey(const Key('register-submit'))).onPressed, isNull);
    });

    testWidgets('the close button is off while the request is pending; a failure keeps the data', (tester) async {
      final f = await _open(tester, registered: false);
      f.vehicles.vehicle = const Vehicle(plate: '9ขข 999', model: 'Honda City', color: 'ดำ');
      f.roles.registerGate = Completer<void>();
      await openRegister(tester, f);
      await tester.ensureVisible(find.byKey(const Key('declaration-checkbox')));
      await tester.tap(find.byKey(const Key('declaration-checkbox')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pump();
      expect(find.text(D.submitting), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('register-close'))).onPressed, isNull);
      expect(tester.widget<AppButton>(find.byKey(const Key('register-submit'))).onPressed, isNull, reason: 'no double submit');
      f.roles.failNextRegister = const AppFailure(FailureCode.networkOffline, retryable: true);
      f.roles.registerGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text(D.errNetwork), findsOneWidget);
      expect(find.text('9ขข 999'), findsOneWidget, reason: 'what was typed is still there');
      expect(tester.widget<IconButton>(find.byKey(const Key('register-close'))).onPressed, isNotNull);
      expect(f.roles.registerCalls.length, 1);
    });

    testWidgets('server refuses a stale declaration: Thai message, nothing registered', (tester) async {
      final f = await _open(tester, registered: false);
      f.vehicles.vehicle = const Vehicle(plate: '9ขข 999', model: 'Honda City', color: 'ดำ');
      f.roles.failNextRegister = const AppFailure('GWM_DECLARATION_VERSION_STALE');
      await openRegister(tester, f);
      await tester.ensureVisible(find.byKey(const Key('declaration-checkbox')));
      await tester.tap(find.byKey(const Key('declaration-checkbox')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();
      expect(find.text(D.errDeclStale), findsOneWidget);
      expect(containerOf(tester).read(roleControllerProvider).registered, isFalse);
    });

    testWidgets('leaving with typed data asks first; "keep filling" stays', (tester) async {
      final f = await _open(tester, registered: false);
      await openRegister(tester, f);
      await tester.enterText(find.byType(TextFormField).first, 'abc');
      await tester.pump();
      await tester.tap(find.byKey(const Key('register-close')));
      await tester.pumpAndSettle();
      expect(find.text(D.discardTitle), findsOneWidget);
      await tester.tap(find.text(D.discardStay));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('register-submit')), findsOneWidget);
    });

    testWidgets('an already registered account is sent to the vehicle page instead', (tester) async {
      final f = await _open(tester);
      f.vehicles.vehicle = const Vehicle(plate: '1กก 1234', model: 'Yaris', color: 'ขาว');
      await goTo(tester, Routes.driverRegister);
      expect(find.byKey(const Key('register-submit')), findsNothing);
      expect(find.text(R.vehicleTitle), findsWidgets);
    });

    testWidgets('/me/vehicle with no vehicle and no registration goes to registration (replace)', (tester) async {
      await _open(tester, registered: false);
      await goTo(tester, Routes.vehicle);
      expect(find.byKey(const Key('register-submit')), findsOneWidget);
    });

    testWidgets('kept vehicle after unregistering: owner-only note, register again, delete allowed', (tester) async {
      final f = await _open(tester, registered: false);
      f.vehicles.vehicle = const Vehicle(plate: '1กก 1234', model: 'Yaris', color: 'ขาว');
      await goTo(tester, Routes.vehicle);
      expect(find.byKey(const Key('vehicle-retained')), findsOneWidget);
      expect(find.text(D.vehicleRetainedNote), findsOneWidget);
      expect(find.byKey(const Key('vehicle-reregister')), findsOneWidget);
      expect(tester.widget<AppButton>(find.byKey(const Key('vehicle-delete'))).onPressed, isNotNull);
    });

    testWidgets('a registered driver cannot delete the vehicle: reasons sheet with a way to unregister', (tester) async {
      final f = await _open(tester);
      f.vehicles.vehicle = const Vehicle(plate: '1กก 1234', model: 'Yaris', color: 'ขาว');
      await goTo(tester, Routes.vehicle);
      await tester.ensureVisible(find.byKey(const Key('vehicle-delete')));
      await tester.tap(find.byKey(const Key('vehicle-delete')));
      await tester.pumpAndSettle();
      expect(find.text(D.vehicleDeleteBlockedRegistered), findsOneWidget);
      expect(find.text(D.vehicleDeleteBlockedCta), findsOneWidget);
      expect(f.vehicles.vehicle, isNotNull);
    });
  });

  group('unregister (US-19)', () {
    Future<void> tapUnregister(WidgetTester tester) async {
      await _tapTab(tester, S.tabMe);
      await tester.ensureVisible(find.byKey(const Key('unregister-row')));
      await tester.tap(find.byKey(const Key('unregister-row')));
      await tester.pumpAndSettle();
    }

    testWidgets('confirm dialog: safe button first, consequences listed; confirming returns to Rider mode', (tester) async {
      final f = await _open(tester, active: ActiveRole.driver);
      await tapUnregister(tester);
      expect(find.byKey(const Key('unregister-dialog')), findsOneWidget);
      for (final t in [D.unregItem1, D.unregItem2, D.unregItem3, D.unregItem4]) {
        expect(find.text(t), findsOneWidget);
      }
      final stay = tester.getTopLeft(find.byKey(const Key('unregister-stay'))).dx;
      final confirm = tester.getTopLeft(find.byKey(const Key('unregister-confirm'))).dx;
      expect(stay, lessThan(confirm), reason: 'the safe choice comes first');
      await tester.tap(find.byKey(const Key('unregister-confirm')));
      await tester.pumpAndSettle();
      expect(f.roles.unregisterCalls, 1);
      expect(find.text(D.unregDone), findsOneWidget);
      expect(_toneAt(tester, find.byKey(const Key('role-strip'))).isDriver, isFalse, reason: 'back to Rider tone');
      expect(find.byKey(const Key('driver-register-card')), findsOneWidget);
    });

    testWidgets('"do not cancel" changes nothing', (tester) async {
      final f = await _open(tester);
      await tapUnregister(tester);
      await tester.tap(find.byKey(const Key('unregister-stay')));
      await tester.pumpAndSettle();
      expect(f.roles.unregisterCalls, 0);
      expect(find.byKey(const Key('my-roles-card')), findsOneWidget);
    });

    testWidgets('an active Driver trip blocks it before any dialog, with the reason and the way to My trips', (tester) async {
      final f = Fakes()..trips.active = sampleTrip(id: 'trip-1', mode: TravelMode.car, role: TripRole.driver);
      await openApp(tester, f);
      await tapUnregister(tester);
      expect(find.byKey(const Key('blocked-reason')), findsOneWidget);
      expect(find.text(D.blockedTrip), findsOneWidget);
      expect(find.byKey(const Key('unregister-dialog')), findsNothing);
      expect(f.roles.unregisterCalls, 0);
      expect(find.text(D.blockedCta), findsOneWidget);
    });

    testWidgets('an accepted Driver-side match blocks it too', (tester) async {
      final f = Fakes()..matches.matches = [sampleMatch(status: MatchStatus.accepted, myRole: TripRole.driver)];
      await openApp(tester, f);
      await tapUnregister(tester);
      expect(find.text(D.blockedMatch), findsOneWidget);
    });

    testWidgets('an active Rider trip does not block (and is not mentioned)', (tester) async {
      final f = Fakes()..trips.active = sampleTrip(id: 'trip-1', mode: TravelMode.car, role: TripRole.rider);
      await openApp(tester, f);
      await tapUnregister(tester);
      expect(find.byKey(const Key('unregister-dialog')), findsOneWidget);
      expect(find.byKey(const Key('blocked-reason')), findsNothing);
    });

    testWidgets('the server refuses at submit (state changed meanwhile): dialog turns into the reasons, still registered', (tester) async {
      final f = await _open(tester);
      f.roles.failNextUnregister = const AppFailure('GWM_DRIVER_ACTIVE_MATCH');
      await tapUnregister(tester);
      await tester.tap(find.byKey(const Key('unregister-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blocked-reason')), findsOneWidget);
      expect(find.text(D.blockedMatch), findsOneWidget);
      expect(containerOf(tester).read(roleControllerProvider).registered, isTrue);
      await tester.tap(find.byKey(const Key('blocked-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('my-roles-card')), findsOneWidget);
    });

    testWidgets('network error: message + retry, state unchanged', (tester) async {
      final f = await _open(tester);
      f.roles.failNextUnregister = const AppFailure(FailureCode.networkOffline, retryable: true);
      await tapUnregister(tester);
      await tester.tap(find.byKey(const Key('unregister-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unregister-error')), findsOneWidget);
      expect(containerOf(tester).read(roleControllerProvider).registered, isTrue);
      await tester.tap(find.byKey(const Key('unregister-confirm')));
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(roleControllerProvider).registered, isFalse);
    });
  });
}
