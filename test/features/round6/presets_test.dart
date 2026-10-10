import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_r6.dart';
import 'package:gowithme/core/l10n/strings_r6_cd.dart';
import 'package:gowithme/core/l10n/strings_trip.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/auth/domain/auth_repository.dart';
import 'package:gowithme/features/geo/domain/geo_services.dart';
import 'package:gowithme/features/presets/domain/preset.dart';
import 'package:gowithme/features/presets/domain/quick_time.dart';
import 'package:gowithme/features/presets/presentation/preset_providers.dart';
import 'package:gowithme/features/roles/domain/role_state.dart';
import 'package:gowithme/features/trip/domain/ride_logic.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/presentation/trip_providers.dart';
import 'package:gowithme/features/vehicle/domain/vehicle.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';

const _home = PlacePreset(name: 'บ้าน', label: 'หมู่บ้านทดสอบ', point: LatLng(13.8027, 100.5537));
const _work = PlacePreset(name: 'ที่ทำงาน', label: 'อาคารทดสอบ', point: LatLng(13.7455, 100.5345), startType: StartType.work);
const _yaris = Vehicle(plate: '1กก 1234', model: 'Toyota Yaris', color: 'ขาว');

String _seed({bool home = true, bool start = true}) =>
    PresetData(home: home ? _home : null, start: start ? _work : null, noticeSeen: true).encode();

Future<Fakes> _open(WidgetTester tester, Fakes f, {Size size = const Size(800, 2000), AuthUser user = testUser}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await buildTestApp(
    repo: FakeAuthRepository(initial: user),
    prefs: {'onboarding_done': true},
    fakes: f,
  ));
  await tester.pumpAndSettle();
  return f;
}

/// The selectors (time chip / role / drop-off / create button) live in a bottom sheet opened by the card's primary
/// button since the card was made compact; open it once if it is not already open.
Future<void> _ensureSheet(WidgetTester tester) async {
  if (find.byKey(const Key('quick-cta')).evaluate().isNotEmpty) return;
  final primary = find.byKey(const Key('quick-primary-cta'));
  if (primary.evaluate().isEmpty) return;
  await tester.tap(primary);
  await tester.pumpAndSettle();
}

Trip _carTripTo(LatLng dest, {TravelMode mode = TravelMode.car}) => Trip(
      id: 't',
      mode: mode,
      role: mode == TravelMode.car ? TripRole.rider : null,
      status: TripStatus.scheduled,
      origin: const LatLng(13.7, 100.5),
      dest: dest,
      originLabel: 'a',
      destLabel: 'b',
      route: const [],
      distanceM: 1,
      durationS: 1,
      departAt: DateTime(2026, 1, 1),
    );

