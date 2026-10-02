import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../../../core/net/retry.dart';
import '../domain/trip_share.dart';

class SupabaseTripShareRepository implements TripShareRepository {
  SupabaseTripShareRepository(this._client, {this.sleep});
  final sb.SupabaseClient _client;
  final Future<void> Function(Duration)? sleep;

  @override
  Future<Result<ShareLink>> create(String tripId, {int? ttlMin}) async {
    try {
      // Not auto-retried: every call mints a new token (limit 10 active).
      final res = await _client.rpc('create_trip_share', params: {
        'p_trip_id': tripId,
        'p_ttl_min': ?ttlMin,
      });
      if (res is List && res.isNotEmpty && res.first is Map) {
        final r = res.first as Map;
        final exp = DateTime.tryParse('${r['share_expires_at']}');
        if (r['share_id'] is String && r['token'] is String && exp != null) {
          return Ok(ShareLink(id: r['share_id'] as String, expiresAt: exp.toLocal(), token: r['token'] as String));
        }
      }
      return const Err(AppFailure(FailureCode.unknown));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> revoke(String shareId) async {
    try {
      await retryTransient(() => _client.rpc('revoke_trip_share', params: {'p_share_id': shareId}), sleep: sleep);
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<List<ActiveShare>>> active() async {
    try {
      final rows = await retryTransient(
        () => _client
            .from('trip_shares')
            .select('id,trip_id,expires_at')
            .isFilter('revoked_at', null)
            .gt('expires_at', DateTime.now().toUtc().toIso8601String())
            .order('created_at', ascending: false)
            .limit(20),
        sleep: sleep,
      );
      return Ok([
        for (final r in rows)
          if (DateTime.tryParse('${r['expires_at']}') case final exp?)
            ActiveShare(id: '${r['id']}', tripId: '${r['trip_id']}', expiresAt: exp.toLocal()),
      ]);
    } catch (e) {
      return Err(mapError(e));
    }
  }
}
