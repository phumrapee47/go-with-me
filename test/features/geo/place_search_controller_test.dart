import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/features/geo/domain/geo_services.dart';
import 'package:gowithme/features/geo/presentation/place_search_controller.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  PlaceSearchController make(FakeGeocoding g) =>
      PlaceSearchController(g, debounce: const Duration(milliseconds: 40));

  test('does not search below 3 characters', () async {
    final g = FakeGeocoding();
    final c = make(g);
    c.onQueryChanged('ab');
    await _wait(80);
    expect(g.queries, isEmpty);
    expect(c.status, PlaceSearchStatus.idle);
    c.dispose();
  });

  test('debounces: rapid typing produces exactly one request for the last text', () async {
    final g = FakeGeocoding();
    final c = make(g);
    for (final q in ['สย', 'สยา', 'สยาม', 'สยามพ']) {
      c.onQueryChanged(q);
      await _wait(10);
    }
    await _wait(120);
    expect(g.queries, ['สยามพ']);
    expect(c.status, PlaceSearchStatus.results);
    c.dispose();
  });

  test('searchNow (keyboard search) skips the debounce', () async {
    final g = FakeGeocoding();
    final c = make(g);
    await c.searchNow('siam');
    expect(g.queries, ['siam']);
    c.dispose();
  });

  test('empty result and failures map to states', () async {
    final g = FakeGeocoding()..results = const [];
    final c = make(g);
    await c.searchNow('nowhere');
    expect(c.status, PlaceSearchStatus.empty);
    g.failure = const AppFailure(FailureCode.rateLimited);
    await c.searchNow('again1');
    expect(c.status, PlaceSearchStatus.rateLimited);
    g.failure = const AppFailure(FailureCode.serverUnavailable);
    await c.searchNow('again2');
    expect(c.status, PlaceSearchStatus.unavailable);
    c.dispose();
  });

  test('typing a too-short text cancels the pending debounce', () async {
    final g = FakeGeocoding();
    final c = make(g);
    c.onQueryChanged('abc');
    c.onQueryChanged('a');
    await _wait(100);
    expect(g.queries, isEmpty);
    c.dispose();
  });

  // BUG-1 (round 8): Nominatim can answer with duplicate label+point rows;
  // `PlaceSuggestion` has no id, so `results` must be deduped by the
  // controller before a widget ever keys a list off it (avoids the
  // duplicate-key crash in place_search_field.dart).
  test('dedups results with the same label+point, keeping the first occurrence', () async {
    final g = FakeGeocoding()
      ..results = const [
        PlaceSuggestion(label: 'สยามพารากอน', point: LatLng(13.7462, 100.5347)),
        PlaceSuggestion(label: 'สยามพารากอน', point: LatLng(13.7462, 100.5347)),
        PlaceSuggestion(label: 'เซ็นทรัลเวิลด์', point: LatLng(13.7469, 100.5392)),
        PlaceSuggestion(label: 'สยามพารากอน', point: LatLng(13.7462, 100.5347)),
      ];
    final c = make(g);
    await c.searchNow('สยาม');
    expect(c.status, PlaceSearchStatus.results);
    expect(c.results.length, 2);
    expect(c.results[0].label, 'สยามพารากอน');
    expect(c.results[1].label, 'เซ็นทรัลเวิลด์');
    c.dispose();
  });

  test('duplicate label with different points is not treated as a duplicate', () async {
    final g = FakeGeocoding()
      ..results = const [
        PlaceSuggestion(label: 'ร้านกาแฟ', point: LatLng(13.70, 100.50)),
        PlaceSuggestion(label: 'ร้านกาแฟ', point: LatLng(13.90, 100.60)),
      ];
    final c = make(g);
    await c.searchNow('กาแฟ');
    expect(c.results.length, 2);
    c.dispose();
  });

  test('regression: distinct results are all kept in original order', () async {
    final g = FakeGeocoding()
      ..results = const [
        PlaceSuggestion(label: 'A', point: LatLng(1, 1)),
        PlaceSuggestion(label: 'B', point: LatLng(2, 2)),
        PlaceSuggestion(label: 'C', point: LatLng(3, 3)),
        PlaceSuggestion(label: 'D', point: LatLng(4, 4)),
        PlaceSuggestion(label: 'E', point: LatLng(5, 5)),
      ];
    final c = make(g);
    await c.searchNow('abc');
    expect(c.results.map((s) => s.label).toList(), ['A', 'B', 'C', 'D', 'E']);
    c.dispose();
  });
}
