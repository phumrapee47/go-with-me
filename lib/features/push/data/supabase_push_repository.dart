import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../../../core/net/retry.dart';
import '../domain/push_models.dart';
import '../domain/push_repository.dart';

/// design-roles 14.6: `register_device_token(p_token text, p_platform
/// device_platform)` / `unregister_device_token(p_token text)`. Not yet live
/// on any database (0011/0011a are drafts) — this class only codes against
/// the documented contract; it is not exercised outside DEMO_MODE/tests until
/// the migration is applied and approved.
class SupabasePushRepository implements PushRepository {
  SupabasePushRepository(this._client);
  final sb.SupabaseClient _client;

  @override
  Future<Result<void>> registerToken(String token, DevicePlatform platform) async {
    try {
      await retryTransient(
        () => _client.rpc('register_device_token', params: {
          'p_token': token,
          'p_platform': platform.wire,
        }),
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> unregisterToken(String token) async {
    try {
      // Idempotent server-side (no matching row = still success).
      await retryTransient(() => _client.rpc('unregister_device_token', params: {'p_token': token}));
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }
}
