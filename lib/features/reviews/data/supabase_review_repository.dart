import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../domain/review_models.dart';
import '../domain/review_repository.dart';

class SupabaseReviewRepository implements ReviewRepository {
  SupabaseReviewRepository(this._client);
  final sb.SupabaseClient _client;

  Map<String, dynamic>? _firstRow(Object? res) {
    if (res is List && res.isNotEmpty && res.first is Map) return Map<String, dynamic>.from(res.first as Map);
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  @override
  Future<Result<ReviewState>> state(String matchId) async {
    try {
      final res = await _client.rpc('get_my_review_state', params: {'p_match_id': matchId});
      final row = _firstRow(res);
      return Ok(row == null ? const ReviewState(canReview: false, reason: 'not_found') : ReviewState.fromJson(row));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> submit({required String matchId, required int stars, required List<String> tags, String? comment}) async {
    try {
      await _client.rpc('submit_review', params: {
        'p_match_id': matchId,
        'p_stars': stars,
        'p_tags': tags,
        'p_comment': (comment == null || comment.trim().isEmpty) ? null : comment.trim(),
      });
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<List<UserRating>>> rating(String userId) async {
    try {
      final res = await _client.rpc('get_user_rating', params: {'p_user': userId});
      final rows = res is List ? res : const [];
      return Ok([
        for (final r in rows)
          if (r is Map) ?UserRating.fromJson(Map<String, dynamic>.from(r)),
      ]);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<List<ReceivedReview>>> received({int limit = 50}) async {
    try {
      final res = await _client.rpc('get_reviews_received', params: {'p_limit': limit});
      final rows = res is List ? res : const [];
      return Ok([
        for (final r in rows)
          if (r is Map) ?ReceivedReview.fromJson(Map<String, dynamic>.from(r)),
      ]);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> report(String reviewId, ReviewReportReason reason) async {
    try {
      await _client.rpc('report_review', params: {'p_review_id': reviewId, 'p_reason': reason.db});
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }
}
