import '../../../core/l10n/strings_r5.dart';
import '../../trip/domain/trip.dart' show TripRole;

/// Minimum number of REVEALED reviews before an average is shown (US-26 / Z-3). The server already
/// returns `enough=false` below this and hides the numbers; the client applies the same rule again so a
/// misbehaving response can never show a 1-2 review average.
const minReviewsForAggregate = 3;

class UserRating {
  const UserRating({required this.role, required this.enough, this.count, this.avg});
  final TripRole role;
  final bool enough;
  final int? count;
  final double? avg;

  static UserRating? fromJson(Map<String, dynamic> j) {
    final role = TripRole.fromDb(j['role']);
    if (role == null) return null;
    final c = j['review_count'];
    final a = j['avg_stars'];
    return UserRating(
      role: role,
      enough: j['enough'] == true,
      count: c is num ? c.toInt() : int.tryParse('$c'),
      avg: a is num ? a.toDouble() : double.tryParse('$a'),
    );
  }
}

/// The aggregate to show for [role], or null = show nothing at all (no "not enough reviews" text, Z-3).
UserRating? visibleRating(Iterable<UserRating> ratings, TripRole role) {
  for (final r in ratings) {
    if (r.role != role) continue;
    final c = r.count;
    final a = r.avg;
    if (r.enough && c != null && c >= minReviewsForAggregate && a != null && a >= 1 && a <= 5) return r;
  }
  return null;
}

String ratingRoleLabel(TripRole role) => role == TripRole.driver ? R5.reviewAsDriver : R5.reviewAsRider;

/// One decimal, e.g. 4.8.
String ratingText(double avg) => avg.toStringAsFixed(1);

class ReviewState {
  const ReviewState({required this.canReview, this.reason, this.closesAt, this.myStars, this.myTags = const [], this.myComment});
  final bool canReview;

  /// not_found | not_boarded | already_submitted | window_closed | ... (server text, never shown raw)
  final String? reason;
  final DateTime? closesAt;
  final int? myStars;
  final List<String> myTags;
  final String? myComment;

  bool get alreadySubmitted => myStars != null || reason == 'already_submitted';
  bool get windowClosed => reason == 'window_closed';

  int daysLeft(DateTime now) {
    final c = closesAt;
    if (c == null) return 0;
    final d = c.difference(now);
    if (d.isNegative) return 0;
    return (d.inHours / 24).ceil().clamp(1, 7);
  }

  /// Show the "please rate" prompt: allowed, not yet sent.
  bool get promptable => canReview && !alreadySubmitted;

  static ReviewState fromJson(Map<String, dynamic> j) => ReviewState(
        canReview: j['can_review'] == true,
        reason: j['reason'] as String?,
        closesAt: DateTime.tryParse('${j['closes_at']}')?.toLocal(),
        myStars: (j['my_stars'] as num?)?.toInt(),
        myTags: [for (final t in (j['my_tags'] as List?) ?? const []) '$t'],
        myComment: j['my_comment'] as String?,
      );
}

class ReceivedReview {
  const ReceivedReview({required this.id, required this.matchId, required this.role, required this.stars, required this.tags, this.comment, required this.createdAt});
  final String id;
  final String matchId;
  final TripRole role;
  final int stars;
  final List<String> tags;
  final String? comment;
  final DateTime createdAt;

  static ReceivedReview? fromJson(Map<String, dynamic> j) {
    final role = TripRole.fromDb(j['role']);
    final id = j['review_id'];
    if (role == null || id is! String) return null;
    return ReceivedReview(
      id: id,
      matchId: '${j['match_id']}',
      role: role,
      stars: ((j['stars'] as num?)?.toInt() ?? 0).clamp(0, 5),
      tags: [for (final t in (j['tags'] as List?) ?? const []) '$t'],
      comment: j['comment'] as String?,
      createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
    );
  }
}

/// Tags a reviewer may pick, by the role of the person being reviewed (mirrors the server seed).
List<String> reviewTagsFor(TripRole reviewee) => reviewee == TripRole.driver
    ? const ['on_time', 'polite', 'safe_driving', 'vehicle_matches', 'late', 'not_as_agreed']
    : const ['on_time', 'polite', 'late', 'not_as_agreed'];

const maxReviewTags = 5;
const maxReviewComment = 200;

/// Reasons a reviewee can give when reporting a review (mapped to the server `report_reason` enum).
enum ReviewReportReason {
  inappropriate('harassment'),
  privateInfo('other'),
  other('other');

  const ReviewReportReason(this.db);
  final String db;
}
