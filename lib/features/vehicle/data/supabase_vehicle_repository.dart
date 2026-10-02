import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../../../core/net/retry.dart';
import '../domain/vehicle.dart';

/// Vehicle plate/model/color are PII-ish: never log arguments of these calls
/// (design-roles 5.8) and never put them in error text.
class SupabaseVehicleRepository implements VehicleRepository {
  SupabaseVehicleRepository(this._client, {this.sleep});
  final sb.SupabaseClient _client;
  final Future<void> Function(Duration)? sleep;

  @override
  Future<Result<Vehicle?>> mine() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      final row = await retryTransient(
        () => _client
            .from('vehicles')
            .select('plate,model,color,share_consent_at,verified_at')
            .eq('user_id', uid)
            .maybeSingle(),
        sleep: sleep,
      );
      return Ok(Vehicle.fromJson(row));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> save(VehicleInput i) async {
    try {
      // Upsert = idempotent, safe to retry.
      await retryTransient(
        () => _client.rpc('upsert_my_vehicle', params: {
          'p_plate': i.plate,
          'p_model': i.model,
          'p_color': i.color,
        }),
        sleep: sleep,
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> setShareConsent(bool on) async {
    try {
      await retryTransient(() => _client.rpc('set_vehicle_share_consent', params: {'p_on': on}), sleep: sleep);
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> deleteMine() async {
    try {
      await retryTransient(() => _client.rpc('delete_my_vehicle'), sleep: sleep);
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<VehicleView?>> forMatch(String matchId) async {
    try {
      final res = await retryTransient(
        () => _client.rpc('get_match_vehicle', params: {'p_match_id': matchId}),
        sleep: sleep,
      );
      if (res is List && res.isNotEmpty && res.first is Map<String, dynamic>) {
        return Ok(VehicleView.fromJson(res.first as Map<String, dynamic>));
      }
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }
}
