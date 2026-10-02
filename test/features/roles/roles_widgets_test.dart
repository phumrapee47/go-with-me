import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_p4.dart';
import 'package:gowithme/core/l10n/strings_roles.dart';
import 'package:gowithme/core/l10n/strings_trip.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/core/widgets/app_button.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/safety/domain/safety_models.dart';
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
const _yaris = Vehicle(plate: '1กก 1234', model: 'Toyota Yaris', color: 'ขาว');

Future<void> _toStep2(WidgetTester tester) async {
  final c = containerOf(tester);
  c.read(tripFormProvider.notifier)
    ..setOrigin(_siam)
    ..setDest(_rangsit);
  await goTo(tester, Routes.tripOptions);
}

Future<void> _pickMode(WidgetTester tester, TravelMode m) async {
  await tester.ensureVisible(find.text(m.label));
  await tester.tap(find.text(m.label));
  await tester.pumpAndSettle();
}

Future<void> _tapInDialog(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(label)));
  await tester.pumpAndSettle();
}

bool _nextEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, S.next)).onPressed != null;

void main() {
  group('role picker + vehicle gate (create trip step 2)', () {
    testWidgets('car shows the picker with a default from the active role (round 4); Next is on and no seat input', (tester) async {
      await openApp(tester, Fakes());
      await _toStep2(tester);
      expect(find.byKey(const Key('role-picker')), findsNothing, reason: 'not for other modes');

      await _pickMode(tester, TravelMode.car);
      expect(find.byKey(const Key('role-picker')), findsOneWidget);
      expect(find.text(R.roleDriver), findsOneWidget);
      expect(find.text(R.roleRider), findsOneWidget);
      expect(find.text(R.roleOneOnly), findsOneWidget);
      expect(find.text(R.roleNoMoney), findsOneWidget);
      expect(find.text(R.roleLockedNote), findsOneWidget);
      // US-20: the default follows the active mode (Rider here) and says so; the user can still change it.
      final form = containerOf(tester).read(tripFormProvider);
      expect(form.role, TripRole.rider);
      expect(form.roleTouched, isFalse, reason: 'a default is not a user choice');
      expect(find.byKey(const Key('role-prefill-note')), findsOneWidget);
      expect(_nextEnabled(tester), isTrue, reason: 'a Rider does not need a vehicle');
      // No seat input anywhere: the driver always takes exactly one companion.
      // (round 7 adds an unrelated `TextField` for the optional mood text — US-44 — so this
      // now checks specifically for a seat-count field, not "no TextField at all".)
      expect(find.textContaining('จำนวนที่นั่ง'), findsNothing);
      expect(find.byKey(const Key('mood-text-field')), findsOneWidget);

      await tester.tap(find.byKey(const Key('role-rider')));
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(tripFormProvider).roleTouched, isTrue);
      expect(find.byKey(const Key('role-prefill-note')), findsNothing);
    });

    testWidgets('choosing another mode removes the picker and forgets the role; back to car re-applies the default', (tester) async {
      await openApp(tester, Fakes());
      await _toStep2(tester);
      await _pickMode(tester, TravelMode.car);
      await tester.tap(find.byKey(const Key('role-rider')));
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(tripFormProvider).role, TripRole.rider);

      await _pickMode(tester, TravelMode.walk);
      expect(find.byKey(const Key('role-picker')), findsNothing);
      expect(containerOf(tester).read(tripFormProvider).role, isNull);
      await _pickMode(tester, TravelMode.car);
      final again = containerOf(tester).read(tripFormProvider);
      expect(again.role, TripRole.rider, reason: 'the default of the active mode, not the old choice');
      expect(again.roleTouched, isFalse);
    });

    testWidgets('Driver without a vehicle is gated; filling it returns to the same step without losing the form',
        (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await _toStep2(tester);
      await _pickMode(tester, TravelMode.car);
      await tester.tap(find.byKey(const Key('role-driver')));
      await tester.pumpAndSettle();
      expect(find.text(R.needsVehicle), findsOneWidget);
      expect(_nextEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('fill-vehicle')));
      await tester.pumpAndSettle();
      expect(find.text(R.vehicleTitle), findsWidgets);
      await tester.enterText(find.widgetWithText(TextFormField, '').at(0), '1กก 1234');
      await tester.pump();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '1กก 1234');
      await tester.enterText(fields.at(1), 'Toyota Yaris');
      await tester.enterText(fields.at(2), 'ขาว');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('vehicle-save')));
      await tester.tap(find.byKey(const Key('vehicle-save')));
      await tester.pumpAndSettle();

      expect(f.vehicles.saved.single.plate, '1กก 1234');
      expect(f.vehicles.consentCalls, isEmpty, reason: 'saving never touches the consent switch');
      // Back on step 2: the draft (places, mode, role) survived and Next works.
      expect(find.byKey(const Key('role-picker')), findsOneWidget);
      final form = containerOf(tester).read(tripFormProvider);
      expect(form.origin?.label, 'สยาม');
      expect(form.mode, TravelMode.car);
      expect(form.role, TripRole.driver);
      expect(find.text(R.rowSummaryDriver), findsOneWidget, reason: '"รับได้ 1 คน" note');
      expect(_nextEnabled(tester), isTrue);
    });

    testWidgets('Driver with a saved vehicle sees the owner preview and can continue', (tester) async {
      final f = Fakes()..vehicles.vehicle = _yaris;
      await openApp(tester, f);
      await _toStep2(tester);
      await _pickMode(tester, TravelMode.car);
      await tester.tap(find.byKey(const Key('role-driver')));
      await tester.pumpAndSettle();
      expect(find.text('1กก 1234'), findsOneWidget);
      expect(find.text(R.ownerPreviewTitle), findsOneWidget);
      expect(_nextEnabled(tester), isTrue);
    });

    testWidgets('step 3 shows the role, creates with it and a server rejection offers "go back and fix"',
        (tester) async {
      final f = Fakes()..vehicles.vehicle = _yaris;
      f.trips.createFailure = const AppFailure('GWM_VEHICLE_REQUIRED');
      await openApp(tester, f);
      await _toStep2(tester);
      await _pickMode(tester, TravelMode.car);
      await tester.tap(find.byKey(const Key('role-driver')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.next));
      await tester.pumpAndSettle();
      expect(find.text(R.rowSummaryDriver), findsOneWidget);
      expect(find.text(R.roleLockedNote), findsOneWidget);

      await tester.tap(find.text(T.createTrip));
      await tester.pumpAndSettle();
      expect(find.text(R.needsVehicle), findsOneWidget);
      expect(find.byKey(const Key('back-to-fix')), findsOneWidget);
      expect(containerOf(tester).read(tripFormProvider).role, TripRole.driver, reason: 'the form is kept');

      f.trips.createFailure = null;
      await tester.tap(find.text(T.createTrip));
      await tester.pumpAndSettle();
      expect(f.trips.created.single.role, TripRole.driver);
      expect(f.trips.created.single.mode, TravelMode.car);
    });

    testWidgets('a non-car trip is created with no role at all', (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await _toStep2(tester);
      await _pickMode(tester, TravelMode.walk);
      await tester.tap(find.text(S.next));
      await tester.pumpAndSettle();
      await tester.tap(find.text(T.createTrip));
      await tester.pumpAndSettle();
      expect(f.trips.created.single.role, isNull);
    });
  });

  group('vehicle screen (S-33)', () {
    testWidgets('consent switch is OFF by default and saving the vehicle does not depend on it', (tester) async {
      final f = Fakes()..vehicles.vehicle = _yaris;
      await openApp(tester, f);
      await goTo(tester, Routes.vehicle);
      final sw = find.byKey(const Key('share-consent-switch'));
      await tester.ensureVisible(sw);
      expect(tester.widget<SwitchListTile>(sw).value, isFalse);
      expect(find.text(R.shareOffState), findsOneWidget);
      expect(find.text(R.privacy3), findsOneWidget, reason: 'privacy notice shown, not hidden');
      expect(find.text(R.unverified), findsWidgets);

      await tester.enterText(find.byType(TextFormField).at(1), 'Honda City');
      await tester.ensureVisible(find.byKey(const Key('vehicle-save')));
      await tester.tap(find.byKey(const Key('vehicle-save')));
      await tester.pumpAndSettle();
      expect(f.vehicles.saved.single.model, 'Honda City');
      expect(f.vehicles.consentCalls, isEmpty);
      expect(f.vehicles.vehicle!.shareConsent, isFalse);
    });

    testWidgets('toggling calls the server; withdrawing shows the notice; failure keeps the old value',
        (tester) async {
      final f = Fakes()..vehicles.vehicle = _yaris;
      await openApp(tester, f);
      await goTo(tester, Routes.vehicle);
      final sw = find.byKey(const Key('share-consent-switch'));
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(f.vehicles.consentCalls, [true]);
      expect(find.text(R.shareOnState), findsOneWidget);

      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(f.vehicles.consentCalls, [true, false]);
      expect(find.byKey(const Key('share-withdraw-notice')), findsOneWidget);
      expect(find.text(R.shareWithdrawNotice), findsOneWidget);

      f.vehicles.consentFailure = const AppFailure(FailureCode.serverUnavailable);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(sw).value, isFalse, reason: 'reverted after the failure');
      expect(find.text(R.shareFailed), findsOneWidget);
    });

    testWidgets('a choice made before any vehicle exists is applied after the first save; failure is reported',
        (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await goTo(tester, Routes.vehicle);
      expect(find.text(R.vehicleEmptyTitle), findsOneWidget);
      final sw = find.byKey(const Key('share-consent-switch'));
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(f.vehicles.consentCalls, isEmpty, reason: 'nothing to attach the consent to yet');

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'ขข 5678');
      await tester.enterText(fields.at(1), 'Honda City');
      await tester.enterText(fields.at(2), 'ดำ');
      f.vehicles.consentFailure = const AppFailure(FailureCode.serverUnavailable);
      await tester.ensureVisible(find.byKey(const Key('vehicle-save')));
      await tester.tap(find.byKey(const Key('vehicle-save')));
      await tester.pumpAndSettle();
      expect(f.vehicles.saved, hasLength(1));
      expect(find.text(R.sharePartialFailed), findsOneWidget);
      expect(f.vehicles.vehicle!.shareConsent, isFalse);
    });

    testWidgets('empty or too long fields show messages under the field and nothing is sent', (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await goTo(tester, Routes.vehicle);
      await tester.ensureVisible(find.byKey(const Key('vehicle-save')));
      await tester.tap(find.byKey(const Key('vehicle-save')));
      await tester.pumpAndSettle();
      expect(find.text(R.errPlateRequired), findsOneWidget);
      expect(find.text(R.errModelRequired), findsOneWidget);
      expect(find.text(R.errColorRequired), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'ก' * 26);
      await tester.tap(find.byKey(const Key('vehicle-save')));
      await tester.pumpAndSettle();
      expect(find.text(R.errTooLong), findsOneWidget);
      expect(f.vehicles.saved, isEmpty);
    });

    testWidgets('delete is disabled with a reason while a Driver trip is active (Q-6)', (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = _yaris
        ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.driver);
      await openApp(tester, f);
      await goTo(tester, Routes.vehicle);
      await tester.ensureVisible(find.byKey(const Key('vehicle-delete')));
      expect(find.byKey(const Key('vehicle-delete-locked')), findsOneWidget);
      expect(find.text(R.deleteLocked), findsOneWidget);
      expect(tester.widget<AppButton>(find.byKey(const Key('vehicle-delete'))).onPressed, isNull);
    });

    testWidgets('delete works when nothing is using the vehicle and the account is not registered (with a confirmation)',
        (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = _yaris
        ..roles.registered = false;
      await openApp(tester, f);
      await goTo(tester, Routes.vehicle);
      await tester.ensureVisible(find.byKey(const Key('vehicle-delete')));
      await tester.tap(find.byKey(const Key('vehicle-delete')));
      await tester.pumpAndSettle();
      expect(find.text(R.deleteTitle), findsOneWidget);
      await tester.tap(find.text(R.delete).last);
      await tester.pumpAndSettle();
      expect(f.vehicles.vehicle, isNull);
    });

    testWidgets('/me lists the vehicle row with its status as text', (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await tester.tap(find.text(S.tabMe));
      await tester.pumpAndSettle();
      expect(find.text(R.vehicleTitle), findsOneWidget);
      expect(find.text(R.rowStatusNone), findsOneWidget);
    });
  });

  group('nearby: Driver / Rider variants', () {
    testWidgets('Driver sees riders: header, role badge, direction wording, CTA, no vehicle data', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.driver)
        ..finder.result = [sampleCandidate(name: 'ริเดอร์', mode: TravelMode.car, role: TripRole.rider)];
      await openApp(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nearby-list-header')), findsOneWidget);
      expect(find.text(R.listForDriver), findsOneWidget);
      expect(find.text(R.roleBadgeRider), findsWidgets);
      expect(find.textContaining(R.overlapDriverView(72)), findsWidgets);
      expect(find.text(R.ctaDriver), findsWidgets);
      expect(find.text(R.vehicleAfterAccept), findsNothing, reason: 'that line belongs to driver cards');
    });

    testWidgets('Rider sees drivers: badge + "รับได้ 1 คน", "ขอติดรถ", vehicle only after accept', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.rider)
        ..finder.result = [sampleCandidate(name: 'คนขับ', mode: TravelMode.car, role: TripRole.driver)];
      await openApp(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      expect(find.text(R.listForRider), findsOneWidget);
      expect(find.text(R.roleBadgeDriver), findsWidgets);
      expect(find.text(R.seatOne), findsWidgets);
      expect(find.textContaining(R.overlapRiderView(72)), findsWidgets);
      expect(find.text(R.ctaRider), findsWidgets);
      expect(find.text(R.vehicleAfterAccept), findsWidgets);
      // Never a plate/model in a search result.
      expect(find.textContaining('Toyota'), findsNothing);
    });

    testWidgets('request sheet wording follows the sender role and sends the request', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.rider)
        ..finder.result = [sampleCandidate(name: 'คนขับ', mode: TravelMode.car, role: TripRole.driver)];
      await openApp(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      await tester.tap(find.text(R.ctaRider).first);
      await tester.pumpAndSettle();
      expect(find.text(R.sendSheetRider), findsOneWidget);
      await tester.tap(find.text(R.ctaRider).last);
      await tester.pumpAndSettle();
      expect(f.matches.requests, [('trip-1', 'cand-1')]);
    });

    testWidgets('empty results are role specific and never hint at other roles', (tester) async {
      final f = Fakes()..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.driver);
      await openApp(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      expect(find.text(R.emptyDriverTitle), findsOneWidget);
      expect(find.text(R.emptyDriverBody), findsOneWidget);
    });

    testWidgets('a car trip that already has its companion shows "you have a partner", not the list',
        (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.driver)
        ..finder.result = [sampleCandidate(mode: TravelMode.car, role: TripRole.rider)]
        ..matches.matches = [sampleMatch(status: MatchStatus.accepted, myRole: TripRole.driver)];
      await openApp(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nearby-matched')), findsOneWidget);
      expect(find.text(R.matchedTitle), findsOneWidget);
      expect(find.text(R.viewMatch), findsOneWidget);
      expect(find.text(R.ctaDriver), findsNothing);
    });

    testWidgets('legacy car trip without a role: explained, no search call', (tester) async {
      final f = Fakes()..trips.active = sampleTrip(mode: TravelMode.car);
      await openApp(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('legacy-no-role')), findsOneWidget);
      expect(find.text(R.legacyNoRole), findsOneWidget);
      expect(f.finder.calls, 0);
    });

    testWidgets('peer modes are untouched: no role UI, original wording', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip()
        ..finder.result = [sampleCandidate()];
      await openApp(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nearby-list-header')), findsNothing);
      expect(find.text(R.roleBadgeDriver), findsNothing);
      expect(find.text(T.goTogether), findsWidgets);
    });

    testWidgets('a car trip drops results that break the role rule even if the server sent them', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.driver)
        ..finder.result = [
          sampleCandidate(tripId: 'a', name: 'ถูก', mode: TravelMode.car, role: TripRole.rider),
          sampleCandidate(tripId: 'b', name: 'ผิดบทบาท', mode: TravelMode.car, role: TripRole.driver),
          sampleCandidate(tripId: 'c', name: 'ผิดโหมด', mode: TravelMode.walk),
        ];
      await openApp(tester, f);
      await tester.tap(find.text(S.tabNearby));
      await tester.pumpAndSettle();
      expect(find.text('ถูก'), findsWidgets);
      expect(find.text('ผิดบทบาท'), findsNothing);
      expect(find.text('ผิดโหมด'), findsNothing);
    });
  });

  group('requests: accept dialogs and neutral closed state', () {
    testWidgets('Driver accepting sees the 1-companion dialog; declining the dialog sends nothing',
        (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.driver)
        ..matches.matches = [sampleMatch(myRole: TripRole.driver)];
      await openApp(tester, f);
      await goTo(tester, Routes.nearbyRequests);
      expect(find.text(R.roleBadgeRider), findsWidgets, reason: "the sender's role is shown");
      await tester.tap(find.text(T.accept));
      await tester.pumpAndSettle();
      expect(find.text(R.acceptTitleDriver), findsOneWidget);
      expect(find.text(R.acceptBodyDriver), findsOneWidget);
      await tester.tap(find.text(R.acceptBack));
      await tester.pumpAndSettle();
      expect(f.matches.responses, isEmpty);

      await tester.tap(find.text(T.accept));
      await tester.pumpAndSettle();
      await _tapInDialog(tester, R.acceptConfirm);
      expect(f.matches.responses, [('m1', true)]);
    });

    testWidgets('Rider accepting a driver invitation sees the rider dialog', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.rider)
        ..matches.matches = [sampleMatch(myRole: TripRole.rider)];
      await openApp(tester, f);
      await goTo(tester, Routes.nearbyRequests);
      await tester.tap(find.text(T.accept));
      await tester.pumpAndSettle();
      expect(find.text(R.acceptTitleRider), findsOneWidget);
      expect(find.text(R.acceptBodyRider), findsOneWidget);
    });

    testWidgets('a peer request still accepts with no extra dialog', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip()
        ..matches.matches = [sampleMatch()];
      await openApp(tester, f);
      await goTo(tester, Routes.nearbyRequests);
      await tester.tap(find.text(T.accept));
      await tester.pumpAndSettle();
      expect(f.matches.responses, [('m1', true)]);
    });

    testWidgets('losing the race: "you already have a partner" and the request shows as closed', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.driver)
        ..matches.matches = [sampleMatch(myRole: TripRole.driver)];
      await openApp(tester, f);
      await goTo(tester, Routes.nearbyRequests);
      // The server refuses (someone else was accepted first) ...
      f.matches.responseFailure = const AppFailure('GWM_MATCH_LIMIT');
      await tester.tap(find.text(T.accept));
      await tester.pumpAndSettle();
      await _tapInDialog(tester, R.acceptConfirm);
      expect(find.text(R.alreadyPaired), findsOneWidget);
    });

    testWidgets('sent tab: an auto-closed request reads "closed" without a reason', (tester) async {
      final f = Fakes()
        ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.rider)
        ..matches.matches = [
          sampleMatch(status: MatchStatus.cancelled, iAmRequester: true, myRole: TripRole.rider, autoClosed: true),
        ];
      await openApp(tester, f);
      await goTo(tester, Routes.nearbyRequests);
      await tester.tap(find.text(T.tabSent));
      await tester.pumpAndSettle();
      expect(find.text(R.requestClosed), findsOneWidget);
      expect(find.textContaining('ตอบรับคนอื่น'), findsNothing);
    });
  });

  group('share / SOS previews and text', () {
    Future<void> openShare(WidgetTester tester, Fakes f) async {
      f.trips.active = runningTrip().copyWith(status: TripStatus.inProgress);
      await openApp(tester, f);
      await goTo(tester, Routes.tripShare('trip-1'));
    }

    testWidgets('Rider, driver allows the plate: preview says so and the text carries it', (tester) async {
      final f = Fakes()
        ..vehicles.view = const VehicleView(plate: 'ขข 5678', model: 'Honda City', color: 'ดำ', shareAllowed: true)
        ..matches.matches = [sampleMatch(status: MatchStatus.accepted, myRole: TripRole.rider, name: 'สมชาย')];
      await openShare(tester, f);
      expect(find.text(R.sharePreviewRiderWithPlate), findsOneWidget);
      await tester.tap(find.text(P.shareSend));
      await tester.pumpAndSettle();
      final text = f.actions.shared.single;
      expect(text, contains('คนขับ: สมชาย'));
      expect(text, contains('ทะเบียนรถ: ขข 5678'));
      expect(text, isNot(contains('Honda')), reason: 'model/colour never leave the app');
      expect(text, isNot(contains('ดำ')));
    });

    testWidgets('Rider, driver has NOT allowed it: preview says no plate and the text has none', (tester) async {
      final f = Fakes()
        ..vehicles.view = const VehicleView(plate: 'ขข 5678', model: 'Honda City', color: 'ดำ')
        ..matches.matches = [sampleMatch(status: MatchStatus.accepted, myRole: TripRole.rider, name: 'สมชาย')];
      await openShare(tester, f);
      expect(find.text(R.sharePreviewRiderNoPlate), findsOneWidget);
      await tester.tap(find.text(P.shareSend));
      await tester.pumpAndSettle();
      final text = f.actions.shared.single;
      expect(text, contains('คนขับ: สมชาย'));
      expect(text, isNot(contains('ขข 5678')));
    });

    testWidgets('consent withdrawn while the page is open: nothing is sent from the stale preview', (tester) async {
      final f = Fakes()
        ..vehicles.view = const VehicleView(plate: 'ขข 5678', model: 'Honda City', color: 'ดำ', shareAllowed: true)
        ..matches.matches = [sampleMatch(status: MatchStatus.accepted, myRole: TripRole.rider, name: 'สมชาย')];
      await openShare(tester, f);
      expect(find.text(R.sharePreviewRiderWithPlate), findsOneWidget);
      f.vehicles.view = const VehicleView(plate: 'ขข 5678', model: 'Honda City', color: 'ดำ');
      await tester.tap(find.text(P.shareSend));
      await tester.pumpAndSettle();
      expect(f.actions.shared, isEmpty, reason: 'the preview changed: user must look again');
      expect(find.text(R.sharePreviewRiderNoPlate), findsOneWidget);
      expect(find.text(R.shareChangedSnack), findsOneWidget);
      await tester.tap(find.text(P.shareSend));
      await tester.pumpAndSettle();
      expect(f.actions.shared.single, isNot(contains('ขข 5678')));
    });

    testWidgets('status cannot be loaded: share still works with the driver name only', (tester) async {
      final f = Fakes()
        ..vehicles.viewFailure = const AppFailure(FailureCode.serverUnavailable)
        ..matches.matches = [sampleMatch(status: MatchStatus.accepted, myRole: TripRole.rider, name: 'สมชาย')];
      await openShare(tester, f);
      await tester.tap(find.text(P.shareSend));
      await tester.pumpAndSettle();
      expect(f.actions.shared.single, contains('คนขับ: สมชาย'));
    });

    testWidgets('Driver: own plate + rider name, plate only', (tester) async {
      final f = Fakes()
        ..vehicles.vehicle = _yaris
        ..matches.matches = [sampleMatch(status: MatchStatus.accepted, myRole: TripRole.driver, name: 'ใจดี')];
      await openShare(tester, f);
      expect(find.text(R.sharePreviewDriver), findsOneWidget);
      await tester.tap(find.text(P.shareSend));
      await tester.pumpAndSettle();
      final text = f.actions.shared.single;
      expect(text, contains('ทะเบียนรถ: 1กก 1234'));
      expect(text, contains('คนนั่ง: ใจดี'));
      expect(text, isNot(contains('Toyota')));
    });

    testWidgets('no car match: no driver section, no preview line', (tester) async {
      final f = Fakes();
      await openShare(tester, f);
      expect(find.byKey(const Key('share-preview-line')), findsNothing);
    });

    testWidgets('SOS: preview line under the confirm button; text has driver name (+plate if allowed); never blocked',
        (tester) async {
      final f = Fakes()
        ..vehicles.view = const VehicleView(plate: 'ขข 5678', model: 'Honda City', color: 'ดำ', shareAllowed: true)
        ..matches.matches = [sampleMatch(status: MatchStatus.accepted, myRole: TripRole.rider, name: 'สมชาย')]
        ..trips.active = runningTrip()
        ..contacts.items.add(const EmergencyContact(id: 'c1', name: 'แม่', phone: '0812345678'));
      await openApp(tester, f);
      await goTo(tester, Routes.sosFor(tripId: 'trip-1'));
      expect(find.byKey(const Key('sos-preview-line')), findsOneWidget);
      expect(find.text(R.sosPreviewRiderWithPlate), findsOneWidget);
      await tester.tap(find.text(P.sosTapConfirm));
      await tester.pumpAndSettle();
      final shared = f.actions.shared.isNotEmpty ? f.actions.shared.last : '';
      expect(shared, contains('คนขับ: สมชาย'));
      expect(shared, contains('ขข 5678'));
    });

    testWidgets('SOS without a car match shows no preview and is not delayed', (tester) async {
      final f = Fakes()..trips.active = runningTrip();
      await openApp(tester, f);
      await goTo(tester, Routes.sosFor(tripId: 'trip-1'));
      expect(find.byKey(const Key('sos-preview-line')), findsNothing);
    });
  });
}
