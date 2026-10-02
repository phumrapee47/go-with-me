import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/geo/domain/geo_services.dart';
import 'package:gowithme/features/geo/presentation/geo_providers.dart';
import 'package:gowithme/features/geo/presentation/place_search_field.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';

/// BUG-1 (round 8): renders the results list from a geocoder that returns
/// duplicate label+point rows and asserts Flutter never throws a duplicate
/// GlobalKey/ValueKey assertion while building the widget tree.
Future<void> _pump(WidgetTester tester, FakeGeocoding geo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [geocodingServiceProvider.overrideWithValue(geo)],
      child: MaterialApp(
        home: Scaffold(
          body: PlaceSearchField(
            label: 'ปลายทาง',
            place: null,
            onSelected: (_) {},
            onCleared: () {},
            onPickOnMap: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('does not crash and dedups when the geocoder returns duplicate results', (tester) async {
    final geo = FakeGeocoding()
      ..results = const [
        PlaceSuggestion(label: 'สยามพารากอน', point: LatLng(13.7462, 100.5347)),
        PlaceSuggestion(label: 'สยามพารากอน', point: LatLng(13.7462, 100.5347)),
        PlaceSuggestion(label: 'เซ็นทรัลเวิลด์', point: LatLng(13.7469, 100.5392)),
      ];
    await _pump(tester, geo);

    await tester.enterText(find.byType(TextField), 'สยาม');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // No duplicate-key assertion was thrown during the pumps above, and the
    // rendered list must be deduped down to 2 tiles.
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(ListTile, 'สยามพารากอน'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'เซ็นทรัลเวิลด์'), findsOneWidget);
  });

  testWidgets('regression: distinct results all render', (tester) async {
    final geo = FakeGeocoding()
      ..results = const [
        PlaceSuggestion(label: 'A', point: LatLng(1, 1)),
        PlaceSuggestion(label: 'B', point: LatLng(2, 2)),
        PlaceSuggestion(label: 'C', point: LatLng(3, 3)),
      ];
    await _pump(tester, geo);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ListTile), findsNWidgets(3));
  });
}
