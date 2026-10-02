import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/demo/demo_data.dart';
import 'package:gowithme/demo/demo_fakes.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';

void main() {
  test('demo mode is off unless explicitly defined', () {
    expect(const bool.fromEnvironment('DEMO_MODE'), isFalse);
  });

  test('blur snaps to 1 km cell centre', () {
    final b = blurTo1km(demoPlaces[0].point);
    expect((b.latitude * 1000).round() % 10, 5);
  });

  test('candidates reflect pending/accepted matches and new requests', () async {
    final repo = DemoMatchRepository();
    final list = (await repo.findMatches('t') as Ok<List<MatchCandidate>>).value;
    expect(list.length, 5);
    expect(list.where((c) => c.requestStatus == MatchStatus.pending).length, 1);
    expect(list.where((c) => c.requestStatus == MatchStatus.accepted).length, 1);
    await repo.request(myTripId: 'demo-trip-me', targetTripId: 'demo-cand-1');
    final after = (await repo.findMatches('t') as Ok<List<MatchCandidate>>).value;
    expect(after.firstWhere((c) => c.tripId == 'demo-cand-1').requestStatus, MatchStatus.pending);
  });

  test('demo geocoding and routing work offline', () async {
    final r = await DemoGeocoding().search('หมอชิต');
    expect(r, isNotEmpty);
    final route = await DemoRouting().route(
      mode: TravelMode.walk,
      from: demoPlaces[0].point,
      to: demoPlaces[2].point,
    );
    expect(route.geometry.first, demoPlaces[0].point);
    expect(route.geometry.last, demoPlaces[2].point);
    expect(route.distanceM, greaterThan(1000));
  });
}
