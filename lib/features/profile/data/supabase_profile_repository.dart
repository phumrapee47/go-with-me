import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../../../core/net/retry.dart';
import '../../matching/domain/match_models.dart' show VerificationBadge;
import '../domain/gender.dart';
import '../domain/profile_repository.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);
  final sb.SupabaseClient _client;

  static const _cols = 'id,display_name,avatar_path';

  @override
  Future<Result<Profile?>> getMe() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Ok(null);
    try {
      final row = await retryTransient(
        () => _client.from('profiles').select(_cols).eq('id', uid).maybeSingle(),
      );
      return Ok(Profile.fromJson(row));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<Profile>> updateDisplayName(String name) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      final rows = await retryTransient(
        () => _client.from('profiles').update({'display_name': name.trim()}).eq('id', uid).select(_cols),
      );
      final p = rows.isEmpty ? null : Profile.fromJson(rows.first);
      return p == null ? const Err(AppFailure(FailureCode.notFound)) : Ok(p);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<List<VerificationBadge>>> myBadges() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Ok([]);
    try {
      final rows = await retryTransient(
        () => _client
            .from('verifications')
            .select('kind,is_mock,org_suffix,org_domains(org_name)')
            .eq('user_id', uid)
            .eq('status', 'verified'),
      );
      return Ok(parseOwnBadges(rows));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<Gender?>> getMyGender() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      // design-roles §14.6: self-view only RPC, not a SELECT column grant.
      final v = await retryTransient(() => _client.rpc('get_my_gender'));
      return Ok(Gender.fromDb(v));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> setMyGender(Gender g) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      await retryTransient(() => _client.from('profiles').update({'gender': g.db}).eq('id', uid));
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> clearMyGender() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      // The server auto-cancels pending/accepted Women-Only matches on this
      // write (Q7) via `profiles_gender_guard`; the client never re-implements
      // that guard, it just relies on the trigger and refreshes state after.
      await retryTransient(() => _client.from('profiles').update({'gender': null}).eq('id', uid));
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }
}

/// Maps `verifications` rows (with embedded `org_domains`) to badges, stable order: email, organization, phone.
List<VerificationBadge> parseOwnBadges(List<dynamic> rows) {
  const order = {'email': 0, 'organization': 1, 'phone': 2};
  final out = <VerificationBadge>[];
  for (final r in rows) {
    if (r is! Map || r['kind'] is! String) continue;
    final org = r['org_domains'];
    out.add(VerificationBadge(
      kind: r['kind'] as String,
      isMock: r['is_mock'] == true,
      orgName: org is Map ? org['org_name'] as String? : null,
    ));
  }
  out.sort((a, b) => (order[a.kind] ?? 9).compareTo(order[b.kind] ?? 9));
  return out;
}
