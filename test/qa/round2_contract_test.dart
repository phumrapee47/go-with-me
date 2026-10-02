// QA round 2: Dart <-> SQL contract for migration 0003 (static scans + error mapping). No network.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/config/app_constants.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/error/error_mapper.dart';
import 'package:gowithme/core/error/failure_messages.dart';
import 'package:gowithme/features/auth/data/supabase_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final sql0003 = File('supabase/migrations/0003_qa_round1.sql').readAsStringSync();

  test('policy version: SQL config == AppConstants.policyVersion == seed', () {
    final m = RegExp(r'''policy\.current_version',\s*'"([^"]+)"''').firstMatch(sql0003);
    expect(m, isNotNull);
    expect(m!.group(1), AppConstants.policyVersion);
    expect(File('supabase/seed.sql').readAsStringSync(), contains("'policy_version', '${AppConstants.policyVersion}'"));
  });

  test('signup metadata keys used by the client are the ones the trigger reads', () {
    final client = File('lib/features/auth/data/supabase_auth_repository.dart').readAsStringSync();
    for (final k in ['adult_confirmed', 'policy_version', 'display_name']) {
      expect(client, contains("'$k'"));
      expect(sql0003, contains("->> '$k'"));
    }
    expect(client, contains("'adult_confirmed': true"));
  });

  test('GWM_ADULT_REQUIRED / GWM_CONSENT_REQUIRED raised by SQL are mapped to Thai text', () {
    for (final c in ['GWM_ADULT_REQUIRED', 'GWM_CONSENT_REQUIRED']) {
      expect(sql0003, contains("raise exception '$c'"));
      final f = mapError(PostgrestException(message: c, code: 'P0001'));
      expect(f.code, c);
      expect(failureMessage(f), isNot(contains('GWM_')));
      expect(failureMessage(f), isNot(failureMessage(const AppFailure(FailureCode.unknown))));
    }
  });

  test('GoTrue "Database error saving new user" -> signupRequirements', () {
    final f = mapError(const AuthException('Database error saving new user', statusCode: '500'));
    expect(f.code, FailureCode.signupRequirements);
    final f2 = mapError(const AuthApiException('Database error saving new user', statusCode: '500', code: 'unexpected_failure'));
    expect(f2.code, FailureCode.signupRequirements);
  });

  test('banned user sign-in -> accountDeleted', () {
    expect(mapError(const AuthApiException('User is banned', statusCode: '400', code: 'user_banned')).code, FailureCode.accountDeleted);
    expect(mapError(const AuthException('User is banned', statusCode: '400')).code, FailureCode.accountDeleted);
  });

  test('0003 does not weaken security: no client insert on consents, no client update of adult_confirmed_at', () {
    expect(sql0003, contains('revoke update (adult_confirmed_at) on public.profiles from authenticated'));
    expect(sql0003, contains('revoke insert on public.consents from authenticated'));
    // no Dart code writes consents / adult_confirmed_at directly
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      expect(RegExp(r"from\('consents'\)\s*\.insert").hasMatch(s), isFalse, reason: f.path);
      expect(s.contains('adult_confirmed_at'), isFalse, reason: f.path);
    }
  });

  test('client deletion check reads deleted_at (profiles_select does not hide own deleted profile)', () {
    final src = File('lib/features/auth/data/supabase_auth_repository.dart').readAsStringSync();
    expect(src, contains("select('id, deleted_at')"));
    expect(src, contains('isDeletedProfileRows'));
  });

  test('isDeletedProfileRows: empty or deleted_at set -> deleted; live row -> not', () {
    expect(isDeletedProfileRows([]), isTrue);
    expect(isDeletedProfileRows([{'id': 'u', 'deleted_at': '2026-01-01T00:00:00Z'}]), isTrue);
    expect(isDeletedProfileRows([{'id': 'u', 'deleted_at': null}]), isFalse);
  });
}
