import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:image/image.dart' as img;

import '../core/error/app_failure.dart';
import '../core/error/result.dart';
import '../features/avatar/domain/avatar_repository.dart';
import '../features/avatar/presentation/avatar_providers.dart' show AvatarPicker, PhotoSource, PickOutcome;
import '../features/matching/domain/match_models.dart';
import '../features/reviews/domain/review_models.dart';
import '../features/reviews/domain/review_repository.dart';
import '../features/trip/domain/trip.dart' show TripRole;
import 'demo_fakes.dart';

const _latency = Duration(milliseconds: 250);
Future<void> _wait() => Future<void>.delayed(_latency);

/// A small generated portrait (gradient + head/shoulders) so avatars are visible without any real photo.
Uint8List demoPortrait(int seed) {
  final palette = [
    [0x0F, 0x64, 0xCB, 0x2E, 0xB8, 0x8A],
    [0xF5, 0xA6, 0x23, 0xE0, 0x5A, 0x4E],
    [0x7B, 0x5E, 0xD6, 0x2E, 0xB8, 0xD6],
    [0x2E, 0x9E, 0x5B, 0xC8, 0xD9, 0x3E],
  ][seed.abs() % 4];
  const s = 160;
  final im = img.Image(width: s, height: s, numChannels: 3);
  for (var y = 0; y < s; y++) {
    final f = y / s;
    final c = img.ColorRgb8(
      (palette[0] + (palette[3] - palette[0]) * f).round(),
      (palette[1] + (palette[4] - palette[1]) * f).round(),
      (palette[2] + (palette[5] - palette[2]) * f).round(),
    );
    for (var x = 0; x < s; x++) {
      im.setPixel(x, y, c);
    }
  }
  img.fillCircle(im, x: s ~/ 2, y: (s * .38).round(), radius: (s * .18).round(), color: img.ColorRgb8(250, 248, 246));
  img.fillCircle(im, x: s ~/ 2, y: (s * 1.05).round(), radius: (s * .42).round(), color: img.ColorRgb8(250, 248, 246));
  return Uint8List.fromList(img.encodeJpg(im, quality: 85));
}

/// In-memory avatars. Partners of accepted matches get a generated portrait; a reported photo disappears.
class DemoAvatarRepository implements AvatarRepository {
  Uint8List? _mine;
  final _reported = <String>{};
  final offline = ValueNotifier<bool>(false);

  bool get hasMine => _mine != null;

  void reset() {
    _mine = null;
    _reported.clear();
    offline.value = false;
  }

  Result<T>? _off<T>() => offline.value ? Err<T>(const AppFailure(FailureCode.networkOffline, retryable: true)) : null;

  @override
  Future<Result<AvatarSource?>> mine() async => Ok(_mine == null ? null : AvatarSource.bytes(_mine!));

  @override
  Future<Result<AvatarSource?>> partner(String matchId) async {
    if (_reported.contains(matchId)) return const Ok(null);
    return Ok(AvatarSource.bytes(demoPortrait(matchId.hashCode)));
  }

  @override
  Future<Result<void>> setMine(Uint8List jpeg) async {
    await _wait();
    final off = _off<void>();
    if (off != null) return off;
    _mine = jpeg;
    return const Ok(null);
  }

  @override
  Future<Result<void>> removeMine() async {
    await _wait();
    final off = _off<void>();
    if (off != null) return off;
    _mine = null;
    return const Ok(null);
  }

  @override
  Future<Result<void>> report(String matchId, AvatarReportReason reason) async {
    await _wait();
    _reported.add(matchId);
    return const Ok(null);
  }
}

/// In-memory reviews. Reviewable = a car match where the Rider boarded. Ratings: every demo partner whose id
/// ends with an even digit-free hash shows an aggregate (>= 3 reviews), the others show nothing (Z-3 rule).
class DemoReviewRepository implements ReviewRepository {
  DemoReviewRepository(this._matches);
  final DemoMatchRepository _matches;

  final _sent = <String, ({int stars, List<String> tags, String? comment})>{};
  final _reported = <String>{};

  void reset() {
    _sent.clear();
    _reported.clear();
  }

  MatchSummary? _m(String id) => _matches.matches.where((x) => x.id == id).firstOrNull;

  @override
  Future<Result<ReviewState>> state(String matchId) async {
    await _wait();
    final m = _m(matchId);
    if (m == null || !m.isCar || !m.boarded) return const Ok(ReviewState(canReview: false, reason: 'not_boarded'));
    final closes = DateTime.now().add(const Duration(days: 7));
    final sent = _sent[matchId];
    if (sent != null) {
      return Ok(ReviewState(canReview: false, reason: 'already_submitted', closesAt: closes, myStars: sent.stars, myTags: sent.tags, myComment: sent.comment));
    }
    return Ok(ReviewState(canReview: true, closesAt: closes));
  }

  @override
  Future<Result<void>> submit({required String matchId, required int stars, required List<String> tags, String? comment}) async {
    await _wait();
    if (_sent.containsKey(matchId)) return const Err(AppFailure('GWM_REVIEW_DUPLICATE'));
    _sent[matchId] = (stars: stars, tags: tags, comment: comment);
    return const Ok(null);
  }

  @override
  Future<Result<List<UserRating>>> rating(String userId) async {
    await _wait();
    // Deterministic: ids with an even hash have >= 3 revealed reviews, the rest have fewer (nothing is shown).
    if (userId.hashCode.isEven) {
      return const Ok([
        UserRating(role: TripRole.driver, enough: true, count: 12, avg: 4.8),
        UserRating(role: TripRole.rider, enough: false),
      ]);
    }
    return const Ok([UserRating(role: TripRole.driver, enough: false), UserRating(role: TripRole.rider, enough: false)]);
  }

  @override
  Future<Result<List<ReceivedReview>>> received({int limit = 50}) async {
    await _wait();
    final now = DateTime.now();
    return Ok([
      if (!_reported.contains('r1'))
        ReceivedReview(id: 'r1', matchId: 'm1', role: TripRole.rider, stars: 5, tags: const ['on_time', 'polite'], comment: 'ตรงเวลา คุยง่าย', createdAt: now.subtract(const Duration(days: 2))),
      if (!_reported.contains('r2'))
        ReceivedReview(id: 'r2', matchId: 'm2', role: TripRole.driver, stars: 4, tags: const ['safe_driving'], createdAt: now.subtract(const Duration(days: 5))),
    ]);
  }

  @override
  Future<Result<void>> report(String reviewId, ReviewReportReason reason) async {
    await _wait();
    _reported.add(reviewId);
    return const Ok(null);
  }
}

/// Demo picker: "picks" a generated 900x700 PNG so the real resize/JPEG pipeline runs without a file dialog.
class DemoAvatarPicker implements AvatarPicker {
  const DemoAvatarPicker();

  @override
  Future<PickOutcome> pick(PhotoSource source) async {
    final big = img.Image(width: 900, height: 700, numChannels: 3);
    img.fill(big, color: img.ColorRgb8(60, 140, 200));
    img.fillCircle(big, x: 450, y: 260, radius: 130, color: img.ColorRgb8(250, 248, 246));
    img.fillCircle(big, x: 450, y: 760, radius: 300, color: img.ColorRgb8(250, 248, 246));
    return PickOutcome.picked(Uint8List.fromList(img.encodePng(big)));
  }
}
