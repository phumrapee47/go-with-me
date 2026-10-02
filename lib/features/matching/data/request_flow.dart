import '../../../core/error/error_mapper.dart';
import '../../../core/net/retry.dart';
import '../../../core/net/throttle.dart';
import '../domain/match_models.dart';

/// Row found when re-reading the match for a trip pair.
typedef FoundMatch = ({String id, MatchStatus status, bool iAmRequester});

/// Idempotent-retry handling for `request_match` (design-api 7.2), kept free
/// of Supabase types so it is unit-testable.
///
/// 1. Transient failures (network/timeout/5xx) are retried with the same
///    arguments; safe because 0002 returns the existing id for a repeat.
/// 2. GWM_ALREADY_REQUESTED / GWM_ALREADY_EXISTS mean an earlier attempt (or
///    the other side) already created the row: re-read it and treat
///    pending/accepted as success. A declined/cancelled row is a real failure.
Future<MatchRequestOutcome> runRequestMatch({
  required Future<String> Function() callRpc,
  required Future<FoundMatch?> Function() lookup,
  Sleeper? sleep,
}) async {
  try {
    final id = await retryTransient(callRpc, sleep: sleep);
    // The RPC does not return the status; a mutual request auto-accepts, so
    // read it back (best effort) to tell the UI "matched" vs "sent".
    FoundMatch? found;
    try {
      found = await lookup();
    } catch (_) {
      found = null;
    }
    return MatchRequestOutcome(
      matchId: id,
      status: found?.status ?? MatchStatus.pending,
      iAmRequester: found?.iAmRequester ?? true,
    );
  } catch (e) {
    final f = mapError(e);
    if (f.code == 'GWM_ALREADY_REQUESTED' || f.code == 'GWM_ALREADY_EXISTS') {
      final found = await lookup();
      if (found != null &&
          (found.status == MatchStatus.pending || found.status == MatchStatus.accepted)) {
        return MatchRequestOutcome(
          matchId: found.id,
          status: found.status,
          iAmRequester: found.iAmRequester,
        );
      }
    }
    throw f;
  }
}

/// Retries a "safe to repeat" action, then treats "already in the target
/// state" as success (used by respond/cancel).
Future<T> resolveByRefetch<T>({
  required Future<T> Function() action,
  required Set<String> staleCodes,
  required Future<T?> Function() refetchIfDone,
  Sleeper? sleep,
}) async {
  try {
    return await retryTransient(action, sleep: sleep);
  } catch (e) {
    final f = mapError(e);
    if (staleCodes.contains(f.code)) {
      final done = await refetchIfDone();
      if (done != null) return done;
    }
    throw f;
  }
}
