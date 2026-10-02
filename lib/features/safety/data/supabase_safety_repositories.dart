import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../../../core/geo/geo.dart';
import '../../../core/net/retry.dart';
import '../domain/safety_models.dart';
import '../domain/safety_repository.dart';

class SupabaseSafetyRepository implements SafetyRepository {
  SupabaseSafetyRepository(this._client, {this.sleep});
  final sb.SupabaseClient _client;
  final Future<void> Function(Duration)? sleep;

  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<Result<void>> block(String userId) async {
    final uid = _uid;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      await retryTransient(
        () => _client.from('blocks').insert({'blocker_id': uid, 'blocked_id': userId}),
        sleep: sleep,
      );
      return const Ok(null);
    } catch (e) {
      final f = mapError(e);
      // blocks_pkey duplicate = already blocked = success.
      return f.code == FailureCode.duplicate ? const Ok(null) : Err(f);
    }
  }

  @override
  Future<Result<void>> unblock(String userId) async {
    try {
      await retryTransient(
        () => _client.from('blocks').delete().eq('blocked_id', userId),
        sleep: sleep,
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<List<BlockedUser>>> blocked() async {
    try {
      final rows = await retryTransient(
        () => _client
            .from('blocks')
            .select('blocked_id,created_at')
            .order('created_at', ascending: false)
            .limit(50),
        sleep: sleep,
      );
      final ids = [for (final r in rows) '${r['blocked_id']}'];
      // Names are best effort: RLS hides profiles of people we are not matched with.
      final names = <String, String>{};
      if (ids.isNotEmpty) {
        try {
          final ps = await _client.from('profiles').select('id,display_name').inFilter('id', ids).limit(50);
          for (final p in ps) {
            names['${p['id']}'] = '${p['display_name']}';
          }
        } catch (_) {}
      }
      return Ok([
        for (final r in rows)
          BlockedUser(
            userId: '${r['blocked_id']}',
            blockedAt: DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now(),
            displayName: names['${r['blocked_id']}'],
          ),
      ]);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> report({
    required String userId,
    String? matchId,
    required ReportReason reason,
    String? details,
  }) async {
    final uid = _uid;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      // Not auto-retried: reports are intentionally not idempotent.
      await _client.from('reports').insert({
        'reporter_id': uid,
        'reported_user_id': userId,
        'match_id': matchId,
        'reason': reason.db,
        if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
      });
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }
}

class SupabaseEmergencyContactRepository implements EmergencyContactRepository {
  SupabaseEmergencyContactRepository(this._client, {this.sleep});
  final sb.SupabaseClient _client;
  final Future<void> Function(Duration)? sleep;

  static const _cols = 'id,name,phone';

  @override
  Future<Result<List<EmergencyContact>>> list() async {
    try {
      final rows = await retryTransient(
        () => _client.from('emergency_contacts').select(_cols).order('created_at').limit(10),
        sleep: sleep,
      );
      return Ok([for (final r in rows) ?EmergencyContact.fromJson(r)]);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<EmergencyContact>> add({required String name, required String phone}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      final row = await _client
          .from('emergency_contacts')
          .insert({'user_id': uid, 'name': name.trim(), 'phone': ContactRules.normalizePhone(phone)})
          .select(_cols)
          .single();
      final c = EmergencyContact.fromJson(row);
      return c == null ? const Err(AppFailure(FailureCode.unknown)) : Ok(c);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<EmergencyContact>> update(String id, {required String name, required String phone}) async {
    try {
      final row = await retryTransient(
        () => _client
            .from('emergency_contacts')
            .update({'name': name.trim(), 'phone': ContactRules.normalizePhone(phone)})
            .eq('id', id)
            .select(_cols)
            .single(),
        sleep: sleep,
      );
      final c = EmergencyContact.fromJson(row);
      return c == null ? const Err(AppFailure(FailureCode.unknown)) : Ok(c);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      await retryTransient(() => _client.from('emergency_contacts').delete().eq('id', id), sleep: sleep);
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }
}

class SupabaseSosRepository implements SosRepository {
  SupabaseSosRepository(this._client);
  final sb.SupabaseClient _client;

  @override
  Future<Result<void>> submit(SosEvent e) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Err(AppFailure(FailureCode.sessionExpired, retryable: true));
    try {
      // upsert(onConflict: id, ignoreDuplicates) = INSERT .. ON CONFLICT DO
      // NOTHING (Prefer: resolution=ignore-duplicates): resending is a no-op.
      await _client.from('sos_events').upsert(
        {
          'id': e.id,
          'user_id': uid,
          'trip_id': e.tripId,
          'source': e.source.db,
          if (e.location != null) 'location': pointEwkt(e.location!),
          if (e.note != null) 'note': e.note,
          'client_created_at': e.clientCreatedAt.toUtc().toIso8601String(),
        },
        onConflict: 'id',
        ignoreDuplicates: true,
      );
      return const Ok(null);
    } catch (err) {
      return Err(mapError(err));
    }
  }
}
