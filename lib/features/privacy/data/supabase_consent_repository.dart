import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../../../core/net/retry.dart';
import '../domain/consent_repository.dart';

class SupabaseConsentRepository implements ConsentRepository {
  SupabaseConsentRepository(this._client);
  final sb.SupabaseClient _client;

  @override
  Future<Result<void>> recordLocationConsent({required bool granted, required String policyVersion}) async {
    try {
      // Append-only log: a retry may add a duplicate row, which is harmless.
      await retryTransient(
        () => _client.rpc('record_consent', params: {
          'p_kind': 'location',
          'p_granted': granted,
          'p_version': policyVersion,
        }),
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<bool>> locationConsentGranted() async {
    try {
      final rows = await retryTransient(
        () => _client
            .from('consents')
            .select('granted')
            .eq('kind', 'location')
            .order('created_at', ascending: false)
            .limit(1),
      );
      return Ok(rows.isNotEmpty && rows.first['granted'] == true);
    } catch (e) {
      return Err(mapError(e));
    }
  }
}

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);
  final sb.SupabaseClient _client;

  @override
  Future<Result<String>> exportMyData() async {
    try {
      final res = await retryTransient(() => _client.rpc('export_my_data'));
      return Ok(const JsonEncoder.withIndent('  ').convert(res));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> requestAccountDeletion() async {
    try {
      await retryTransient(() => _client.rpc('request_account_deletion'));
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }
}
