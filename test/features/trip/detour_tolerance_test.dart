import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_r5.dart';
import 'package:gowithme/core/l10n/strings_trip.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/presentation/create_trip_widgets.dart';
import 'package:gowithme/features/trip/presentation/trip_providers.dart';
import 'package:gowithme/features/vehicle/domain/vehicle.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';

const _siam = Place(point: LatLng(13.7455, 100.5345), label: 'สยาม');
const _rangsit = Place(point: LatLng(13.9, 100.6), label: 'รังสิต');
const _yaris = Vehicle(plate: '1กก 1234', model: 'Toyota Yaris', color: 'ขาว');

Future<void> _toStep2(WidgetTester tester, TravelMode mode) async {
  containerOf(tester).read(tripFormProvider.notifier)
    ..setOrigin(_siam)
    ..setDest(_rangsit);
  await goTo(tester, Routes.tripOptions);
  await tester.ensureVisible(find.text(mode.label));
  await tester.tap(find.text(mode.label));
  await tester.pumpAndSettle();
}

Future<void> _pickRole(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _createTrip(WidgetTester tester) async {
  await tester.tap(find.text(S.next));
  await tester.pumpAndSettle();
  await tester.tap(find.text(T.createTrip));
  await tester.pumpAndSettle();
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('DetourToleranceControl (US-50)', () {
    testWidgets('shows the formatted value, slider 200..2000 step 100, chips 200/500/1000/2000', (tester) async {
      int? picked;
      await tester.pumpWidget(_host(DetourToleranceControl(value: 500, onChanged: (v) => picked = v)));
      expect(tester.widget<Text>(find.byKey(const Key('detour-value'))).data, '500 ม.');
      final slider = tester.widget<Slider>(find.byKey(const Key('detour-slider')));
      expect((slider.min, slider.max, slider.divisions), (200, 2000, 18));
      for (final m in [200, 500, 1000, 2000]) {
        expect(find.byKey(Key('detour-chip-$m')), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('detour-chip-1000')));
      expect(picked, 1000);
      slider.onChanged!(650);
      expect(picked, 700, reason: 'snapped to the 100 m step');
    });

    testWidgets('locked: read-only with the reason, slider and chips disabled', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
          _host(DetourToleranceControl(value: 500, onChanged: (_) => calls++, lockedReason: R5.dropoffLockedReason)));
      expect(find.text(R5.dropoffLockedReason), findsOneWidget);
      expect(tester.widget<Slider>(find.byKey(const Key('detour-slider'))).onChanged, isNull);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('detour-chip-1000'))).onSelected, isNull);
      await tester.tap(find.byKey(const Key('detour-chip-1000')));
      expect(calls, 0);
    });

    test('form state clamps to the allowed range and step', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(tripFormProvider.notifier).setDetourTolerance(50);
      expect(c.read(tripFormProvider).detourToleranceM, 200);
      c.read(tripFormProvider.notifier).setDetourTolerance(99999);
      expect(c.read(tripFormProvider).detourToleranceM, 2000);
    });
  });

  group('create-trip form: both mechanisms are separate and driver-only', () {
    testWidgets('DropoffLimitControl and DetourToleranceControl are BOTH shown for a car Driver, defaults 2000/500',
        (tester) async {
      final f = Fakes()..vehicles.vehicle = _yaris;
      await openApp(tester, f);
      await _toStep2(tester, TravelMode.car);
      await _pickRole(tester, 'role-rider');
      expect(find.byKey(const Key('dropoff-control')), findsNothing);
      expect(find.byKey(const Key('detour-control')), findsNothing);

      await _pickRole(tester, 'role-driver');
      expect(find.byKey(const Key('dropoff-control')), findsOneWidget);
      expect(find.byKey(const Key('detour-control')), findsOneWidget);
      expect(containerOf(tester).read(tripFormProvider).detourToleranceM, 500);

      await tester.ensureVisible(find.byKey(const Key('detour-chip-1000')));
      await tester.tap(find.byKey(const Key('detour-chip-1000')));
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(tripFormProvider).detourToleranceM, 1000);

      await _createTrip(tester);
      expect(f.trips.created.single.role, TripRole.driver);
      expect(f.trips.created.single.detourToleranceM, 1000);
      expect(f.trips.created.single.maxDropoffM, 2000, reason: 'the two controls are independent');
    });

    testWidgets('a rider trip never carries detour_tolerance_m even after the driver value was changed',
        (tester) async {
      final f = Fakes()..vehicles.vehicle = _yaris;
      await openApp(tester, f);
      await _toStep2(tester, TravelMode.car);
      await _pickRole(tester, 'role-driver');
      containerOf(tester).read(tripFormProvider.notifier).setDetourTolerance(1500);
      await tester.pumpAndSettle();
      await _pickRole(tester, 'role-rider');
      await _createTrip(tester);
      expect(f.trips.created.single.role, TripRole.rider);
      expect(f.trips.created.single.detourToleranceM, isNull);
    });

    testWidgets('a non-car trip never carries it', (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await _toStep2(tester, TravelMode.walk);
      await _createTrip(tester);
      expect(f.trips.created.single.detourToleranceM, isNull);
    });
  });

  group('trip detail editor', () {
    testWidgets('editable when no request is open: saves the new value', (tester) async {
      final f = Fakes()
        ..trips.active =
            sampleTrip(mode: TravelMode.car, role: TripRole.driver, maxDropoffM: 2000, detourToleranceM: 500);
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      await tester.ensureVisible(find.byKey(const Key('detour-chip-1000')));
      await tester.tap(find.byKey(const Key('detour-chip-1000')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('detour-save')));
      await tester.tap(find.byKey(const Key('detour-save')));
      await tester.pumpAndSettle();
      expect(f.trips.detourUpdates, [('trip-1', 1000)]);
    });

    for (final st in [MatchStatus.pending, MatchStatus.accepted]) {
      testWidgets('locked with a reason while a ${st.db} match exists', (tester) async {
        final f = Fakes()
          ..trips.active =
              sampleTrip(mode: TravelMode.car, role: TripRole.driver, maxDropoffM: 2000, detourToleranceM: 500)
          ..matches.matches = [sampleMatch(status: st, myRole: TripRole.driver)];
        await openApp(tester, f);
        await goTo(tester, Routes.tripDetail('trip-1'));
        await tester.ensureVisible(find.byKey(const Key('detour-locked')));
        expect(find.text(R5.dropoffLockedReason), findsWidgets);
        expect(find.byKey(const Key('detour-save')), findsNothing);
        expect(tester.widget<Slider>(find.byKey(const Key('detour-slider'))).onChanged, isNull);
      });
    }

    testWidgets('not shown for a rider trip', (tester) async {
      final f = Fakes()..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.rider);
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      expect(find.byKey(const Key('detour-control')), findsNothing);
    });
  });
}
