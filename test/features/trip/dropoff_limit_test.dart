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
  group('DropoffLimitControl', () {
    testWidgets('shows the formatted value, slider 500..5000 step 100, chips 1000/2000/3000/5000', (tester) async {
      int? picked;
      await tester.pumpWidget(_host(DropoffLimitControl(value: 2000, onChanged: (v) => picked = v)));
      expect(find.text(R5.dropoffLabel), findsOneWidget);
      expect(find.text(R5.dropoffHelper), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('dropoff-value'))).data, '2.0 กม.');
      final slider = tester.widget<Slider>(find.byKey(const Key('dropoff-slider')));
      expect((slider.min, slider.max, slider.divisions), (500, 5000, 45));
      for (final m in [1000, 2000, 3000, 5000]) {
        expect(find.byKey(Key('dropoff-chip-$m')), findsOneWidget);
      }
      expect(find.byKey(const Key('dropoff-chip-4000')), findsNothing);
      await tester.tap(find.byKey(const Key('dropoff-chip-3000')));
      expect(picked, 3000);
      slider.onChanged!(750);
      expect(picked, 800, reason: 'snapped to the 100 m step');
    });

    testWidgets('value text below 1 km is in metres', (tester) async {
      await tester.pumpWidget(_host(DropoffLimitControl(value: 500, onChanged: (_) {})));
      expect(tester.widget<Text>(find.byKey(const Key('dropoff-value'))).data, '500 ม.');
    });

    testWidgets('locked: read-only with the reason, slider and chips disabled', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
          _host(DropoffLimitControl(value: 2000, onChanged: (_) => calls++, lockedReason: R5.dropoffLockedReason)));
      expect(find.text(R5.dropoffLockedReason), findsOneWidget);
      expect(find.text(R5.dropoffHelper), findsNothing);
      expect(tester.widget<Slider>(find.byKey(const Key('dropoff-slider'))).onChanged, isNull);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('dropoff-chip-3000'))).onSelected, isNull);
      await tester.tap(find.byKey(const Key('dropoff-chip-3000')));
      expect(calls, 0);
    });
  });

  group('create-trip form', () {
    testWidgets('the control appears only for a car Driver, defaults to 2000 and is sent only for driver trips',
        (tester) async {
      final f = Fakes()..vehicles.vehicle = _yaris;
      await openApp(tester, f);
      await _toStep2(tester, TravelMode.car);
      await _pickRole(tester, 'role-rider');
      expect(find.byKey(const Key('dropoff-control')), findsNothing);

      await _pickRole(tester, 'role-driver');
      expect(find.byKey(const Key('dropoff-control')), findsOneWidget);
      expect(containerOf(tester).read(tripFormProvider).maxDropoffM, 2000);
      await tester.ensureVisible(find.byKey(const Key('dropoff-chip-3000')));
      await tester.tap(find.byKey(const Key('dropoff-chip-3000')));
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(tripFormProvider).maxDropoffM, 3000);

      await _createTrip(tester);
      expect(f.trips.created.single.role, TripRole.driver);
      expect(f.trips.created.single.maxDropoffM, 3000);
    });

    testWidgets('a rider trip never carries max_dropoff_m even after the driver value was changed', (tester) async {
      final f = Fakes()..vehicles.vehicle = _yaris;
      await openApp(tester, f);
      await _toStep2(tester, TravelMode.car);
      await _pickRole(tester, 'role-driver');
      containerOf(tester).read(tripFormProvider.notifier).setMaxDropoff(4000);
      await tester.pumpAndSettle();
      await _pickRole(tester, 'role-rider');
      await _createTrip(tester);
      expect(f.trips.created.single.role, TripRole.rider);
      expect(f.trips.created.single.maxDropoffM, isNull);
    });

    testWidgets('a non-car trip never carries it', (tester) async {
      final f = Fakes();
      await openApp(tester, f);
      await _toStep2(tester, TravelMode.walk);
      await _createTrip(tester);
      expect(f.trips.created.single.maxDropoffM, isNull);
    });

    test('form state clamps to the allowed range and step', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(tripFormProvider.notifier).setMaxDropoff(120);
      expect(c.read(tripFormProvider).maxDropoffM, 500);
      c.read(tripFormProvider.notifier).setMaxDropoff(99999);
      expect(c.read(tripFormProvider).maxDropoffM, 5000);
    });
  });

  group('trip detail editor', () {
    testWidgets('editable when no request is open: saves the new value', (tester) async {
      final f = Fakes()..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.driver, maxDropoffM: 2000);
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      await tester.ensureVisible(find.byKey(const Key('dropoff-chip-3000')));
      await tester.tap(find.byKey(const Key('dropoff-chip-3000')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('dropoff-save')));
      await tester.tap(find.byKey(const Key('dropoff-save')));
      await tester.pumpAndSettle();
      expect(f.trips.dropoffUpdates, [('trip-1', 3000)]);
    });

    for (final st in [MatchStatus.pending, MatchStatus.accepted]) {
      testWidgets('locked with a reason while a ${st.db} match exists', (tester) async {
        final f = Fakes()
          ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.driver, maxDropoffM: 2000)
          ..matches.matches = [sampleMatch(status: st, myRole: TripRole.driver)];
        await openApp(tester, f);
        await goTo(tester, Routes.tripDetail('trip-1'));
        await tester.ensureVisible(find.byKey(const Key('dropoff-locked')));
        expect(find.text(R5.dropoffLockedReason), findsOneWidget);
        expect(find.byKey(const Key('dropoff-save')), findsNothing);
        expect(tester.widget<Slider>(find.byKey(const Key('dropoff-slider'))).onChanged, isNull);
      });
    }

    testWidgets('not shown for a rider trip', (tester) async {
      final f = Fakes()..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.rider);
      await openApp(tester, f);
      await goTo(tester, Routes.tripDetail('trip-1'));
      expect(find.byKey(const Key('dropoff-control')), findsNothing);
    });
  });

  testWidgets('a candidate without a destination opens the detail card (no destination area)', (tester) async {
    final f = Fakes()
      ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.driver)
      ..finder.result = [
        MatchCandidate(
          tripId: 'c1',
          displayName: 'คนนั่ง',
          badges: const [],
          mode: TravelMode.car,
          departAt: DateTime.now().add(const Duration(minutes: 10)),
          timeDiffMin: 2,
          overlapPct: 80,
          approxDistanceM: 5000,
          score: 90,
          approxOrigin: const LatLng(13.75, 100.53),
          approxDest: null,
          requestStatus: null,
          role: TripRole.rider,
        ),
      ];
    await openApp(tester, f);
    await tester.tap(find.text(S.tabNearby));
    await tester.pumpAndSettle();
    expect(find.text('คนนั่ง'), findsWidgets);
    await tester.tap(find.text('คนนั่ง').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
