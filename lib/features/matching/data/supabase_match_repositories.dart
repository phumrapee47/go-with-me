import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../../../core/geo/geo.dart';
import '../../../core/net/retry.dart';
import '../../trip/domain/travel_mode.dart';
import '../../trip/domain/trip.dart' show TripRole, TripStatus;
import '../domain/match_models.dart';
import '../domain/match_repository.dart';
import 'request_flow.dart';

class SupabaseMatchFinderRepository implements MatchFinderRepository {
  SupabaseMatchFinderRepository(this._client);
  final sb.SupabaseClient _client;

  @override
  Future<Result<List<MatchCandidate>>> findMatches(String tripId, {int limit = 20}) async {
    try {
      final res = await retryTransient(
        () => _client.rpc('find_matches', params: {'p_trip_id': tripId, 'p_limit': limit}),
      );
      final rows = res is List ? res : const [];
      final out = <MatchCandidate>[
        for (final r in rows)
          if (r is Map<String, dynamic>) ?MatchCandidate.fromJson(r),
      ];
      // Server already orders by score; keep it stable if it ever does not.
      out.sort((a, b) => b.score.compareTo(a.score));
      return Ok(out);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<MatchHint?>> matchHint(String tripId) async {
    try {
      final res = await _client.rpc('get_match_hint', params: {'p_trip_id': tripId});
      return Ok(MatchHint.fromDb(res));
    } catch (e) {
      return Err(mapError(e));
    }
  }
}

class SupabaseMatchRepository implements MatchRepository {
  SupabaseMatchRepository(this._client, {this.sleep});

  final sb.SupabaseClient _client;
  final Future<void> Function(Duration)? sleep;

  String? get _uid => _client.auth.currentUser?.id;

  static const _cols = 'id,requester_trip_id,target_trip_id,requester_id,target_id,status,overlap_pct,'
      'meeting_point,meeting_label,meeting_proposed_by,meeting_proposed_point,meeting_proposed_label,created_at,'
      'boarded_at,auto_closed,driver_trip_id,rider_trip_id';

  // In-flight guard per (my trip, target trip): a double tap shares one call.
  final _inflight = <String, Future<Result<MatchRequestOutcome>>>{};

  @override
  Future<Result<MatchRequestOutcome>> request({
    required String myTripId,
    required String targetTripId,
    double? clientDetourM,
  }) {
    final key = '$myTripId|$targetTripId';
    return _inflight[key] ??=
        _request(myTripId, targetTripId, clientDetourM).whenComplete(() => _inflight.remove(key));
  }

  Future<Result<MatchRequestOutcome>> _request(String my, String target, double? clientDetourM) async {
    final uid = _uid;
    try {
      final outcome = await runRequestMatch(
        sleep: sleep,
        callRpc: () async {
          final id = await _client.rpc('request_match', params: {
            'p_my_trip': my,
            'p_target_trip': target,
            'p_client_detour_m': ?clientDetourM,
          });
          return '$id';
        },
        lookup: () async {
          final rows = await _client
              .from('matches')
              .select('id,status,requester_id')
              .or('and(requester_trip_id.eq.$my,target_trip_id.eq.$target),'
                  'and(requester_trip_id.eq.$target,target_trip_id.eq.$my)')
              .limit(1);
          if (rows.isEmpty) return null;
          final r = rows.first;
          final status = MatchStatus.fromDb(r['status']);
          if (status == null) return null;
          return (id: '${r['id']}', status: status, iAmRequester: r['requester_id'] == uid);
        },
      );
      return Ok(outcome);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<List<MatchSummary>>> inbox() async {
    final uid = _uid;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      final rows = await retryTransient(
        () => _client
            .from('matches')
            .select(_cols)
            .or('requester_id.eq.$uid,target_id.eq.$uid')
            .order('created_at', ascending: false)
            .limit(50),
        sleep: sleep,
      );
      final out = <MatchSummary>[];
      for (final r in rows) {
        final s = await _summarise(r, uid);
        if (s != null) out.add(s);
      }
      return Ok(out);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  Future<MatchSummary?> _summarise(Map<String, dynamic> r, String uid) async {
    final status = MatchStatus.fromDb(r['status']);
    if (status == null) return null;
    final iAmRequester = r['requester_id'] == uid;
    final myTrip = '${iAmRequester ? r['requester_trip_id'] : r['target_trip_id']}';
    final partnerTrip = '${iAmRequester ? r['target_trip_id'] : r['requester_trip_id']}';

    // Partner card is only readable while pending/accepted; failure of one
    // card must not hide the whole list.
    Map<String, dynamic>? card;
    if (status == MatchStatus.pending || status == MatchStatus.accepted) {
      try {
        final res = await _client.rpc('get_trip_card', params: {'p_trip_id': partnerTrip});
        if (res is List && res.isNotEmpty && res.first is Map<String, dynamic>) {
          card = res.first as Map<String, dynamic>;
        }
      } catch (_) {
        card = null;
      }
    }
    final proposedBy = r['meeting_proposed_by'];
    // Roles come from the trigger-filled driver/rider trip ids (car matches only).
    final TripRole? myRole = r['driver_trip_id'] == myTrip
        ? TripRole.driver
        : (r['rider_trip_id'] == myTrip ? TripRole.rider : null);
    final partnerRole = myRole?.opposite;
    return MatchSummary(
      id: '${r['id']}',
      status: status,
      iAmRequester: iAmRequester,
      myTripId: myTrip,
      partnerTripId: partnerTrip,
      partnerName: card?['display_name'] as String?,
      badges: parseBadges(card?['badges']),
      mode: TravelMode.fromDb(card?['mode']),
      departAt: DateTime.tryParse('${card?['depart_at']}')?.toLocal(),
      overlapPct: (r['overlap_pct'] as num?)?.round(),
      approxOrigin: _pair(card?['approx_origin_lat'], card?['approx_origin_lng']),
      approxDest: _pair(card?['approx_dest_lat'], card?['approx_dest_lng']),
      meetingPoint: parsePoint(r['meeting_point']),
      meetingLabel: r['meeting_label'] as String?,
      proposedPoint: parsePoint(r['meeting_proposed_point']),
      proposedLabel: r['meeting_proposed_label'] as String?,
      proposedByMe: proposedBy == uid,
      createdAt: DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now(),
      partnerId: '${iAmRequester ? r['target_id'] : r['requester_id']}',
      myRole: myRole,
      partnerRole: partnerRole,
      boardedAt: DateTime.tryParse('${r['boarded_at']}')?.toLocal(),
      autoClosed: r['auto_closed'] == true,
      partnerTripStatus: TripStatus.fromDb(card?['status']),
    );
  }

  LatLng? _pair(Object? lat, Object? lng) =>
      (lat is num && lng is num) ? LatLng(lat.toDouble(), lng.toDouble()) : null;

  Future<MatchStatus?> _statusOf(String id) async {
    final row = await _client.from('matches').select('status').eq('id', id).maybeSingle();
    return MatchStatus.fromDb(row?['status']);
  }

  @override
  Future<Result<MatchStatus>> respond(String matchId, {required bool accept}) async {
    final want = accept ? MatchStatus.accepted : MatchStatus.declined;
    try {
      final s = await resolveByRefetch<MatchStatus>(
        sleep: sleep,
        action: () async {
          final res = await _client.rpc('respond_match', params: {'p_match_id': matchId, 'p_accept': accept});
          return MatchStatus.fromDb(res) ?? want;
        },
        staleCodes: {'GWM_MATCH_NOT_FOUND'},
        refetchIfDone: () async {
          final s = await _statusOf(matchId);
          return s == want ? s : null;
        },
      );
      return Ok(s);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> cancel(String matchId) async {
    try {
      await resolveByRefetch<bool>(
        sleep: sleep,
        action: () async {
          await _client.rpc('cancel_match', params: {'p_match_id': matchId});
          return true;
        },
        staleCodes: {'GWM_MATCH_NOT_FOUND'},
        refetchIfDone: () async => (await _statusOf(matchId)) == MatchStatus.cancelled ? true : null,
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<bool>> cancelPending(String matchId) async {
    try {
      // Not retried on GWM_MATCH_NOT_FOUND / NOT_PENDING: they are final answers; the RPC itself is idempotent.
      final res = await retryTransient(() => _client.rpc('cancel_pending_match', params: {'p_match_id': matchId}));
      return Ok(res != 'already_cancelled');
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<String>> cancelNoFault(String matchId) async {
    try {
      // Idempotent (returns 'cancelled' | 'already_cancelled', first-write-wins per Q12) so a retry
      // is safe; GWM_NOT_OVERDUE is a final answer (the server's own re-check said "not yet").
      final res = await retryTransient(() => _client.rpc('cancel_match_no_fault', params: {'p_match_id': matchId}));
      return Ok('$res');
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<bool>> proposeMeetingPoint(String matchId, LatLng point, String label) async {
    try {
      // Same point re-sent = same proposal, so retrying is safe.
      final res = await retryTransient(
        () => _client.rpc('propose_meeting_point', params: {
          'p_match_id': matchId,
          'p_lng': point.longitude,
          'p_lat': point.latitude,
          'p_label': label,
        }),
        sleep: sleep,
      );
      // 0006: boolean "beyond the deviation limit". Older servers return void (null).
      return Ok(res == true);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<DateTime>> markBoarded(String matchId) async {
    try {
      // Idempotent on the server (returns the first timestamp) so one retry is safe.
      final res = await retryTransient(
        () => _client.rpc('mark_boarded', params: {'p_match_id': matchId}),
        maxRetries: 1,
        sleep: sleep,
      );
      return Ok(DateTime.tryParse('$res')?.toLocal() ?? DateTime.now());
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> reportRiderNoShow(String matchId) async {
    try {
      // State RPC: at most one automatic retry (design-roles 3). A repeat after
      // success answers GWM_MATCH_NOT_FOUND, which we resolve by re-reading.
      await resolveByRefetch<bool>(
        sleep: sleep,
        action: () async {
          await _client.rpc('report_rider_no_show', params: {'p_match_id': matchId});
          return true;
        },
        staleCodes: {'GWM_MATCH_NOT_FOUND'},
        refetchIfDone: () async => (await _statusOf(matchId)) == MatchStatus.cancelled ? true : null,
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> confirmMeetingPoint(String matchId) async {
    try {
      await _client.rpc('confirm_meeting_point', params: {'p_match_id': matchId});
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Stream<void> changes() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    late final StreamController<void> ctrl;
    final channels = <sb.RealtimeChannel>[];
    ctrl = StreamController<void>(
      onListen: () {
        // Two subscriptions: RLS-filtered filters allow one column each.
        for (final col in ['requester_id', 'target_id']) {
          final ch = _client.channel('matches:$col:$uid').onPostgresChanges(
                event: sb.PostgresChangeEvent.all,
                schema: 'public',
                table: 'matches',
                filter: sb.PostgresChangeFilter(type: sb.PostgresChangeFilterType.eq, column: col, value: uid),
                callback: (_) => ctrl.add(null),
              );
          ch.subscribe();
          channels.add(ch);
        }
      },
      onCancel: () async {
        for (final ch in channels) {
          await _client.removeChannel(ch);
        }
      },
    );
    return ctrl.stream;
  }
}
