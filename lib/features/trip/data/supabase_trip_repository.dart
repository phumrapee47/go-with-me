import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../../../core/geo/geo.dart';
import '../../../core/net/retry.dart';
import '../domain/trip.dart';
import '../domain/trip_repository.dart';
import '../domain/trip_state_machine.dart';

class SupabaseTripRepository implements TripRepository {
  SupabaseTripRepository(this._client, {this.sleep});

  final sb.SupabaseClient _client;
  final Future<void> Function(Duration)? sleep;

  static const _cols =
      'id,mode,status,origin,origin_label,dest,dest_label,route,route_distance_m,route_duration_s,depart_at,started_at,ended_at,role,max_dropoff_m,detour_tolerance_m,vibe_tags,mood_text,mood_set_at,women_only';

  @override
  Future<Result<Trip?>> activeTrip() async {
    try {
      final rows = await retryTransient(
        () => _client
            .from('trips')
            .select(_cols)
            .inFilter('status', ['scheduled', 'in_progress'])
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .limit(1),
        sleep: sleep,
      );
      if (rows.isEmpty) return const Ok(null);
      return Ok(Trip.fromJson(rows.first));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<Trip>> createTrip(TripDraft d) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      // return=minimal: on a duplicate id the trigger skips the insert and
      // PostgREST answers 201 with no body, so we always re-read afterwards.
      await retryTransient(
        () => _client.from('trips').insert({
          'id': d.id,
          'user_id': uid,
          'mode': d.mode.db,
          'origin': pointEwkt(d.origin.point),
          'origin_label': d.origin.label,
          'dest': pointEwkt(d.dest.point),
          'dest_label': d.dest.label,
          'route': lineEwkt(d.route),
          'route_distance_m': d.distanceM,
          'route_duration_s': d.durationS,
          'depart_at': d.departAt.toUtc().toIso8601String(),
          if (d.role != null) 'role': d.role!.db,
          // Server raises GWM_DROPOFF_NOT_ALLOWED for anything but a driver trip.
          if (d.role == TripRole.driver && d.maxDropoffM != null) 'max_dropoff_m': d.maxDropoffM,
          // US-50 (round 7): a SECOND, independent driver-only matching path (server raises
          // GWM_DETOUR_NOT_ALLOWED for anything but a driver trip).
          if (d.role == TripRole.driver && d.detourToleranceM != null) 'detour_tolerance_m': d.detourToleranceM,
          // US-44/45 (round 7): optional, server re-validates (GWM_VIBE_TAG_INVALID/
          // GWM_MOOD_INVALID/GWM_GENDER_REQUIRED). Omitted entirely when unset so a
          // server default (empty/false) applies rather than sending noisy nulls.
          if (d.vibeTags.isNotEmpty) 'vibe_tags': d.vibeTags,
          if ((d.moodText ?? '').trim().isNotEmpty) 'mood_text': d.moodText!.trim(),
          if (d.womenOnly) 'women_only': true,
        }),
        sleep: sleep,
      );
    } catch (e) {
      final failure = mapError(e);
      // Verify-then-treat-success (design-api 7.3): a timed-out first attempt
      // may have committed; then the retry reports ACTIVE_TRIP_LIMIT.
      if (failure.code == 'GWM_ACTIVE_TRIP_LIMIT' || failure.retryable) {
        final existing = await _byId(d.id);
        if (existing != null) return Ok(existing);
      }
      return Err(failure);
    }
    try {
      final t = await _byId(d.id);
      if (t == null) return const Err(AppFailure(FailureCode.unknown));
      return Ok(t);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<List<Trip>>> myTrips({required bool history, int limit = 20}) async {
    try {
      final rows = await retryTransient(
        () {
          final q = _client.from('trips').select(_cols).isFilter('deleted_at', null);
          final f = history
              ? q.inFilter('status', ['completed', 'cancelled', 'expired'])
              : q.inFilter('status', ['scheduled', 'in_progress']);
          return f.order('created_at', ascending: false).limit(limit);
        },
        sleep: sleep,
      );
      return Ok([for (final r in rows) ?Trip.fromJson(r)]);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<Trip?>> tripById(String id) async {
    try {
      final row = await retryTransient(
        () => _client.from('trips').select(_cols).eq('id', id).maybeSingle(),
        sleep: sleep,
      );
      return Ok(row == null ? null : Trip.fromJson(row));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<Trip>> transition(String id, TripAction action) async {
    final target = TripStateMachine.targetOf(action);
    try {
      // Guarded PATCH (`status in sources`): safe to repeat, and a stale
      // client can never overwrite a newer state.
      final rows = await retryTransient(
        () => _client
            .from('trips')
            .update({'status': target.db})
            .eq('id', id)
            .inFilter('status', [for (final s in TripStateMachine.sourcesFor(action)) s.db])
            .select(_cols),
        sleep: sleep,
      );
      if (rows.isNotEmpty) {
        final t = Trip.fromJson(rows.first);
        if (t != null) return Ok(t);
      }
      return _resolveNoop(id, action);
    } catch (e) {
      final f = mapError(e);
      if (f.code == 'GWM_INVALID_TRIP_TRANSITION') return _resolveNoop(id, action, original: f);
      return Err(f);
    }
  }

  /// Nothing was updated: either an earlier attempt already did it (success)
  /// or the trip is in a state that forbids the action.
  Future<Result<Trip>> _resolveNoop(String id, TripAction action, {AppFailure? original}) async {
    final t = await _byId(id);
    if (t == null) return const Err(AppFailure('GWM_TRIP_NOT_FOUND'));
    if (TripStateMachine.isAlreadyDone(t.status, action)) return Ok(t);
    return Err(original ?? const AppFailure('GWM_INVALID_TRIP_TRANSITION'));
  }

  @override
  Future<Result<void>> deleteTrip(String id) async {
    try {
      await retryTransient(
        () => _client.from('trips').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id),
        sleep: sleep,
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<Trip>> updateMaxDropoff(String id, int metres) async {
    try {
      await _client.from('trips').update({'max_dropoff_m': metres}).eq('id', id);
      final t = await _byId(id);
      return t == null ? const Err(AppFailure('GWM_TRIP_NOT_FOUND')) : Ok(t);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<Trip>> updateDetourTolerance(String id, int metres) async {
    try {
      await _client.from('trips').update({'detour_tolerance_m': metres}).eq('id', id);
      final t = await _byId(id);
      return t == null ? const Err(AppFailure('GWM_TRIP_NOT_FOUND')) : Ok(t);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<Trip>> updateVibeMood(String id, {required List<String> vibeTags, required String? moodText}) async {
    try {
      await _client.from('trips').update({
        'vibe_tags': vibeTags,
        'mood_text': (moodText ?? '').trim().isEmpty ? null : moodText!.trim(),
      }).eq('id', id);
      final t = await _byId(id);
      return t == null ? const Err(AppFailure('GWM_TRIP_NOT_FOUND')) : Ok(t);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<Trip>> updateWomenOnly(String id, bool value) async {
    try {
      await _client.from('trips').update({'women_only': value}).eq('id', id);
      final t = await _byId(id);
      return t == null ? const Err(AppFailure('GWM_TRIP_NOT_FOUND')) : Ok(t);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  Future<Trip?> _byId(String id) async {
    try {
      final row = await _client.from('trips').select(_cols).eq('id', id).maybeSingle();
      return row == null ? null : Trip.fromJson(row);
    } catch (_) {
      return null;
    }
  }
}
