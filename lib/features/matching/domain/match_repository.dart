import 'package:latlong2/latlong.dart';

import '../../../core/error/result.dart';
import 'match_models.dart';

abstract class MatchFinderRepository {
  /// `find_matches` RPC (server-blurred, bucketed, sorted by score desc).
  Future<Result<List<MatchCandidate>>> findMatches(String tripId, {int limit = 20});

  /// `get_match_hint` (rate limited, one category). Null result = unknown category (generic text).
  Future<Result<MatchHint?>> matchHint(String tripId);
}

abstract class MatchRepository {
  /// Idempotent from the caller's view: transient failures are retried and
  /// "already requested" is resolved by re-reading the match (design-api 7.2).
  ///
  /// [clientDetourM] is US-50 (round 7 Stage D, migration 0016)'s
  /// `p_client_detour_m`: the caller's own CLIENT-SIDE precise (OSRM) detour
  /// calculation (`computePreciseDetourM`), only meaningful when this
  /// candidate only qualifies via the detour-tolerance path. Null is always
  /// safe to pass (the server ignores it unless that path is the only one
  /// that qualifies); a value below the server's sound floor is rejected
  /// with `GWM_DETOUR_IMPLAUSIBLE`.
  Future<Result<MatchRequestOutcome>> request({
    required String myTripId,
    required String targetTripId,
    double? clientDetourM,
  });

  /// Pending/accepted matches (enriched) plus recent declined/cancelled ones.
  Future<Result<List<MatchSummary>>> inbox();

  Future<Result<MatchStatus>> respond(String matchId, {required bool accept});
  Future<Result<void>> cancel(String matchId);

  /// Deck undo (migration 0010 `cancel_pending_match`): cancels ONLY a still-pending request I sent.
  /// Ok(true) = cancelled now, Ok(false) = it was already cancelled (idempotent). Errors: GWM_MATCH_NOT_PENDING
  /// (the other side answered first, nothing changed), GWM_MATCH_NOT_FOUND.
  Future<Result<bool>> cancelPending(String matchId);

  /// Meeting point is proposed by one side and confirmed by the other (P-2).
  ///
  /// Returns true when (car match) the point is farther than
  /// `match.pickup_max_deviation_m` from the Driver's route: a WARNING only,
  /// the point is always saved (R3-2). The server never returns the distance.
  Future<Result<bool>> proposeMeetingPoint(String matchId, LatLng point, String label);
  Future<Result<void>> confirmMeetingPoint(String matchId);

  /// Rider only: "ขึ้นรถแล้ว". Returns the server timestamp (idempotent).
  /// Errors: GWM_TRIP_NOT_STARTED, GWM_NOT_RIDER, GWM_MATCH_NOT_FOUND.
  Future<Result<DateTime>> markBoarded(String matchId);

  /// Driver only: "คนนั่งไม่มาตามนัด" (no timer, no penalty; reason is internal).
  Future<Result<void>> reportRiderNoShow(String matchId);

  /// US-49 (round 7): "ยกเลิกการเดินทาง (ไม่เสียประวัติ)" — the server (`cancel_match_no_fault`,
  /// migration 0014) re-verifies lateness itself and never trusts the client. Returns 'cancelled' |
  /// 'already_cancelled' (idempotent, first-write-wins per Q12). Errors: GWM_NOT_OVERDUE (the
  /// server's own check does not yet consider it overdue), GWM_MATCH_NOT_FOUND, GWM_NOT_ELIGIBLE
  /// (not a car Driver<->Rider match).
  Future<Result<String>> cancelNoFault(String matchId);

  /// Emits whenever a match involving the caller changes (Realtime).
  Stream<void> changes();
}
