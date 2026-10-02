import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/error/app_failure.dart';
import '../../../core/error/result.dart';
import '../../../core/net/throttle.dart';
import '../../../core/notify/local_notifier.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../geo/presentation/geo_providers.dart' show routingServiceProvider;
import '../../trip/domain/precise_detour.dart';
import '../../trip/domain/travel_mode.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/trip_lifecycle_providers.dart' show appForegroundProvider;
import '../../trip/presentation/trip_providers.dart';
import '../data/supabase_match_repositories.dart';
import '../domain/match_models.dart';
import '../domain/match_repository.dart';
import 'match_moment.dart' show matchMomentProvider;

/// Server-side blur cell is ~1 km (`privacy.blur_cell_m`); a 700 m circle
/// around the cell centre covers the whole cell, so the true point is never
/// implied by the drawing.
const blurAreaRadiusM = 700.0;

/// design-api section 8: find_matches at most once per 10 s per user.
const findMatchesMinInterval = Duration(seconds: 10);

final matchFinderRepositoryProvider = Provider<MatchFinderRepository>(
  (ref) => SupabaseMatchFinderRepository(Supabase.instance.client),
);

final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => SupabaseMatchRepository(Supabase.instance.client),
);

/// Clock override point for the refresh gate in tests.
final refreshClockProvider = Provider<Clock>((ref) => DateTime.now);

class NearbyController extends AsyncNotifier<List<MatchCandidate>> {
  late RefreshGate _gate;

  @override
  Future<List<MatchCandidate>> build() async {
    _gate = RefreshGate(findMatchesMinInterval, clock: ref.read(refreshClockProvider));
    final trip = await ref.watch(activeTripProvider.future);
    // P-1: no trip -> no list (a count/list without a trip would be an oracle).
    if (trip == null) return const [];
    // F-R3.7: an old car trip without a role is never matched; do not even ask.
    if (trip.isLegacyCarWithoutRole) return const [];
    _gate.tryAcquire();
    return _load(trip);
  }

  Future<List<MatchCandidate>> _load(Trip trip) async {
    final res = await ref.read(matchFinderRepositoryProvider).findMatches(trip.id);
    return res.when(
      ok: (l) => [...filterCandidates(trip, l)]..sort((a, b) => b.score.compareTo(a.score)), // score desc, stable UI order
      err: (f) => throw f,
    );
  }

  /// Pull-to-refresh / retry. Calls closer than 10 s to the previous fetch
  /// keep the current list instead of hitting the server.
  Future<void> refresh({bool force = false}) async {
    final trip = ref.read(activeTripProvider).valueOrNull;
    if (trip == null) return;
    if (!force && !_gate.tryAcquire()) return;
    if (force) _gate.tryAcquire();
    final prev = state;
    if (!prev.hasValue) state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(trip));
    if (state.hasError && prev.hasValue) {
      // Keep showing the old list; the screen shows a transient error.
      state = AsyncData<List<MatchCandidate>>(prev.value!);
    }
  }

  /// Sends a request and reflects the outcome in the list.
  Future<Result<MatchRequestOutcome>> request(MatchCandidate c) async {
    final trip = ref.read(activeTripProvider).valueOrNull;
    if (trip == null) return const Err(AppFailure('GWM_TRIP_NOT_FOUND'));

    // US-50 (round 7 Stage D): only a car Rider requesting a car Driver
    // candidate can compute the precise OSRM detour client-side (see
    // precise_detour.dart's doc comment for why the reverse direction
    // cannot). Only bother when the radial max_dropoff_m path alone would
    // not already have qualified this candidate.
    double? clientDetourM;
    if (trip.isCar &&
        trip.role == TripRole.rider &&
        c.mode == TravelMode.car &&
        c.role == TripRole.driver &&
        c.approxDest != null &&
        needsDetourPath(driverDest: c.approxDest!, riderDest: trip.dest, effectiveDropoffLimitM: c.maxDropoffM)) {
      clientDetourM = await computePreciseDetourM(
        routing: ref.read(routingServiceProvider),
        mode: TravelMode.car,
        driverOrigin: c.approxOrigin,
        driverDest: c.approxDest!,
        riderDest: trip.dest,
      );
      if (clientDetourM == null) {
        // Fail-closed per docs/design-roles.md §16: never guess a number, never
        // silently omit and hope — a clear "ลองใหม่อีกครั้ง" without even
        // calling request_match (the server would only answer GWM_NOT_ELIGIBLE,
        // which reads as "not a candidate" rather than "network hiccup, retry").
        return const Err(AppFailure(FailureCode.detourCalcFailed, retryable: true));
      }
    }

    final res = await ref
        .read(matchRepositoryProvider)
        .request(myTripId: trip.id, targetTripId: c.tripId, clientDetourM: clientDetourM);
    if (res case Ok(:final value)) {
      final list = state.valueOrNull ?? const <MatchCandidate>[];
      state = AsyncData([
        for (final x in list) x.tripId == c.tripId ? x.withRequestStatus(value.status) : x,
      ]);
      ref.invalidate(inboxProvider);
      // Round 6 (US-37): remember this request so the Match Moment can show once the other side accepts.
      ref.read(matchMomentProvider.notifier).track(value.matchId);
    }
    return res;
  }

  /// Undo: the request was cancelled, so the person can be a candidate again.
  void clearRequest(String tripId) {
    final list = state.valueOrNull;
    if (list == null) return;
    state = AsyncData([for (final x in list) x.tripId == tripId ? x.withoutRequest() : x]);
  }
}

