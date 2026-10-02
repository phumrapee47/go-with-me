import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../../../core/net/retry.dart';
import '../domain/role_state.dart';

/// RPC-only access to the role state. `profiles` is never read with `select('*')`
/// (0008 narrows the SELECT grant to a column list); the new columns are only
/// reachable through `get_my_role_state()`. Plate/model/colour never reach logs or errors.
class SupabaseRoleRepository implements RoleRepository {
  SupabaseRoleRepository(this._client, {this.sleep});

  /// Lazy so a missing Supabase instance (tests, config error) surfaces as a mapped failure, not a crash.
  final sb.SupabaseClient Function() _client;
  final Future<void> Function(Duration)? sleep;

  Future<Result<DriverRegistration>> _call(String fn, [Map<String, dynamic>? params, bool retry = true]) async {
    try {
      final client = _client();
      final Object? res = retry
          ? await retryTransient(() => client.rpc(fn, params: params), sleep: sleep)
          : await client.rpc(fn, params: params);
      final state = DriverRegistration.fromJson(res is List && res.isNotEmpty ? res.first : res);
      return state == null ? const Err(AppFailure(FailureCode.unknown)) : Ok(state);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<DriverRegistration>> getMyRoleState() => _call('get_my_role_state');

  // register/unregister are idempotent server-side, so transient retries are safe.
  @override
  Future<Result<DriverRegistration>> registerDriver({
    required String plate,
    required String model,
    required String colour,
    required String declarationVersion,
  }) =>
      _call('register_driver', {
        'p_plate': plate,
        'p_model': model,
        'p_colour': colour,
        'p_declaration_version': declarationVersion,
      });

  @override
  Future<Result<DriverRegistration>> unregisterDriver() => _call('unregister_driver');

  @override
  Future<Result<DriverRegistration>> setActiveRole(ActiveRole role) =>
      _call('set_active_role', {'p_role': role.db}, false); // no backoff: offline must be reported at once (F-D1)
}