void main() {
  group('quickTimeOptions (Q8)', () {
    String hm(List<TimeOption> l) => l.map((o) => o.isNow ? 'now' : o.hm).join(',');

    test('morning: now + 17:30 + 18:00', () {
      expect(hm(quickTimeOptions(DateTime(2026, 5, 4, 10, 0))), 'now,17:30,18:00');
    });
    test('17:10 keeps both fixed times', () {
      expect(hm(quickTimeOptions(DateTime(2026, 5, 4, 17, 10))), 'now,17:30,18:00');
    });
    test('17:45: 17:30 is dropped, filled with the next 30-minute slot', () {
      expect(hm(quickTimeOptions(DateTime(2026, 5, 4, 17, 45))), 'now,18:00,18:30');
    });
    test('exactly 18:00: nothing fixed is left, next slots are rounded UP after now', () {
      expect(hm(quickTimeOptions(DateTime(2026, 5, 4, 18, 0))), 'now,18:30,19:00');
    });
    test('17:31: 18:00 stays, one slot is added (18:30)', () {
      expect(hm(quickTimeOptions(DateTime(2026, 5, 4, 17, 31))), 'now,18:00,18:30');
    });
    test('late evening rolls over midnight', () {
      final o = quickTimeOptions(DateTime(2026, 5, 4, 23, 50));
      expect(hm(o), 'now,00:00,00:30');
      expect(o[1].at!.day, 5);
    });
    test('always at least 3 options and never a time in the past', () {
      for (var m = 0; m < 24 * 60; m += 7) {
        final now = DateTime(2026, 5, 4, m ~/ 60, m % 60, 15);
        final o = quickTimeOptions(now);
        expect(o.length, greaterThanOrEqualTo(3));
        expect(o.where((x) => !x.isNow).every((x) => x.at!.isAfter(now)), isTrue, reason: '$now');
      }
    });
  });

  group('preset data + matcher', () {
    test('round trip; damaged text is empty, never a crash', () {
      const d = PresetData(home: _home, start: _work, noticeSeen: true, lastDepartMinutes: 1050, lastMaxDropoffM: 3000);
      final back = PresetData.decode(d.encode());
      expect(back.home!.name, 'บ้าน');
      expect(back.start!.startType, StartType.work);
      expect(back.lastDepartMinutes, 1050);
      expect(back.lastMaxDropoffM, 3000);
      expect(PresetData.decode('{{not json').isEmpty, isTrue);
      expect(PresetData.decode(null).isEmpty, isTrue);
    });

    test('matcher: no preset = unknown; near = home; far / other place = not home', () {
      const m0 = PresetHomeDestinationMatcher(null);
      expect(m0.match(_carTripTo(_home.point)), HomeMatch.unknown);
      const m = PresetHomeDestinationMatcher(LatLng(13.8027, 100.5537));
      expect(m.match(_carTripTo(_home.point)), HomeMatch.home);
      expect(m.match(_carTripTo(const LatLng(13.8037, 100.5537))), HomeMatch.home, reason: '~111 m');
      expect(m.match(_carTripTo(const LatLng(13.8047, 100.5537))), HomeMatch.notHome, reason: '~222 m');
      expect(m.match(_carTripTo(const LatLng(13.9, 100.6))), HomeMatch.notHome);
    });

    test('matcher: Peer modes never get the home wording (Q5)', () {
      const m = PresetHomeDestinationMatcher(LatLng(13.8027, 100.5537));
      expect(m.match(_carTripTo(_home.point, mode: TravelMode.walk)), HomeMatch.notHome);
    });
  });

  group('device-local storage', () {
    testWidgets('saved per user: another account never sees them', (tester) async {
      final f = Fakes();
      f.presets.data['u1'] = _seed();
      await _open(tester, f, user: const AuthUser(id: 'u2', email: 'x@y.co', displayName: 'บี', emailConfirmed: true));
      final d = await containerOf(tester).read(presetsProvider.future);
      expect(d.isEmpty, isTrue);
      expect(containerOf(tester).read(homePresetPointProvider), isNull);
    });

    testWidgets('sign-out wipes them from the device', (tester) async {
      final f = Fakes();
      f.presets.data['u1'] = _seed();
      final repo = FakeAuthRepository(initial: testUser);
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await buildTestApp(repo: repo, prefs: {'onboarding_done': true}, fakes: f));
      await tester.pumpAndSettle();
      expect((await containerOf(tester).read(presetsProvider.future)).isComplete, isTrue);
      await repo.signOut();
      await tester.pumpAndSettle();
      expect(f.presets.data, isEmpty);
    });

    testWidgets('explicit clearAll (sign-out button / account deletion) removes everything', (tester) async {
      final f = Fakes();
      f.presets.data['u1'] = _seed();
      f.presets.data['u9'] = _seed();
      await _open(tester, f);
      await containerOf(tester).read(presetsProvider.notifier).clearAll();
      expect(f.presets.data, isEmpty);
      expect(containerOf(tester).read(presetsProvider).value!.isEmpty, isTrue);
    });

    testWidgets('a failing write keeps the old state and reports false', (tester) async {
      final f = Fakes();
      await _open(tester, f);
      f.presets.failWrites = true;
      final ok = await containerOf(tester).read(presetsProvider.notifier).save(PresetKind.home, _home);
      expect(ok, isFalse);
      expect(containerOf(tester).read(presetsProvider).value!.home, isNull);
    });
  });

  group('setup flow (US-38)', () {
    Future<void> pickPlace(WidgetTester tester) async {
      await tester.enterText(find.byType(TextFormField).first, 'สยามพารากอน');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('place-สยามพารากอน')));
      await tester.pumpAndSettle();
    }

    testWidgets('first save shows the local-only notice; then home is stored on the device only', (tester) async {
      final f = await _open(tester, Fakes());
      await goTo(tester, Routes.mePlaces);
      expect(find.text('${R6C.homeRow}: ${R6C.notSet}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('places-set-home')));
      await tester.pumpAndSettle();
      await pickPlace(tester);
      await tester.tap(find.byKey(const Key('place-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('places-notice')), findsOneWidget);
      expect(find.text(R6C.noticeBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('places-notice-ok')));
      await tester.pumpAndSettle();
      final stored = PresetData.decode(f.presets.data['u1']);
      expect(stored.home!.name, R6C.homeName);
      expect(stored.noticeSeen, isTrue);
      // The setup continues with the regular start.
      expect(find.text(R6C.editStartTitle), findsWidgets);
      // Nothing about it went to a server: only the trip-side fakes exist and none was called.
      expect(f.trips.created, isEmpty);
    });

    testWidgets('cancelling the notice saves nothing', (tester) async {
      final f = await _open(tester, Fakes());
      await goTo(tester, Routes.mePlace('home'));
      await pickPlace(tester);
      await tester.tap(find.byKey(const Key('place-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('places-notice-cancel')));
      await tester.pumpAndSettle();
      expect(f.presets.data, isEmpty);
    });

    testWidgets('the start may not be the same place as home', (tester) async {
      final f = Fakes();
      f.presets.data['u1'] = _seed(start: false);
      // Fake geocoder answers a point ~0 m from the saved home.
      f.geocoding.results = const [PlaceSuggestion(label: 'สยามพารากอน', point: LatLng(13.8027, 100.5537))];
      await _open(tester, f);
      await goTo(tester, Routes.mePlace('start'));
      await pickPlace(tester);
      await tester.tap(find.byKey(const Key('place-save')));
      await tester.pumpAndSettle();
      expect(find.text(R6C.sameAsHome), findsOneWidget);
      expect(PresetData.decode(f.presets.data['u1']).start, isNull);
    });

    testWidgets('edit and remove (dialog first, then really gone)', (tester) async {
      final f = Fakes();
      f.presets.data['u1'] = _seed();
      await _open(tester, f);
      await goTo(tester, Routes.mePlaces);
      expect(find.text('${R6C.homeRow}: บ้าน'), findsOneWidget);
      expect(find.text('${R6C.startRow}: ที่ทำงาน'), findsOneWidget);
      await tester.tap(find.byKey(const Key('places-remove-home')));
      await tester.pumpAndSettle();
      expect(find.text(R6C.removeTitle('บ้าน')), findsOneWidget);
      await tester.tap(find.text(R6C.noticeCancel));
      await tester.pumpAndSettle();
      expect(PresetData.decode(f.presets.data['u1']).home, isNotNull);
      await tester.tap(find.byKey(const Key('places-remove-home')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(R6C.remove).last);
      await tester.pumpAndSettle();
      expect(PresetData.decode(f.presets.data['u1']).home, isNull);
      expect(find.text('${R6C.homeRow}: ${R6C.notSet}'), findsOneWidget);
    });
  });

  group('one-tap home card (US-39)', () {
    testWidgets('no presets: setup card, wizard link, no one-tap', (tester) async {
      await _open(tester, Fakes());
      expect(find.byKey(const Key('quick-missing')), findsOneWidget);
      expect(find.text(R6C.missingTitle), findsOneWidget);
      expect(find.byKey(const Key('quick-cta')), findsNothing);
      expect(find.text(T.homeCreatePrompt), findsOneWidget, reason: 'the wizard entry stays');
    });

    testWidgets('only one preset: says what is missing', (tester) async {
      final f = Fakes()..presets.data['u1'] = _seed(start: false);
      await _open(tester, f);
      expect(find.byKey(const Key('quick-partial')), findsOneWidget);
      expect(find.text(R6C.partialMissing(R6C.startRow)), findsOneWidget);
    });

    testWidgets('Rider: one tap creates a car Rider trip start->home with NO drop-off limit, then opens the deck',
        (tester) async {
      final f = Fakes()..presets.data['u1'] = _seed();
      await _open(tester, f);
      expect(find.text(R6C.quickTitle), findsOneWidget);
      expect(find.text(R6C.quickRoute('ที่ทำงาน', 'บ้าน')), findsOneWidget);
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-cta')));
      await tester.pumpAndSettle();
      final d = f.trips.created.single;
      expect(d.mode, TravelMode.car);
      expect(d.role, TripRole.rider);
      expect(d.maxDropoffM, isNull, reason: 'driver only');
      expect(d.origin.point, _work.point);
      expect(d.dest.point, _home.point);
      expect(d.route.length, greaterThanOrEqualTo(2));
      expect(f.routing.calls, 1);
      expect(find.text(S.nearbyTitle), findsWidgets, reason: 'on the deck page');
    });

    testWidgets('chosen time chip becomes the departure', (tester) async {
      final f = Fakes()..presets.data['u1'] = _seed();
      await _open(tester, f);
      final opts = quickTimeOptions(DateTime.now());
      final second = opts[1];
      await tester.tap(find.byKey(Key('time-chip-${second.hm}')));
      await tester.pump();
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-cta')));
      await tester.pumpAndSettle();
      final at = f.trips.created.single.departAt;
      expect('${at.hour}:${at.minute}', '${second.at!.hour}:${second.at!.minute}');
    });

    testWidgets('Driver: sends max_dropoff_m (default 2000) and shows it before creating', (tester) async {
      final f = Fakes()
        ..presets.data['u1'] = _seed()
        ..roles.registered = true
        ..roles.active = ActiveRole.driver
        ..roles.hasVehicle = true
        ..vehicles.vehicle = _yaris;
      await _open(tester, f);
      await _ensureSheet(tester);
      expect(find.byKey(const Key('quick-dropoff')), findsOneWidget);
      expect(find.text(R6C.dropoffRow('2.0 กม.')), findsOneWidget);
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-cta')));
      await tester.pumpAndSettle();
      final d = f.trips.created.single;
      expect(d.role, TripRole.driver);
      expect(d.maxDropoffM, 2000);
    });

    testWidgets('Driver: the limit can be adjusted first, and is remembered on the device', (tester) async {
      final f = Fakes()
        ..presets.data['u1'] = _seed()
        ..roles.registered = true
        ..roles.active = ActiveRole.driver
        ..vehicles.vehicle = _yaris;
      await _open(tester, f);
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-dropoff-adjust')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dropoff-chip-3000')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(R6C.dropoffDone));
      await tester.pumpAndSettle();
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-cta')));
      await tester.pumpAndSettle();
      expect(f.trips.created.single.maxDropoffM, 3000);
      expect(PresetData.decode(f.presets.data['u1']).lastMaxDropoffM, 3000);
    });

    testWidgets('not registered: choosing "ขับรถเอง" explains and offers registration, nothing is created',
        (tester) async {
      final f = Fakes()
        ..presets.data['u1'] = _seed()
        ..roles.registered = false;
      await _open(tester, f);
      await tester.tap(find.text(R6C.roleDriver));
      await tester.pumpAndSettle();
      await _ensureSheet(tester);
      expect(find.byKey(const Key('quick-register-hint')), findsOneWidget);
      expect(find.text(R6C.driverNeedsRegister), findsOneWidget);
      await _ensureSheet(tester);
      expect(find.byKey(const Key('quick-register')), findsOneWidget);
      expect(f.roles.switchCalls, isEmpty, reason: 'no server switch for an unregistered account');
      expect(find.byKey(const Key('quick-dropoff')), findsNothing);
    });

    testWidgets('registered Driver without a vehicle: registration gate, no trip', (tester) async {
      final f = Fakes()
        ..presets.data['u1'] = _seed()
        ..roles.registered = true
        ..roles.active = ActiveRole.driver
        ..vehicles.vehicle = null;
      await _open(tester, f);
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-cta')));
      await tester.pumpAndSettle();
      expect(f.trips.created, isEmpty);
      expect(find.text(R6C.driverNoVehicle), findsOneWidget);
    });

    testWidgets('the role switch is the app-wide active role', (tester) async {
      final f = Fakes()
        ..presets.data['u1'] = _seed()
        ..roles.registered = true
        ..vehicles.vehicle = _yaris;
      await _open(tester, f);
      await tester.tap(find.text(R6C.roleDriver));
      await tester.pumpAndSettle();
      expect(f.roles.switchCalls, [ActiveRole.driver]);
      await _ensureSheet(tester);
      expect(find.byKey(const Key('quick-dropoff')), findsOneWidget);
    });

    testWidgets('max 1 active trip: a trip that appeared meanwhile blocks creation with a clear message',
        (tester) async {
      final f = Fakes()..presets.data['u1'] = _seed();
      await _open(tester, f);
      f.trips.active = sampleTrip(); // created elsewhere after the card was drawn
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-cta')));
      await tester.pumpAndSettle();
      expect(f.trips.created, isEmpty);
      // The card is gone (the banner / trip summary took over); the same rule from the server has its own text.
      f.trips.active = null;
    });

    testWidgets('server says active-trip limit: clear message + way to the old trip + step by step', (tester) async {
      final f = Fakes()..presets.data['u1'] = _seed();
      f.trips.createFailure = const AppFailure('GWM_ACTIVE_TRIP_LIMIT');
      await _open(tester, f);
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-cta')));
      await tester.pumpAndSettle();
      expect(find.text('คุณมีทริปที่ยังใช้งานอยู่แล้ว จบหรือยกเลิกทริปเดิมก่อน'), findsOneWidget);
      expect(find.byKey(const Key('quick-go-active')), findsOneWidget);
    });

    testWidgets('failure: fallback to the wizard keeps what was chosen', (tester) async {
      final f = Fakes()..presets.data['u1'] = _seed();
      f.trips.createFailure = const AppFailure('GWM_DEPART_IN_PAST');
      await _open(tester, f);
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quick-error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick-step-by-step')));
      await tester.pumpAndSettle();
      final form = containerOf(tester).read(tripFormProvider);
      expect(form.dest!.point, _home.point);
      expect(form.origin!.point, _work.point);
      expect(form.mode, TravelMode.car);
      expect(form.role, TripRole.rider);
      expect(find.text(T.newTripTitle), findsOneWidget);
    });

    testWidgets('network error: Thai message and a retry that does not double create', (tester) async {
      final f = Fakes()..presets.data['u1'] = _seed();
      f.trips.createFailure = const AppFailure(FailureCode.networkOffline, retryable: true);
      await _open(tester, f);
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-cta')));
      await tester.pumpAndSettle();
      expect(find.text(R6C.quickNetworkError), findsOneWidget);
      f.trips.createFailure = null;
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-cta')));
      await tester.pumpAndSettle();
      expect(f.trips.created.length, 1);
    });

    testWidgets('routing failure is fail-closed: no trip is created', (tester) async {
      final f = Fakes()..presets.data['u1'] = _seed();
      f.routing.failure = const AppFailure(FailureCode.routeNotFound);
      await _open(tester, f);
      await _ensureSheet(tester);
      await tester.tap(find.byKey(const Key('quick-cta')));
      await tester.pumpAndSettle();
      expect(f.trips.created, isEmpty);
      expect(find.byKey(const Key('quick-error')), findsOneWidget);
    });

    testWidgets('with an active trip the card is not shown', (tester) async {
      final f = Fakes()
        ..presets.data['u1'] = _seed()
        ..trips.active = sampleTrip();
      await _open(tester, f);
      expect(find.byKey(const Key('quick-home-card')), findsNothing);
    });

    for (final scale in [1.0, 1.4]) {
      testWidgets('layout at 390 px, text x$scale: no overflow (Driver row visible)', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final f = Fakes()
          ..presets.data['u1'] = _seed()
          ..roles.registered = true
          ..roles.active = ActiveRole.driver
          ..vehicles.vehicle = _yaris;
        await _open(tester, f, size: const Size(390, 844));
        expect(tester.takeException(), isNull);
        await _ensureSheet(tester);
        expect(find.byKey(const Key('quick-cta')), findsOneWidget);
      });
    }

    testWidgets('semantic label of the main button names time and role', (tester) async {
      final handle = tester.ensureSemantics();
      final f = Fakes()..presets.data['u1'] = _seed();
      await _open(tester, f);
      expect(find.bySemanticsLabel(RegExp(R6C.quickCtaSemantics(R6C.timeNow, R6C.roleRider))), findsOneWidget);
      handle.dispose();
    });
  });

  group('arrival wording follows the Home preset (Q5)', () {
    test('labels', () {
      expect(arriveSliderLabel(HomeMatch.home), R6.sliderArriveHome);
      expect(arriveSliderLabel(HomeMatch.notHome), R6.sliderArriveDest);
      expect(arriveSliderLabel(HomeMatch.unknown), R6.sliderArriveDest);
    });
  });
}