/// Defence in depth on top of the server rule: car trips only see the
/// opposite role, other modes never see car trips (and vice versa). Peer
/// modes (walk/transit/taxi) are unchanged: everyone else non-car.
List<MatchCandidate> filterCandidates(Trip trip, List<MatchCandidate> items) => [
      for (final c in items)
        if (tripsCompatible(myMode: trip.mode, myRole: trip.role, otherMode: c.mode, otherRole: c.role)) c,
    ];

final nearbyProvider =
    AsyncNotifierProvider<NearbyController, List<MatchCandidate>>(NearbyController.new);

class InboxController extends AsyncNotifier<List<MatchSummary>> {
  @override
  Future<List<MatchSummary>> build() async {
    final uid = ref.watch(authUserProvider.select((a) => a.valueOrNull?.id));
    if (uid == null) return const [];
    final repo = ref.watch(matchRepositoryProvider);
    // Realtime: any change to my matches refetches the inbox.
    final sub = repo.changes().listen((_) => ref.invalidateSelf());
    ref.onDispose(sub.cancel);
    final res = await repo.inbox();
    return res.when(ok: (l) => l, err: (f) => throw f);
  }

  Future<void> refresh() async {
    final repo = ref.read(matchRepositoryProvider);
    final res = await repo.inbox();
    res.when(
      ok: (l) => state = AsyncData(l),
      err: (f) => state = state.hasValue ? state : AsyncError(f, StackTrace.current),
    );
  }

  Future<Result<MatchStatus>> respond(MatchSummary m, {required bool accept}) async {
    final res = await ref.read(matchRepositoryProvider).respond(m.id, accept: accept);
    await refresh();
    return res;
  }

  Future<Result<void>> cancel(String matchId) async {
    // My own cancellation must not raise the "match ended" alert for me.
    ref.read(matchAlertProvider.notifier).suppress(matchId);
    final res = await ref.read(matchRepositoryProvider).cancel(matchId);
    await refresh();
    return res;
  }

  /// Deck undo: server-guarded cancel of a still-pending request only (never an accepted match).
  Future<Result<bool>> cancelPending(String matchId) async {
    ref.read(matchAlertProvider.notifier).suppress(matchId);
    final res = await ref.read(matchRepositoryProvider).cancelPending(matchId);
    await refresh();
    return res;
  }

  /// Rider: "ขึ้นรถแล้ว".
  Future<Result<DateTime>> markBoarded(String matchId) async {
    final res = await ref.read(matchRepositoryProvider).markBoarded(matchId);
    await refresh();
    return res;
  }

