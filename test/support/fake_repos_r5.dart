import 'dart:typed_data';

import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/features/avatar/domain/avatar_repository.dart';
import 'package:gowithme/features/avatar/presentation/avatar_providers.dart';
import 'package:gowithme/features/reviews/domain/review_models.dart';
import 'package:gowithme/features/reviews/domain/review_repository.dart';

/// No photo unless a test sets one; records uploads/removals/reports.
class FakeAvatarRepository implements AvatarRepository {
  AvatarSource? mineSource;
  AvatarSource? partnerSource;
  AppFailure? uploadFailure;
  final uploads = <Uint8List>[];
  final reports = <(String, AvatarReportReason)>[];
  int removed = 0;
  int partnerCalls = 0;

  @override
  Future<Result<AvatarSource?>> mine() async => Ok(mineSource);

  @override
  Future<Result<AvatarSource?>> partner(String matchId) async {
    partnerCalls++;
    return Ok(partnerSource);
  }

  @override
  Future<Result<void>> setMine(Uint8List jpeg) async {
    if (uploadFailure != null) return Err(uploadFailure!);
    uploads.add(jpeg);
    mineSource = AvatarSource.bytes(jpeg);
    return const Ok(null);
  }

  @override
  Future<Result<void>> removeMine() async {
    removed++;
    mineSource = null;
    return const Ok(null);
  }

  @override
  Future<Result<void>> report(String matchId, AvatarReportReason reason) async {
    reports.add((matchId, reason));
    partnerSource = null;
    return const Ok(null);
  }
}

class FakePicker implements AvatarPicker {
  FakePicker(this.outcome);
  PickOutcome outcome;
  final asked = <PhotoSource>[];

  @override
  Future<PickOutcome> pick(PhotoSource source) async {
    asked.add(source);
    return outcome;
  }
}

class FakeReviewRepository implements ReviewRepository {
  ReviewState reviewState = const ReviewState(canReview: false, reason: 'not_boarded');
  List<UserRating> ratings = const [];
  List<ReceivedReview> receivedList = const [];
  AppFailure? submitFailure;
  final submitted = <({String matchId, int stars, List<String> tags, String? comment})>[];
  final reported = <String>[];

  @override
  Future<Result<ReviewState>> state(String matchId) async => Ok(reviewState);

  @override
  Future<Result<void>> submit({required String matchId, required int stars, required List<String> tags, String? comment}) async {
    if (submitFailure != null) return Err(submitFailure!);
    submitted.add((matchId: matchId, stars: stars, tags: tags, comment: comment));
    return const Ok(null);
  }

  @override
  Future<Result<List<UserRating>>> rating(String userId) async => Ok(ratings);

  @override
  Future<Result<List<ReceivedReview>>> received({int limit = 50}) async => Ok(receivedList);

  @override
  Future<Result<void>> report(String reviewId, ReviewReportReason reason) async {
    reported.add(reviewId);
    receivedList = [for (final r in receivedList) if (r.id != reviewId) r];
    return const Ok(null);
  }
}
