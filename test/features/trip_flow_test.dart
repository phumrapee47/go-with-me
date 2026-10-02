import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_trip.dart';
import 'package:gowithme/features/auth/domain/auth_repository.dart';
import 'package:gowithme/features/geo/domain/geo_services.dart';
import 'package:gowithme/features/geo/domain/location_service.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:latlong2/latlong.dart';

import '../support/fake_repos.dart';
import '../support/fakes.dart';

const _user = AuthUser(id: 'u1', email: 'a@b.co', displayName: 'มิ้นท์', emailConfirmed: true);

Future<Fakes> _open(WidgetTester tester, {Fakes? fakes}) async {
  final f = fakes ?? Fakes();
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await buildTestApp(
    repo: FakeAuthRepository(initial: _user),
    prefs: {'onboarding_done': true},
    fakes: f,
  ));
  await tester.pumpAndSettle();
  return f;
}

Future<void> _startFlow(WidgetTester tester) async {
  await tester.tap(find.text(T.homeCreatePrompt));
  await tester.pumpAndSettle();
  expect(find.text(T.stepOf.replaceFirst('%s', '1')), findsOneWidget);
}

Future<void> _pickDestBySearch(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'สยามพารากอน');
  // Nothing is sent before the 800 ms debounce elapses.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('place-สยามพารากอน')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('full create-trip flow uploads route + client UUID and lands on nearby', (tester) async {
    final f = await _open(tester);
    f.location.state = LocationPermissionState.denied; // first use: consent shown

    await _startFlow(tester);
    await _pickDestBySearch(tester);
    expect(f.geocoding.queries, ['สยามพารากอน']);

    // Current location: rationale dialog, consent logged, then OS prompt.
    await tester.tap(find.text(T.useCurrent));
    await tester.pumpAndSettle();
    expect(find.text(T.locConsentTitle), findsOneWidget);
    await tester.tap(find.text(T.locConsentAllow));
    await tester.pumpAndSettle();
    expect(f.consent.recorded, 1);
    expect(f.location.requests, 1);

    // The fake position is several km from the destination: valid.
    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();
    expect(find.text(T.departQuestion), findsOneWidget);

    // Next stays disabled until a mode is chosen (single-select).
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, S.next)).onPressed, isNull);
    await tester.tap(find.text(TravelMode.car.label));
    await tester.pump();
    await tester.tap(find.text(TravelMode.walk.label)); // switching replaces the choice
    await tester.pump();
    await tester.tap(find.text(TravelMode.car.label));
    await tester.pump();
    // Car needs an explicit role (US-16): Next stays disabled until one is chosen.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, S.next)).onPressed, isNull);
    await tester.ensureVisible(find.byKey(const Key('role-rider')));
    await tester.tap(find.byKey(const Key('role-rider')));
    await tester.pump();
    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();

    // Step 3: route preview then create.
    expect(find.text(T.confirmTitle), findsOneWidget);
    expect(find.text('ประมาณ 8.4 กม. ราว 25 นาที'), findsOneWidget);
    await tester.tap(find.text(T.createTrip));
    await tester.pumpAndSettle();

    expect(f.trips.created.length, 1);
    final d = f.trips.created.single;
    expect(d.mode, TravelMode.car);
    expect(d.role, TripRole.rider);
    expect(d.route.length, greaterThanOrEqualTo(2));
    expect(d.distanceM, 8400);
    expect(d.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(d.dest.label, 'สยามพารากอน');
    expect(find.text(S.nearbyTitle), findsWidgets); // now on /nearby
  });

  testWidgets('denied location never blocks the flow: search + pin path still works', (tester) async {
    final f = await _open(tester);
    f.location.state = LocationPermissionState.deniedForever;
    await _startFlow(tester);

    await tester.tap(find.text(T.useCurrent));
    await tester.pumpAndSettle();
    // Not asked again for deniedForever; explains and stays on the form.
    expect(find.text(T.locConsentTitle), findsNothing);
    expect(find.text(T.locOpenSettings), findsOneWidget);

    await _pickDestBySearch(tester);
    // Let the floating snackbar go away so it does not cover the Next button.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    // Without an origin, Next reports the missing origin instead of crashing.
    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();
    expect(find.text(T.errOriginMissing), findsOneWidget);
  });

  testWidgets('step 1 rejects places closer than 200 m', (tester) async {
    final f = await _open(tester);
    f.location.state = LocationPermissionState.granted;
    // Destination within ~50 m of the fake current position.
    f.geocoding.results = const [
      PlaceSuggestion(label: 'ใกล้มาก', point: LatLng(13.74552, 100.5345)),
    ];
    await _startFlow(tester);
    await tester.tap(find.text(T.useCurrent));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'ใกล้มาก');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('place-ใกล้มาก')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();
    expect(find.text(T.errTooClose), findsOneWidget);
    expect(find.text(T.departQuestion), findsNothing);
  });

  testWidgets('home shows the active trip instead of the create prompt', (tester) async {
    final fakes = Fakes()..trips.active = sampleTrip();
    await _open(tester, fakes: fakes);
    expect(find.text(T.homeCreatePrompt), findsNothing);
    expect(find.text(T.homeMyTrip), findsOneWidget);
  });

  testWidgets('routing failure is fail-closed: create stays disabled and retry works', (tester) async {
    final f = Fakes();
    f.routing.failure = const AppFailure(FailureCode.serverUnavailable, retryable: true);
    f.location.state = LocationPermissionState.granted;
    await _open(tester, fakes: f);
    await _startFlow(tester);
    await tester.tap(find.text(T.useCurrent));
    await tester.pumpAndSettle();
    await _pickDestBySearch(tester);
    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TravelMode.taxi.label));
    await tester.pump();
    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();

    expect(find.text(T.routeFailed), findsOneWidget);
    final create = find.widgetWithText(FilledButton, T.createTrip);
    expect(tester.widget<FilledButton>(create).onPressed, isNull);

    f.routing.failure = null;
    await tester.tap(find.text(S.retry));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
  });

  testWidgets('server rejection shows a Thai message and keeps the form', (tester) async {
    final f = Fakes();
    f.trips.createFailure = const AppFailure('GWM_ACTIVE_TRIP_LIMIT');
    f.location.state = LocationPermissionState.granted;
    await _open(tester, fakes: f);
    await _startFlow(tester);
    await tester.tap(find.text(T.useCurrent));
    await tester.pumpAndSettle();
    await _pickDestBySearch(tester);
    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TravelMode.walk.label));
    await tester.pump();
    await tester.tap(find.text(S.next));
    await tester.pumpAndSettle();
    await tester.tap(find.text(T.createTrip));
    await tester.pumpAndSettle();
    expect(find.textContaining('ทริปที่ยังใช้งานอยู่'), findsOneWidget);
    expect(find.text(T.confirmTitle), findsOneWidget);
  });
}