  /// Driver: "คนนั่งไม่มาตามนัด".
  Future<Result<void>> reportNoShow(String matchId) async {
    ref.read(matchAlertProvider.notifier).suppress(matchId);
    final res = await ref.read(matchRepositoryProvider).reportRiderNoShow(matchId);
    await refresh();
    return res;
  }

  /// Result true = beyond the deviation limit (warning only, point saved).
  Future<Result<bool>> proposeMeeting(String matchId, LatLng point, String label) async {
    final res = await ref.read(matchRepositoryProvider).proposeMeetingPoint(matchId, point, label);
    await refresh();
    return res;
  }

  Future<Result<void>> confirmMeeting(String matchId) async {
    final res = await ref.read(matchRepositoryProvider).confirmMeetingPoint(matchId);
    await refresh();
    return res;
  }
}

final inboxProvider = AsyncNotifierProvider<InboxController, List<MatchSummary>>(InboxController.new);

/// Incoming pending requests waiting for my answer (badge on the tab).
final incomingPendingCountProvider = Provider<int>((ref) {
  final list = ref.watch(inboxProvider).valueOrNull ?? const <MatchSummary>[];
  return list.where((m) => m.isIncomingPending).length;
});


/// Raised when my accepted car match (I am the Rider) ends while my trip is in
/// progress and I have not boarded (Q-1/Q-7): shown from any screen until acknowledged.
class MatchEndAlert {
  const MatchEndAlert({required this.matchId, required this.tripId});
  final String matchId;
  final String tripId;
}

class MatchAlertController extends Notifier<MatchEndAlert?> {
  // Accepted Rider matches seen so far, by id.
  final _tracked = <String, MatchSummary>{};
  final _suppressed = <String>{};

  @override
  MatchEndAlert? build() {
    _tracked.clear();
    // Realtime already refetches the inbox on every `matches` change; listening
    // here keeps that subscription alive app-wide (not only on the match page).
    ref.listen<AsyncValue<List<MatchSummary>>>(
      inboxProvider,
      (_, next) {
        final list = next.valueOrNull;
        if (list != null) _onInbox(list);
      },
      fireImmediately: true,
    );
    // Back from background: refresh at once (no remote push in the MVP).
    ref.listen<bool>(appForegroundProvider, (prev, fg) {
      if (fg && prev == false) ref.invalidate(inboxProvider);
    });
    return null;
  }

  void _onInbox(List<MatchSummary> list) {
    final byId = {for (final m in list) m.id: m};
    final trip = ref.read(activeTripProvider).valueOrNull;
    for (final prev in _tracked.values.toList()) {
      final now = byId[prev.id];
      final inProgress = trip != null && trip.id == prev.myTripId && trip.status == TripStatus.inProgress;
      if (now != null &&
          now.status == MatchStatus.cancelled &&
          !now.boarded &&
          !_suppressed.contains(prev.id) &&
          inProgress &&
          state == null) {
        state = MatchEndAlert(matchId: prev.id, tripId: prev.myTripId);
        // Neutral text only: no plate, name or location (design-spec R.6).
        unawaited(ref.read(localNotifierProvider).show(const LocalNotice(LocalNoticeKind.matchEndedDuringTrip)));
      }
    }
    _tracked
      ..clear()
      ..addEntries([
        for (final m in list)
          if (m.iAmRider && m.status == MatchStatus.accepted) MapEntry(m.id, m),
      ]);
  }

  void suppress(String matchId) => _suppressed.add(matchId);

  /// My own trip is ending: matches closing because of that are not alerts.
  void quiet() => _tracked.clear();

  void dismiss() => state = null;
}

final matchAlertProvider = NotifierProvider<MatchAlertController, MatchEndAlert?>(MatchAlertController.new);

/// `get_match_hint` for the empty search state only (rate limited server side; no side effects).
/// Watched only while the list is empty; a failure hides the hint without touching the results.
final matchHintProvider = FutureProvider.autoDispose.family<MatchHint?, String>((ref, tripId) async {
  final res = await ref.watch(matchFinderRepositoryProvider).matchHint(tripId);
  return res.when(ok: (h) => h, err: (f) => throw f);
});
