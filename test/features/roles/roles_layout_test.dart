import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_roles.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/presentation/trip_providers.dart';
import 'package:gowithme/features/vehicle/domain/vehicle.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';

const _width = 390.0;

List<String> _clipped(WidgetTester tester) {
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) continue;
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
    final left = box.localToGlobal(Offset.zero).dx;
    if (right > _width + 0.5 || left < -0.5) {
      final w = e.widget as Text;
      out.add('${w.data ?? w.textSpan} (left=$left right=$right)');
    }
  }
  return out;
}

Trip _trip(TripRole role, {TripStatus status = TripStatus.scheduled}) =>
    sampleTrip(mode: TravelMode.car, role: role).copyWith(status: status, startedAt: DateTime.now());

Fakes _rider() => Fakes()
  ..vehicles.view = const VehicleView(plate: '1กก 1234 กรุงเทพมหานคร', model: 'Toyota Corolla Cross', color: 'เทา/เงิน', shareAllowed: true)
  ..trips.active = _trip(TripRole.rider, status: TripStatus.inProgress)
  ..finder.result = [sampleCandidate(name: 'คนขับใจดีมาก', mode: TravelMode.car, role: TripRole.driver)]
  ..matches.matches = [
    sampleMatch(status: MatchStatus.accepted, myRole: TripRole.rider, partnerTripStatus: TripStatus.inProgress, name: 'คนขับใจดีมาก')
        .copyWith(
      meetingPoint: const LatLng(13.75, 100.53),
      meetingLabel: 'หน้าสถานีรถไฟฟ้าสยามพารากอนทางออกที่ 3',
    ),
  ];

Fakes _driver() => Fakes()
  ..vehicles.vehicle = const Vehicle(plate: '1กก 1234 กรุงเทพมหานคร', model: 'Toyota Corolla Cross', color: 'เทา/เงิน')
  ..trips.active = _trip(TripRole.driver, status: TripStatus.inProgress)
  ..finder.result = [sampleCandidate(name: 'คนนั่ง', mode: TravelMode.car, role: TripRole.rider)]
  ..matches.matches = [sampleMatch(status: MatchStatus.accepted, myRole: TripRole.driver, name: 'คนนั่ง')];

void main() {
  for (final scale in [1.0, 1.4]) {
    group('roles at 390 px, text scale $scale: nothing clipped or overflowing', () {
      Future<void> open(WidgetTester tester, Fakes f) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await openApp(tester, f, size: const Size(_width, 844));
      }

      Future<void> check(WidgetTester tester) async {
        expect(tester.takeException(), isNull);
        expect(_clipped(tester), isEmpty);
      }

      testWidgets('Rider: nearby, match page, active trip, chat, share', (tester) async {
        await open(tester, _rider());
        await tester.tap(find.text(S.tabNearby));
        await tester.pumpAndSettle();
        await check(tester);
        for (final r in [
          Routes.match('m1'),
          Routes.tripActive('trip-1'),
          Routes.chat('m1'),
          Routes.tripShare('trip-1'),
          Routes.tripDetail('trip-1'),
        ]) {
          await goTo(tester, r);
          await check(tester);
          await goBack(tester);
        }
      });

      testWidgets('Driver: nearby, match page, active trip, vehicle form', (tester) async {
        await open(tester, _driver());
        await tester.tap(find.text(S.tabNearby));
        await tester.pumpAndSettle();
        await check(tester);
        for (final r in [Routes.match('m1'), Routes.tripActive('trip-1'), Routes.vehicle, Routes.tripDetail('trip-1')]) {
          await goTo(tester, r);
          await check(tester);
          await goBack(tester);
        }
      });

      testWidgets('create-trip step 2 with the role picker (Driver, with vehicle)', (tester) async {
        final f = Fakes()..vehicles.vehicle = const Vehicle(plate: '1กก 1234', model: 'Toyota Yaris', color: 'ขาว');
        await open(tester, f);
        f.trips.active = null;
        containerOf(tester).invalidate(activeTripProvider);
        containerOf(tester).read(tripFormProvider.notifier)
          ..setOrigin(const Place(point: LatLng(13.7455, 100.5345), label: 'สยาม'))
          ..setDest(const Place(point: LatLng(13.9, 100.6), label: 'รังสิต'))
          ..setMode(TravelMode.car)
          ..setRole(TripRole.driver);
        await goTo(tester, Routes.tripOptions);
        await tester.scrollUntilVisible(find.byKey(const Key('role-picker')), 300);
        expect(find.byKey(const Key('role-picker')), findsOneWidget);
        await check(tester);
      });

      testWidgets('match-ended alert card', (tester) async {
        final f = _rider();
        await open(tester, f);
        f.matches.matches = [
          sampleMatch(status: MatchStatus.cancelled, myRole: TripRole.rider, name: 'คนขับใจดีมาก'),
        ];
        f.matches.emitChange();
        await tester.pumpAndSettle();
        expect(find.text(R.alertTitle), findsOneWidget);
        await check(tester);
      });
    });
  }
}
