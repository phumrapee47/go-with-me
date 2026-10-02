import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gowithme/core/l10n/strings_trip.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/auth/presentation/auth_providers.dart';
import 'package:gowithme/features/geo/domain/geo_services.dart';
import 'package:gowithme/features/geo/domain/location_service.dart';
import 'package:gowithme/features/geo/presentation/geo_providers.dart';
import 'package:gowithme/features/privacy/presentation/consent_providers.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/presentation/create_trip_step1_screen.dart';
import 'package:gowithme/features/trip/presentation/trip_providers.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';
import '../../support/p4_helpers.dart' show testUser;

/// BUG-3 (round 8): validation used to only recompute inside `_next()`, so a
/// stale "select origin" error survived origin/dest changes made via the
/// search field, "use current location", or the map-pin flow. These tests
/// cover all 3 entry points plus the "no false-positive on a fresh screen"
/// and "next still navigates once valid" regressions.
///
/// A minimal `GoRouter` (rather than the full app harness) is used on
/// purpose: it isolates this screen's own reactive-validation logic from the
/// rest of the app's boot sequence (splash video, auth, other tabs) that
/// this bug fix never touches.
class _Harness {
  _Harness()
      : geocoding = FakeGeocoding(),
        location = FakeLocationService(),
        trips = FakeTripRepository();

  final FakeGeocoding geocoding;
  final FakeLocationService location;
  final FakeTripRepository trips;

  late final router = GoRouter(
    initialLocation: Routes.tripNew,
    routes: [
      GoRoute(path: Routes.tripNew, builder: (_, _) => const CreateTripStep1Screen()),
      GoRoute(
        path: Routes.tripOptions,
        builder: (_, _) => const Scaffold(body: Text('step2-placeholder')),
      ),
      GoRoute(path: Routes.home, builder: (_, _) => const Scaffold(body: Text('home'))),
    ],
  );

  Widget build() => ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(testUser)),
          tripRepositoryProvider.overrideWithValue(trips),
          geocodingServiceProvider.overrideWithValue(geocoding),
          locationServiceProvider.overrideWithValue(location),
          consentRepositoryProvider.overrideWithValue(FakeConsentRepository()),
          mapTilesEnabledProvider.overrideWithValue(false),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
}

Future<_Harness> _open(WidgetTester tester) async {
  final h = _Harness();
  await tester.pumpWidget(h.build());
  await tester.pumpAndSettle();
  return h;
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('ถัดไป'));
  await tester.pumpAndSettle();
}

/// Confirms the map-pin flow for the origin field (2nd "ปักหมุดบนแผนที่"
/// button: destination field is built first, origin field second).
Future<void> _pinOrigin(WidgetTester tester) async {
  await tester.tap(find.text(T.pickOnMap).at(1));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('pick-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fresh screen: no error shown before any interaction', (tester) async {
    await _open(tester);
    expect(find.text(T.errOriginMissing), findsNothing);
    expect(find.text(T.errDestMissing), findsNothing);
  });

  testWidgets('main bug: pinning the origin on the map clears the stale "select origin" error immediately',
      (tester) async {
    await _open(tester);
    await _next(tester); // origin + dest both missing -> shows an error
    expect(find.text(T.errOriginMissing), findsOneWidget);

    await _pinOrigin(tester);

    // Origin is set now, but dest is still missing: the origin error must be
    // gone immediately (no extra tap on "ถัดไป" needed), replaced by the dest one.
    expect(find.text(T.errOriginMissing), findsNothing);
    expect(find.text(T.errDestMissing), findsOneWidget);
  });

  testWidgets('regression: setting origin via the search flow clears the error immediately', (tester) async {
    final h = await _open(tester);
    h.geocoding.results = const [PlaceSuggestion(label: 'สยามพารากอน', point: LatLng(13.7462, 100.5347))];
    await _next(tester);
    expect(find.text(T.errOriginMissing), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('origin-field')), 'สยาม');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'สยามพารากอน'));
    await tester.pumpAndSettle();

    expect(find.text(T.errOriginMissing), findsNothing);
  });

  testWidgets('regression: "use current location" clears the error immediately', (tester) async {
    final h = await _open(tester);
    h.location.state = LocationPermissionState.granted; // skip the consent dialog
    await _next(tester);
    expect(find.text(T.errOriginMissing), findsOneWidget);

    await tester.tap(find.text(T.useCurrent));
    await tester.pumpAndSettle();

    expect(find.text(T.errOriginMissing), findsNothing);
  });

  testWidgets('regression: "next" still navigates to step 2 once origin+dest are valid', (tester) async {
    final h = await _open(tester);
    await _pinOrigin(tester);
    // Dest is set directly (far enough from the pinned origin) so this case
    // isolates "next navigates once both places are valid" from the map
    // widget's own default-centre behaviour, which is covered separately by
    // the main-bug test above.
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(tripFormProvider.notifier)
        .setDest(const Place(point: LatLng(13.9, 100.6), label: 'รังสิต'));
    await tester.pumpAndSettle();

    await _next(tester);

    expect(find.text('step2-placeholder'), findsOneWidget);
    // Unused otherwise; keeps the harness reference alive for clarity/lint.
    expect(h.trips.created, isEmpty);
  });
}
