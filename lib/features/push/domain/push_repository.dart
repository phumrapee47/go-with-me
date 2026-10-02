import '../../../core/error/app_failure.dart';
import '../../../core/error/result.dart';
import 'push_models.dart';

/// design-roles 14.6 RPC contract: `register_device_token(p_token, p_platform)`
/// / `unregister_device_token(p_token)`. Both are upserts/idempotent deletes
/// server-side; the client never needs to know whether a row already existed.
abstract class PushRepository {
  Future<Result<void>> registerToken(String token, DevicePlatform platform);

  /// Removes only this device's token (Q1) — never affects other devices.
  Future<Result<void>> unregisterToken(String token);
}

/// Used before config is ready / Supabase unavailable (mirrors
/// `UnavailableAuthRepository`). Never blocks the caller.
class UnavailablePushRepository implements PushRepository {
  const UnavailablePushRepository();

  static const _failure = AppFailure(FailureCode.serverUnavailable, retryable: true);

  @override
  Future<Result<void>> registerToken(String token, DevicePlatform platform) async =>
      const Err(_failure);

  @override
  Future<Result<void>> unregisterToken(String token) async => const Err(_failure);
}
