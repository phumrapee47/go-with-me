import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/demo/demo_data.dart';
import 'package:gowithme/demo/demo_fakes.dart';
import 'package:gowithme/demo/demo_fakes_p4.dart';
import 'package:gowithme/demo/demo_fakes_r5.dart';
import 'package:gowithme/features/avatar/domain/avatar_processing.dart';
import 'package:gowithme/features/avatar/domain/avatar_repository.dart';
import 'package:gowithme/features/avatar/presentation/avatar_providers.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/reviews/domain/review_models.dart';
import 'package:gowithme/features/trip/domain/trip.dart';

void main() {
  test('demo picker feeds the REAL resize pipeline: a portrait JPEG <= 512 px comes out', () async {
    final out = await const DemoAvatarPicker().pick(PhotoSource.gallery);
    final p = processAvatarSync(out.bytes!);
    expect(p.width, lessThanOrEqualTo(512));
    expect(p.bytes.length, lessThanOrEqualTo(avatarHardMaxBytes));
  });

  test('demo avatars: partner portrait for a match, mine set / removed, a report hides the partner photo', () async {
    final repo = DemoAvatarRepository();
    expect((await repo.mine()).valueOrNull, isNull);
    await repo.setMine(demoPortrait(1));
    expect((await repo.mine()).valueOrNull, isNotNull);
    await repo.removeMine();
    expect((await repo.mine()).valueOrNull, isNull);
    expect((await repo.partner('demo-match-accepted')).valueOrNull, isNotNull);
    await repo.report('demo-match-accepted', AvatarReportReason.inappropriate);
    expect((await repo.partner('demo-match-accepted')).valueOrNull, isNull, reason: 'hidden from the reporter at once');
  });

  test('demo live location: only for an accepted match, fixes change every 15 s, freeze stops them, Driver loses the boarded Rider', () async {
    final trips = DemoTripRepository()..reset(DemoScenario.rider);
    final matches = DemoMatchRepository(trips)..reset(DemoScenario.rider);
    final live = DemoLiveLocationRepository(matches);
    // pending match: nothing
    expect((await live.partnerLocation('demo-match-pending')).valueOrNull, isNull);
    // accept it (Rider scenario: the Driver Plöy asked me)
    await matches.respond('demo-match-pending', accept: true);
    final a = (await live.partnerLocation('demo-match-pending')).valueOrNull;
    expect(a, isNotNull);
    // same 15 s window: same recorded_at
    final b = (await live.partnerLocation('demo-match-pending')).valueOrNull;
    expect(b!.recordedAt, a!.recordedAt);
    live.frozen.value = true;
    final f1 = (await live.partnerLocation('demo-match-pending')).valueOrNull!;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final f2 = (await live.partnerLocation('demo-match-pending')).valueOrNull!;
    expect(f2.recordedAt, f1.recordedAt, reason: 'frozen: the last fix stops updating (stale after 45 s)');
  });

  test('demo Driver: the Rider disappears from the live feed after boarding', () async {
    final trips = DemoTripRepository()..reset(DemoScenario.driver);
    final matches = DemoMatchRepository(trips)..reset(DemoScenario.driver);
    final live = DemoLiveLocationRepository(matches);
    await matches.respond('demo-match-pending', accept: true);
    expect((await live.partnerLocation('demo-match-pending')).valueOrNull, isNotNull);
    matches.partnerBoards();
    expect((await live.partnerLocation('demo-match-pending')).valueOrNull, isNull);
  });

  test('demo reviews: only after boarding; sent once; aggregates follow the >= 3 rule', () async {
    final trips = DemoTripRepository()..reset(DemoScenario.rider);
    final matches = DemoMatchRepository(trips)..reset(DemoScenario.rider);
    final reviews = DemoReviewRepository(matches);
    await matches.respond('demo-match-pending', accept: true);
    expect((await reviews.state('demo-match-pending')).valueOrNull!.canReview, isFalse, reason: 'not boarded yet');
    await matches.markBoarded('demo-match-pending');
    // (markBoarded needs both trips started in the demo; fall back to the hub simulation)
    if (matches.acceptedCar?.boarded != true) matches.partnerBoards();
    final st = (await reviews.state('demo-match-pending')).valueOrNull!;
    expect(st.canReview, isTrue);
    await reviews.submit(matchId: 'demo-match-pending', stars: 5, tags: const ['polite']);
    expect((await reviews.state('demo-match-pending')).valueOrNull!.alreadySubmitted, isTrue);
    final dup = await reviews.submit(matchId: 'demo-match-pending', stars: 4, tags: const []);
    expect(dup.failureOrNull?.code, 'GWM_REVIEW_DUPLICATE');
    // ratings: some users show an aggregate, others (below 3) show nothing after the client rule
    var shown = 0, hidden = 0;
    for (final id in ['u-a', 'u-b', 'u-c', 'u-d', 'u-e', 'u-f']) {
      final r = (await reviews.rating(id)).valueOrNull!;
      visibleRating(r, TripRole.driver) == null ? hidden++ : shown++;
      expect(visibleRating(r, TripRole.rider), isNull);
    }
    expect(shown, greaterThan(0));
    expect(hidden, greaterThan(0));
  });

  test('demo hint category and car candidates follow the drop-off rule', () async {
    final trips = DemoTripRepository()..reset(DemoScenario.rider);
    final matches = DemoMatchRepository(trips)..reset(DemoScenario.rider);
    matches.hintForDemo = MatchHint.farOrigin;
    expect((await matches.matchHint('t')).valueOrNull, MatchHint.farOrigin);
    for (final c in demoCarCandidates(TripRole.rider)) {
      expect(c.maxDropoffM, isNotNull);
      expect(c.approxDest, isNotNull);
    }
    for (final c in demoCarCandidates(TripRole.driver)) {
      expect(c.approxDest, isNull, reason: 'a rider destination is never shown to a driver');
      expect(c.maxDropoffM, isNull);
    }
  });

  test('driver limit filters rider candidates: the 2461 m rider appears only from 3000 m', () async {
    bool has2461(int limit) => demoCarCandidates(TripRole.driver, driverLimitM: limit)
        .any((c) => demoCarDestGapM[int.parse(c.tripId.split('-').last) - 1] == 2461);
    expect(has2461(2000), isFalse);
    expect(has2461(2400), isFalse);
    expect(has2461(2500), isTrue);
    expect(has2461(3000), isTrue);
    expect(demoCarCandidates(TripRole.driver, driverLimitM: 500), isEmpty);
    final trips = DemoTripRepository()..reset(DemoScenario.driver);
    final matches = DemoMatchRepository(trips)..reset(DemoScenario.driver);
    final before = (await matches.findMatches('demo-trip-me')).valueOrNull!.length;
    expect((await trips.updateMaxDropoff('demo-trip-me', 5000)).valueOrNull!.maxDropoffM, 5000);
    final after = (await matches.findMatches('demo-trip-me')).valueOrNull!.length;
    expect(after, greaterThan(before));
  });

  test('demo updateMaxDropoff enforces the server errors', () async {
    final trips = DemoTripRepository()..reset(DemoScenario.driver);
    expect((await trips.updateMaxDropoff('demo-trip-me', 550)).failureOrNull?.code, 'GWM_DROPOFF_INVALID');
    expect((await trips.updateMaxDropoff('demo-trip-me', 6000)).failureOrNull?.code, 'GWM_DROPOFF_INVALID');
    trips.hasOpenMatch = (_) => true;
    expect((await trips.updateMaxDropoff('demo-trip-me', 3000)).failureOrNull?.code, 'GWM_TRIP_HAS_MATCHES');
    final rider = DemoTripRepository()..reset(DemoScenario.rider);
    expect((await rider.updateMaxDropoff('demo-trip-me', 3000)).failureOrNull?.code, 'GWM_DROPOFF_NOT_ALLOWED');
  });
}
