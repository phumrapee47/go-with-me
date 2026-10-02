import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/core/l10n/strings_r5.dart';
import 'package:gowithme/features/avatar/domain/avatar_processing.dart';
import 'package:gowithme/features/avatar/domain/avatar_repository.dart';
import 'package:gowithme/features/avatar/domain/avatar_service.dart';
import 'package:gowithme/features/geo/domain/geo_services.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/matching/presentation/matching_widgets.dart' show dropoffText;
import 'package:gowithme/features/reviews/domain/review_models.dart';
import 'package:gowithme/features/trip/domain/live_map_logic.dart';
import 'package:gowithme/features/trip/domain/navigation_links.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart' show TripRole;
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';

// ~111 m per 0.001 deg latitude
LatLng _north(LatLng p, double metres) => LatLng(p.latitude + metres / 111195, p.longitude);
const _bkk = LatLng(13.7563, 100.5018);

class _Routing implements RoutingService {
  int calls = 0;
  bool fail = false;
  int durationS = 600;

  @override
  Future<RouteResult> route({required TravelMode mode, required LatLng from, required LatLng to}) async {
    calls++;
    if (fail) throw StateError('down');
    return RouteResult(geometry: [from, to], distanceM: 5000, durationS: durationS);
  }
}

class _AvatarRepo implements AvatarRepository {
  int partnerCalls = 0;
  AvatarSource? src = AvatarSource.bytes(Uint8List(3));
  @override
  Future<Result<AvatarSource?>> mine() async => Ok(src);
  @override
  Future<Result<AvatarSource?>> partner(String matchId) async {
    partnerCalls++;
    return Ok(src);
  }

  @override
  Future<Result<void>> setMine(Uint8List jpeg) async => const Ok(null);
  @override
  Future<Result<void>> removeMine() async => const Ok(null);
  @override
  Future<Result<void>> report(String matchId, AvatarReportReason reason) async => const Ok(null);
}

