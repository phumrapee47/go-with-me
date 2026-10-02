import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/config/app_constants.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../domain/auth_repository.dart';

/// True when a profile read shows a deleted account: no visible row, or a row with non-null `deleted_at`.
bool isDeletedProfileRows(List<dynamic> rows) {
  if (rows.isEmpty) return true;
  final first = rows.first;
  return first is Map && first['deleted_at'] != null;
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final sb.SupabaseClient _client;

  AuthUser? _map(sb.User? u) {
    if (u == null) return null;
    return AuthUser(
      id: u.id,
      email: u.email ?? '',
      displayName: (u.userMetadata?['display_name'] as String?)?.trim() ?? '',
      emailConfirmed: u.emailConfirmedAt != null,
    );
  }

  @override
  Stream<AuthUser?> authChanges() async* {
    yield _map(_client.auth.currentUser);
    await for (final s in _client.auth.onAuthStateChange) {
      yield _map(s.session?.user);
    }
  }

  @override
  Future<Result<SignUpOutcome>> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        // Server trigger records consent from these (design-api section 5).
        data: {
          'display_name': displayName.trim(),
          'adult_confirmed': true,
          'policy_version': AppConstants.policyVersion,
        },
      );
      return Ok(SignUpOutcome(needsEmailVerification: res.session == null));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> signIn({required String email, required String password}) async {
    try {
      final res = await _client.auth.signInWithPassword(email: email.trim(), password: password);
      // T5.12 second layer: the profiles_select policy does NOT hide a deleted own profile, so read deleted_at.
      // Non-null deleted_at, or an empty row (hidden by RLS), means deleted -> sign out. A read error stays
      // fail-open (UX only).
      final uid = res.user?.id;
      if (uid != null) {
        List<dynamic>? rows;
        try {
          rows = await _client.from('profiles').select('id, deleted_at').eq('id', uid);
        } catch (_) {
          rows = null;
        }
        if (rows != null && isDeletedProfileRows(rows)) {
          await signOut();
          return const Err(AppFailure(FailureCode.accountDeleted));
        }
      }
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Server unreachable: still clear the local session so the UI is safe.
      try {
        await _client.auth.signOut(scope: sb.SignOutScope.local);
      } catch (e) {
        return Err(mapError(e));
      }
    }
    return const Ok(null);
  }

  @override
  Future<Result<void>> resendVerification(String email) async {
    try {
      await _client.auth.resend(type: sb.OtpType.signup, email: email.trim());
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }
}

/// Used when Supabase is not configured; the router never leaves /config-error.
class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository();

  static const _failure = AppFailure(FailureCode.configMissing);

  @override
  Stream<AuthUser?> authChanges() => Stream.value(null);

  @override
  Future<Result<SignUpOutcome>> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async => const Err(_failure);

  @override
  Future<Result<void>> signIn({required String email, required String password}) async =>
      const Err(_failure);

  @override
  Future<Result<void>> signOut() async => const Ok(null);

  @override
  Future<Result<void>> resendVerification(String email) async => const Err(_failure);
}
