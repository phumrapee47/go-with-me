import '../../../core/error/result.dart';
import 'review_models.dart';

abstract class ReviewRepository {
  /// `get_my_review_state`. Never says whether the other side has reviewed.
  Future<Result<ReviewState>> state(String matchId);

  /// `submit_review`; errors GWM_REVIEW_NOT_ELIGIBLE / _WINDOW_CLOSED / _DUPLICATE / _INVALID, GWM_RATE_LIMITED.
  Future<Result<void>> submit({required String matchId, required int stars, required List<String> tags, String? comment});

  /// `get_user_rating`: one row per role; below the threshold only `enough=false`.
  Future<Result<List<UserRating>>> rating(String userId);

  /// `get_reviews_received`: revealed reviews only, no reviewer identity.
  Future<Result<List<ReceivedReview>>> received({int limit = 50});

  Future<Result<void>> report(String reviewId, ReviewReportReason reason);
}