Uint8List _png(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(20, 120, 200));
  // some texture so JPEG is not trivially tiny
  for (var y = 0; y < h; y += 7) {
    for (var x = 0; x < w; x += 5) {
      im.setPixelRgb(x, y, (x * 3) % 255, (y * 5) % 255, (x + y) % 255);
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  group('avatar resize (US-22)', () {
    test('large landscape photo -> square JPEG, longest side <= 512, small, no EXIF', () {
      final out = processAvatarSync(_png(2000, 1200));
      expect(out.width, lessThanOrEqualTo(avatarMaxSide));
      expect(out.width, out.height, reason: 'centre-cropped square');
      expect(out.bytes.length, lessThanOrEqualTo(avatarHardMaxBytes));
      // JPEG magic
      expect(out.bytes.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
      final decoded = img.decodeJpg(out.bytes)!;
      expect(decoded.width, out.width);
      // No APP1/EXIF marker anywhere in the stream
      final s = String.fromCharCodes(out.bytes);
      expect(s.contains('Exif'), isFalse);
      expect(decoded.exif.isEmpty, isTrue);
    });

    test('EXIF orientation is applied and then dropped (input JPEG with GPS-like EXIF)', () {
      final im = img.Image(width: 600, height: 300, numChannels: 3);
      img.fill(im, color: img.ColorRgb8(200, 30, 30));
      im.exif.imageIfd.orientation = 6; // rotate 90 CW
      im.exif.gpsIfd['GPSLatitudeRef'] = 'N';
      final src = Uint8List.fromList(img.encodeJpg(im));
      expect(String.fromCharCodes(src).contains('Exif'), isTrue, reason: 'fixture must carry EXIF');
      final out = processAvatarSync(src);
      expect(String.fromCharCodes(out.bytes).contains('Exif'), isFalse);
      expect(out.width, out.height);
    });

    test('image already <= 512 is not upscaled; exactly 256 is accepted', () {
      final out = processAvatarSync(_png(300, 300));
      expect(out.width, 300);
      expect(processAvatarSync(_png(256, 256)).width, 256);
    });

    test('too small, not an image, HEIC and oversized input are refused with a kind', () {
      expect(() => processAvatarSync(_png(200, 900)), throwsA(isA<AvatarException>().having((e) => e.kind, 'kind', AvatarErrorKind.tooSmall)));
      expect(() => processAvatarSync(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
          throwsA(isA<AvatarException>().having((e) => e.kind, 'kind', AvatarErrorKind.notImage)));
      final heic = Uint8List.fromList([0, 0, 0, 24, ...'ftypheic'.codeUnits, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect(() => processAvatarSync(heic), throwsA(isA<AvatarException>().having((e) => e.kind, 'kind', AvatarErrorKind.unsupported)));
      expect(() => processAvatarSync(Uint8List(avatarMaxInputBytes + 1)),
          throwsA(isA<AvatarException>().having((e) => e.kind, 'kind', AvatarErrorKind.tooLarge)));
    });

    test('a transparent PNG is flattened onto white (no black background)', () {
      final im = img.Image(width: 300, height: 300, numChannels: 4);
      img.fill(im, color: img.ColorRgba8(0, 0, 0, 0));
      final out = processAvatarSync(Uint8List.fromList(img.encodePng(im)));
      final px = img.decodeJpg(out.bytes)!.getPixel(150, 150);
      expect(px.r, greaterThan(240));
    });
  });

  group('avatar cache (signed URLs are short lived)', () {
    test('serves from cache inside the TTL and re-signs after it; evict drops it', () async {
      var now = DateTime(2026, 1, 1, 12);
      final repo = _AvatarRepo();
      final svc = AvatarService(repo, clock: () => now);
      await svc.partner('m1');
      await svc.partner('m1');
      expect(repo.partnerCalls, 1);
      now = now.add(const Duration(seconds: 91));
      await svc.partner('m1');
      expect(repo.partnerCalls, 2, reason: 'TTL 90 s < signed URL lifetime 120 s');
      svc.evictMatch('m1');
      await svc.partner('m1');
      expect(repo.partnerCalls, 3);
    });

    test('"no photo" answers are cached for a shorter time', () async {
      var now = DateTime(2026, 1, 1, 12);
      final repo = _AvatarRepo()..src = null;
      final svc = AvatarService(repo, clock: () => now);
      await svc.partner('m1');
      now = now.add(const Duration(seconds: 31));
      await svc.partner('m1');
      expect(repo.partnerCalls, 2);
    });
  });

  group('heading + interpolation + stale (US-23)', () {
    test('bearing: north 0, east 90, south 180, west 270', () {
      expect(bearingDeg(_bkk, _north(_bkk, 100)), closeTo(0, 0.5));
      expect(bearingDeg(_bkk, LatLng(_bkk.latitude, _bkk.longitude + 0.001)), closeTo(90, 0.5));
      expect(bearingDeg(_bkk, _north(_bkk, -100)), closeTo(180, 0.5));
      expect(bearingDeg(_bkk, LatLng(_bkk.latitude, _bkk.longitude - 0.001)), closeTo(270, 0.5));
    });

    test('heading only changes after >= 15 m of movement (no jitter)', () {
      final h = HeadingTracker();
      expect(h.update(_bkk), isNull);
      expect(h.update(_north(_bkk, 8)), isNull, reason: '8 m: keep no heading');
      expect(h.update(_north(_bkk, 20)), closeTo(0, 1));
      final east = LatLng(_north(_bkk, 20).latitude, _bkk.longitude + 0.0005);
      expect(h.update(east), closeTo(90, 1));
      // a 5 m wobble keeps the old heading
      expect(h.update(LatLng(east.latitude + 0.00002, east.longitude)), closeTo(90, 1));
    });

    test('interpolator glides in 1 s (ease in-out) and rests on the last fix: never extrapolates', () {
      var now = DateTime(2026, 1, 1, 12);
      final ip = PositionInterpolator(clock: () => now);
      ip.moveTo(_bkk);
      final target = _north(_bkk, 200);
      ip.moveTo(target);
      expect(ip.valueAt(now), _bkk);
      now = now.add(const Duration(milliseconds: 500));
      final mid = ip.valueAt(now)!;
      expect(mid.latitude, closeTo((_bkk.latitude + target.latitude) / 2, 1e-6), reason: 'ease in-out is 50 % at t=0.5');
      now = now.add(const Duration(milliseconds: 500));
      expect(ip.valueAt(now), target);
      now = now.add(const Duration(seconds: 10));
      expect(ip.valueAt(now), target, reason: 'waits for the next fix instead of predicting');
      expect(ip.isAnimating(now), isFalse);
    });

    test('a new fix mid-glide starts from the icon position (no snap back)', () {
      var now = DateTime(2026, 1, 1, 12);
      final ip = PositionInterpolator(clock: () => now);
      ip.moveTo(_bkk);
      ip.moveTo(_north(_bkk, 400));
      now = now.add(const Duration(milliseconds: 500));
      final shown = ip.valueAt(now)!;
      ip.moveTo(_north(_bkk, 600));
      expect(ip.valueAt(now)!.latitude, closeTo(shown.latitude, 1e-9));
    });

    test('jump > 2 km and reduce-motion move instantly', () {
      var now = DateTime(2026, 1, 1, 12);
      final ip = PositionInterpolator(clock: () => now);
      ip.moveTo(_bkk);
      final far = _north(_bkk, 3000);
      ip.moveTo(far);
      expect(ip.valueAt(now), far);
      final calm = PositionInterpolator(clock: () => now, reduceMotion: true)..moveTo(_bkk);
      calm.moveTo(_north(_bkk, 100));
      expect(calm.valueAt(now), _north(_bkk, 100));
    });

    test('stale after 45 s: label in seconds, then minutes, then a clock time', () {
      final at = DateTime(2026, 1, 1, 12, 0, 0);
      expect(isStale(at.add(const Duration(seconds: 45)), at), isFalse, reason: 'threshold is "more than 45 s"');
      expect(isStale(at.add(const Duration(seconds: 46)), at), isTrue);
      expect(staleLabel(at.add(const Duration(seconds: 30)), at), isNull);
      expect(staleLabel(at.add(const Duration(seconds: 50)), at), 'อัปเดตเมื่อ 50 วินาทีที่แล้ว');
      expect(staleLabel(at.add(const Duration(minutes: 3)), at), 'อัปเดตเมื่อ 3 นาทีที่แล้ว');
      expect(staleLabel(at.add(const Duration(minutes: 11)), at), 'ตำแหน่งล่าสุดเมื่อ 12:00');
    });

    test('compass + coarse distance for the text alternative', () {
      expect(compassThai(0), 'เหนือ');
      expect(compassThai(45), 'ตะวันออกเฉียงเหนือ');
      expect(compassThai(200), 'ใต้');
      expect(compassThai(359), 'เหนือ');
      expect(coarseDistanceText(60), 'ไม่ถึง 100 เมตร');
      expect(coarseDistanceText(1240), '1 กิโลเมตร');
      expect(coarseDistanceText(1300), '1.5 กิโลเมตร');
    });
  });

  group('ETA throttle (D13)', () {
    test('at most one routing call per 45 s for the same target; cached value in between', () async {
      var now = DateTime(2026, 1, 1, 12);
      final routing = _Routing();
      final eta = EtaService(routing: routing, clock: () => now);
      final to = _north(_bkk, 3000);
      final r1 = await eta.eta(from: _bkk, to: to);
      expect(r1.minutes, 10);
      expect(r1.approximate, isFalse);
      expect(r1.geometry, isNotEmpty);
      now = now.add(const Duration(seconds: 20));
      await eta.eta(from: _north(_bkk, 100), to: to);
      now = now.add(const Duration(seconds: 20));
      await eta.eta(from: _north(_bkk, 200), to: to);
      expect(routing.calls, 1, reason: '40 s < 45 s');
      now = now.add(const Duration(seconds: 6));
      routing.durationS = 300;
      final r2 = await eta.eta(from: _north(_bkk, 300), to: to);
      expect(routing.calls, 2);
      expect(r2.minutes, 5);
    });

    test('a new target (pickup -> destination) is calculated at once', () async {
      var now = DateTime(2026, 1, 1, 12);
      final routing = _Routing();
      final eta = EtaService(routing: routing, clock: () => now);
      await eta.eta(from: _bkk, to: _north(_bkk, 1000));
      now = now.add(const Duration(seconds: 5));
      await eta.eta(from: _bkk, to: _north(_bkk, 9000));
      expect(routing.calls, 2);
    });

    test('routing failure falls back to a straight-line estimate marked "(ไม่แม่น)" and is not retried for 45 s', () async {
      var now = DateTime(2026, 1, 1, 12);
      final routing = _Routing()..fail = true;
      final eta = EtaService(routing: routing, clock: () => now);
      final to = _north(_bkk, 5000);
      final r = await eta.eta(from: _bkk, to: to);
      expect(r.approximate, isTrue);
      expect(r.geometry, isEmpty);
      // 5 km * 1.3 at 30 km/h = 13 min
      expect(r.minutes, inInclusiveRange(13, 14));
      expect(r.text, contains('(ไม่แม่น)'));
      now = now.add(const Duration(seconds: 10));
      await eta.eta(from: _bkk, to: to);
      expect(routing.calls, 1, reason: 'a failing service is not hammered');
    });

    test('text: soon under a minute, hours above 60', () {
      expect(const EtaResult(minutes: 0, approximate: false).text, R5.etaSoon);
      expect(const EtaResult(minutes: 70, approximate: false).text, '1 ชม. 10 นาที');
      expect(const EtaResult(minutes: 8, approximate: false).text, '8 นาที');
    });
  });

  group('live markers: what may be drawn (Z-2 / US-18)', () {
    List<LiveMarkerKind> kinds(List<LiveMarker> l) => [for (final m in l) m.kind];

    test('Driver sees the Rider as a person pin (no heading) until boarding, then nothing', () {
      final before = buildLiveMarkers(
        iAmDriver: true, riderBoarded: false, me: _bkk, peer: _north(_bkk, 500), peerStale: false,
        peerHeading: 90, pickup: _north(_bkk, 300), myDestination: _north(_bkk, 9000),
      );
      expect(kinds(before), containsAll([LiveMarkerKind.peerRider, LiveMarkerKind.pickup, LiveMarkerKind.myDestination, LiveMarkerKind.me]));
      expect(before.firstWhere((m) => m.kind == LiveMarkerKind.peerRider).heading, isNull, reason: 'person pin never rotates');
      final after = buildLiveMarkers(
        iAmDriver: true, riderBoarded: true, me: _bkk, peer: _north(_bkk, 500), peerStale: false,
        peerHeading: 90, pickup: _north(_bkk, 300), myDestination: _north(_bkk, 9000),
      );
      expect(kinds(after), isNot(contains(LiveMarkerKind.peerRider)));
      expect(kinds(after), isNot(contains(LiveMarkerKind.pickup)), reason: 'pickup done');
    });

    test('Rider sees the Driver car (with heading + stale flag) all the way; only ONE destination marker exists', () {
      final l = buildLiveMarkers(
        iAmDriver: false, riderBoarded: true, me: _bkk, peer: _north(_bkk, 500), peerStale: true,
        peerHeading: 33, pickup: null, myDestination: _north(_bkk, 7000),
      );
      final car = l.firstWhere((m) => m.kind == LiveMarkerKind.peerDriver);
      expect(car.heading, 33);
      expect(car.stale, isTrue);
      expect(l.where((m) => m.kind == LiveMarkerKind.myDestination), hasLength(1));
    });

    test('the builder has no input for the partner destination (drop-off is never drawn)', () {
      // Structural guarantee: every marker point comes from me / peer live fix / pickup / my destination.
      final me = _bkk, peer = _north(_bkk, 500), pickup = _north(_bkk, 300), dest = _north(_bkk, 9000);
      final l = buildLiveMarkers(
        iAmDriver: true, riderBoarded: false, me: me, peer: peer, peerStale: false, peerHeading: null, pickup: pickup, myDestination: dest,
      );
      final allowed = {me, peer, pickup, dest};
      for (final m in l) {
        expect(allowed, contains(m.point));
      }
    });
  });

  group('navigation buttons (US-24)', () {
    const pickup = LatLng(13.7455, 100.5345);
    NavButtonState st({bool accepted = true, bool boarded = false, bool inProgress = true, LatLng? p = pickup, LatLng? pos}) =>
        navButtonState(matchAccepted: accepted, riderBoarded: boarded, myTripInProgress: inProgress, pickup: p, myPosition: pos);

    test('one button chosen by state', () {
      expect(st(), NavButtonState.toPickup);
      expect(st(boarded: true), NavButtonState.toDestination);
      expect(st(accepted: false), NavButtonState.toDestination, reason: 'no match: own trip only');
      expect(st(inProgress: false), NavButtonState.hidden);
    });

    test('pickup not agreed: disabled with a reason state', () {
      expect(st(p: null), NavButtonState.toPickupDisabledNoPoint);
    });

    test('hidden within 50 m of the pickup, back beyond it; destination button is not affected', () {
      expect(st(pos: _north(pickup, 30)), NavButtonState.hidden);
      expect(st(pos: _north(pickup, 49)), NavButtonState.hidden);
      expect(st(pos: _north(pickup, 80)), NavButtonState.toPickup);
      expect(st(boarded: true, pos: _north(pickup, 10)), NavButtonState.toDestination);
    });

    test('links carry only the target coordinate (no origin, no partner data)', () {
      final g = mapLink(MapApp.google, pickup);
      expect(g.host, 'www.google.com');
      expect(g.queryParameters['destination'], '13.745500,100.534500');
      expect(g.queryParameters.keys.toSet(), {'api', 'destination', 'travelmode'});
      final a = mapLink(MapApp.apple, pickup);
      expect(a.host, 'maps.apple.com');
      expect(a.queryParameters['daddr'], '13.745500,100.534500');
      expect(a.queryParameters.keys.toSet(), {'daddr', 'dirflg'});
      expect(mapLink(MapApp.web, pickup).toString(), contains('13.745500'));
    });

    test('Apple Maps only on Apple platforms; the web link is always offered', () {
      expect(availableMapApps(isApple: false), [MapApp.google, MapApp.web]);
      expect(availableMapApps(isApple: true), [MapApp.google, MapApp.apple, MapApp.web]);
    });
  });

  group('no-match hint mapping (US-21 P1)', () {
    test('db values map to categories; unknown -> null', () {
      expect(MatchHint.fromDb('has_results'), MatchHint.hasResults);
      expect(MatchHint.fromDb('none_found'), MatchHint.noneFound);
      expect(MatchHint.fromDb('far_destination'), MatchHint.farDestination);
      expect(MatchHint.fromDb('far_origin'), MatchHint.farOrigin);
      expect(MatchHint.fromDb('off_route'), isNull, reason: 'replaced by far_destination in 0009');
      expect(MatchHint.fromDb('detour'), isNull);
      expect(MatchHint.fromDb('time_window'), isNull, reason: 'category removed by PM');
      expect(MatchHint.fromDb(null), isNull);
    });

    test('has_results shows nothing; every other category has one plain sentence without numbers', () {
      expect(matchHintMessage(MatchHint.hasResults, role: TripRole.rider), isNull);
      for (final role in [TripRole.driver, TripRole.rider, null]) {
        for (final h in [MatchHint.noneFound, MatchHint.farDestination, MatchHint.farOrigin, null]) {
          final t = matchHintMessage(h, role: role);
          expect(t, isNotNull);
          expect(RegExp(r'\d').hasMatch(t!), isFalse, reason: 'no counts / times / distances in a hint: $t');
        }
      }
    });

    test('wording follows my role: a Driver waits for riders, a Rider for drivers; peer uses its own route text', () {
      expect(matchHintMessage(MatchHint.noneFound, role: TripRole.driver), R5.noneNoRider);
      expect(matchHintMessage(MatchHint.noneFound, role: TripRole.rider), R5.noneNoDriver);
      expect(matchHintMessage(MatchHint.noneFound, role: null), R5.noneGeneric);
      expect(matchHintMessage(MatchHint.farDestination, role: TripRole.rider), R5.noneFarDest);
      expect(matchHintMessage(MatchHint.farDestination, role: null), R5.nonePeerRoute);
      expect(matchHintMessage(MatchHint.farOrigin, role: TripRole.driver), R5.noneFarOrigin);
      expect(matchHintMessage(null, role: TripRole.rider), R5.noneGeneric);
    });
  });

  group('find_matches 0009 columns + drop-off limit (US-21)', () {
    Map<String, dynamic> row({Object? maxDropoff, String mode = 'car', String role = 'driver', bool nullDest = false}) => {
          'trip_id': 't1',
          'display_name': 'พลอย',
          'badges': const [],
          'mode': mode,
          'depart_at': '2026-01-01T12:00:00Z',
          'time_diff_min': 3,
          'overlap_pct': 80,
          'approx_distance_m': 4500,
          'score': 88,
          'approx_origin_lat': 13.75,
          'approx_origin_lng': 100.5,
          'approx_dest_lat': nullDest ? null : 13.8,
          'approx_dest_lng': nullDest ? null : 100.6,
          'request_status': null,
          'role': role,
          'max_dropoff_m': maxDropoff,
        };

    test('max_dropoff_m parsed for car, ignored for peer modes, null when absent', () {
      expect(MatchCandidate.fromJson(row(maxDropoff: 3000))!.maxDropoffM, 3000);
      expect(MatchCandidate.fromJson(row(maxDropoff: '2000'))!.maxDropoffM, 2000);
      expect(MatchCandidate.fromJson(row())!.maxDropoffM, isNull);
      expect(MatchCandidate.fromJson(row(maxDropoff: 3000, mode: 'transit'))!.maxDropoffM, isNull);
      expect(MatchCandidate.fromJson(row(maxDropoff: 3000))!.withRequestStatus(MatchStatus.pending).maxDropoffM, 3000);
    });

    test('a null destination (car rider seen by a driver) is tolerated, not dropped', () {
      final c = MatchCandidate.fromJson(row(role: 'rider', nullDest: true));
      expect(c, isNotNull);
      expect(c!.approxDest, isNull);
      expect(c.withRequestStatus(MatchStatus.pending).approxDest, isNull);
      expect(MatchCandidate.fromJson(row())!.approxDest, isNotNull);
    });

    test('metre formatting: m under 1000, else km with one decimal', () {
      expect(formatMetres(499), '499 ม.');
      expect(formatMetres(500), '500 ม.');
      expect(formatMetres(999), '999 ม.');
      expect(formatMetres(1000), '1.0 กม.');
      expect(formatMetres(1500), '1.5 กม.');
      expect(formatMetres(5000), '5.0 กม.');
    });

    test('slider bounds, step, chips and clamping mirror the 0009 CHECK', () {
      expect((dropoffMinM, dropoffMaxM, dropoffStepM, dropoffDefaultM), (500, 5000, 100, 2000));
      expect(dropoffChipsM, [1000, 2000, 3000, 5000]);
      for (final m in dropoffChipsM) {
        expect(m % dropoffStepM, 0);
        expect(m, inInclusiveRange(dropoffMinM, dropoffMaxM));
      }
      expect(clampDropoff(100), 500);
      expect(clampDropoff(9000), 5000);
      expect(clampDropoff(2049), 2000);
      expect(clampDropoff(2051), 2100);
    });

    test('card text uses the driver limit; copy has no detour wording', () {
      expect(R5.matchDriverMaxDropoff('2.0 กม.'), 'คนขับรับส่งได้ไม่เกิน 2.0 กม. จากปลายทางของเขา');
      expect(R5.matchSameWay(80), 'ทางเดียวกัน ~80%');
      expect(R5.matchRuleExplain, isNot(contains('เบี่ยง')));
    });

    test('dropoffText only for a car driver candidate with a limit', () {
      MatchCandidate c(String role, Object? m) => MatchCandidate.fromJson(row(role: role, maxDropoff: m))!;
      expect(dropoffText(c('driver', 2000)), 'คนขับรับส่งได้ไม่เกิน 2.0 กม. จากปลายทางของเขา');
      expect(dropoffText(c('driver', 800)), 'คนขับรับส่งได้ไม่เกิน 800 ม. จากปลายทางของเขา');
      expect(dropoffText(c('driver', null)), isNull);
      expect(dropoffText(c('rider', null)), isNull);
    });
  });

  group('review aggregate rule (US-26 / Z-3)', () {
    test('only >= 3 revealed reviews show an average; below that nothing is shown at all', () {
      const two = UserRating(role: TripRole.driver, enough: true, count: 2, avg: 5);
      const notEnough = UserRating(role: TripRole.driver, enough: false);
      const three = UserRating(role: TripRole.driver, enough: true, count: 3, avg: 4.5);
      expect(visibleRating([two], TripRole.driver), isNull, reason: 'client re-applies the threshold');
      expect(visibleRating([notEnough], TripRole.driver), isNull);
      expect(visibleRating([three], TripRole.driver), same(three));
      expect(visibleRating([three], TripRole.rider), isNull, reason: 'per role');
      expect(visibleRating(const [], TripRole.driver), isNull);
      // A server that says enough but sends a nonsense value is not shown either
      expect(visibleRating([const UserRating(role: TripRole.driver, enough: true, count: 5, avg: 7)], TripRole.driver), isNull);
      expect(visibleRating([const UserRating(role: TripRole.driver, enough: true, count: 5)], TripRole.driver), isNull);
    });

    test('rating rows parse from the RPC shape', () {
      final r = UserRating.fromJson({'role': 'driver', 'enough': true, 'review_count': 12, 'avg_stars': '4.83'})!;
      expect(r.count, 12);
      expect(r.avg, closeTo(4.83, 1e-9));
      expect(ratingText(4.83), '4.8');
      expect(UserRating.fromJson({'role': 'admin'}), isNull);
    });

    test('tags follow the reviewed role; state helpers', () {
      expect(reviewTagsFor(TripRole.driver), containsAll(['safe_driving', 'vehicle_matches']));
      expect(reviewTagsFor(TripRole.rider), isNot(contains('safe_driving')));
      final st = ReviewState.fromJson({'can_review': true, 'reason': null, 'closes_at': DateTime.now().add(const Duration(days: 3, hours: 2)).toUtc().toIso8601String(), 'my_stars': null, 'my_tags': null, 'my_comment': null});
      expect(st.promptable, isTrue);
      expect(st.daysLeft(DateTime.now()), 4);
      final done = ReviewState.fromJson({'can_review': false, 'reason': 'already_submitted', 'my_stars': 4, 'my_tags': ['polite']});
      expect(done.alreadySubmitted, isTrue);
      expect(done.promptable, isFalse);
      expect(ReviewState.fromJson({'can_review': false, 'reason': 'window_closed'}).windowClosed, isTrue);
    });
  });
}
