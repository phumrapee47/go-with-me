import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../matching/domain/match_models.dart';
import '../data/supabase_review_repository.dart';
import '../domain/review_models.dart';
import '../domain/review_repository.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => SupabaseReviewRepository(Supabase.instance.client),
);

/// null = could not be read (treated as "nothing to prompt": a failed read never nags the user).
final reviewStateProvider = FutureProvider.autoDispose.family<ReviewState?, String>((ref, matchId) async {
  final res = await ref.watch(reviewRepositoryProvider).state(matchId);
  return res.valueOrNull;
});

/// Aggregates of one user (both roles). Errors and "not enough" both end up hidden (Z-3).
final userRatingProvider = FutureProvider.autoDispose.family<List<UserRating>, String>((ref, userId) async {
  final res = await ref.watch(reviewRepositoryProvider).rating(userId);
  return res.valueOrNull ?? const <UserRating>[];
});

final receivedReviewsProvider = FutureProvider.autoDispose<List<ReceivedReview>>((ref) async {
  final res = await ref.watch(reviewRepositoryProvider).received();
  return res.when(ok: (l) => l, err: (f) => throw f);
});

/// SharedPreferences key: the post-trip sheet is shown once per match ("later" keeps the card elsewhere).
String reviewPromptSeenKey(String matchId) => 'review_prompt_seen_$matchId';

/// The match a finished trip can be reviewed for: a car match that reached boarding.
MatchSummary? reviewableMatchFor(List<MatchSummary> inbox, String myTripId) {
  MatchSummary? best;
  for (final m in inbox) {
    if (m.myTripId == myTripId && m.isCar && m.boarded) best = m;
  }
  return best;
}
