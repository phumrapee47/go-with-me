import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/geo/geo.dart';
import 'package:gowithme/core/l10n/strings_roles.dart';
import 'package:gowithme/features/geo/domain/geo_services.dart';
import 'package:gowithme/features/geo/presentation/geo_providers.dart';
import 'package:gowithme/features/geo/presentation/pick_point_screen.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';

const _raw = LatLng(13.7460, 100.5340);

class _FakeSnap implements RoadSnapService {
  _FakeSnap.accept() : _mode = 0;
  _FakeSnap.reject() : _mode = 1;
  _FakeSnap.fail() : _mode = 2;
  final int _mode;
  int calls = 0;

  @override
  Future<SnapResult> nearest({required TravelMode mode, required LatLng point}) async {
    calls++;
    switch (_mode) {
      case 0:
        final p = LatLng(point.latitude + 0.0002, point.longitude); // ~22 m, within default 40 m limit
        return SnapResult(point: p, deviationM: haversineM(point, p));
      case 1:
        final p = LatLng(point.latitude + 0.002, point.longitude); // ~222 m, over the limit
        return SnapResult(point: p, deviationM: haversineM(point, p));
      default:
        throw const AppFailure(FailureCode.serverUnavailable, retryable: true);
    }
  }
}

Future<void> _pump(WidgetTester tester, RoadSnapService snap, void Function(Place) onPicked) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mapTilesEnabledProvider.overrideWithValue(false),
        geocodingServiceProvider.overrideWithValue(FakeGeocoding()),
        roadSnapServiceProvider.overrideWithValue(snap),
      ],
      child: MaterialApp(
        home: PickPointScreen(
          title: 'test',
          initial: _raw,
          snapMode: TravelMode.car,
          onPicked: (p) async {
            onPicked(p);
            return false; // stay on screen so we can inspect the marker state
          },
        ),
      ),
    ),
  );
  await tester.pump(); // let the reverse-geocode debounce timer get scheduled
}

/// Controlled by the test (a `Completer`) so the transient "snapping" state
/// is observable, unlike `_FakeSnap` whose zero-delay future can resolve
/// before the next pump ever renders it.
class _ControlledSnap implements RoadSnapService {
  final _completer = Completer<SnapResult>();

  @override
  Future<SnapResult> nearest({required TravelMode mode, required LatLng point}) => _completer.future;

  void resolve(SnapResult r) => _completer.complete(r);
}

void main() {
  testWidgets('shows the transient "snapping" state while the lookup is in flight', (tester) async {
    final snap = _ControlledSnap();
    await _pump(tester, snap, (_) {});

    await tester.tap(find.byKey(const Key('pick-confirm')));
    await tester.pump();
    expect(find.text(R.pickupSnapping), findsOneWidget);
    expect(find.bySemanticsLabel(R.pickupMarkerA11yRaw), findsOneWidget); // not yet snapped

    final p = LatLng(_raw.latitude + 0.0002, _raw.longitude);
    snap.resolve(SnapResult(point: p, deviationM: haversineM(_raw, p)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(R.pickupSnapping), findsNothing);
    expect(find.text(R.pickupSnappedToast), findsOneWidget);
  });

  testWidgets('accepted snap: shows the toast and moves the marker', (tester) async {
    Place? got;
    await _pump(tester, _FakeSnap.accept(), (p) => got = p);

    await tester.tap(find.byKey(const Key('pick-confirm')));
    await tester.pump(const Duration(milliseconds: 400)); // fetch + move animation
    expect(find.text(R.pickupSnappedToast), findsOneWidget);
    expect(got, isNotNull);
    expect(got!.point.latitude, closeTo(_raw.latitude + 0.0002, 1e-6));

    // The a11y label announces the marker changed to "snapped".
    expect(find.bySemanticsLabel(R.pickupMarkerA11ySnapped), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text(R.pickupSnappedToast), findsNothing); // caption clears itself
  });

  testWidgets('deviation beyond the threshold: silent, keeps the raw point', (tester) async {
    Place? got;
    await _pump(tester, _FakeSnap.reject(), (p) => got = p);

    await tester.tap(find.byKey(const Key('pick-confirm')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(R.pickupSnappedToast), findsNothing);
    expect(find.text(R.pickupSnapFallbackToast), findsNothing);
    expect(got, isNotNull);
    expect(got!.point, _raw); // unchanged: raw point kept
    expect(find.bySemanticsLabel(R.pickupMarkerA11yRaw), findsOneWidget);
  });

  testWidgets('service failure: fail-open with a small caption, never blocks proposing', (tester) async {
    Place? got;
    await _pump(tester, _FakeSnap.fail(), (p) => got = p);

    await tester.tap(find.byKey(const Key('pick-confirm')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(R.pickupSnapFallbackToast), findsOneWidget);
    expect(got, isNotNull);
    expect(got!.point, _raw); // unchanged: raw point kept
  });

  testWidgets('snapMode null: never calls the snap service', (tester) async {
    final snap = _FakeSnap.accept();
    Place? got;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapTilesEnabledProvider.overrideWithValue(false),
          geocodingServiceProvider.overrideWithValue(FakeGeocoding()),
          roadSnapServiceProvider.overrideWithValue(snap),
        ],
        child: MaterialApp(
          home: PickPointScreen(
            title: 'test',
            initial: _raw,
            // snapMode intentionally omitted (null) — plain origin/destination picking.
            onPicked: (p) async {
              got = p;
              return false;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('pick-confirm')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(snap.calls, 0);
    expect(got, isNotNull);
    expect(got!.point, _raw);
  });
}
