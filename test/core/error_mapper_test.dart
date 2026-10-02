import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/error/error_mapper.dart';
import 'package:gowithme/core/error/failure_messages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('GWM code in P0001 message is used directly', () {
    final f = mapError(const PostgrestException(message: 'GWM_DEPART_IN_PAST', code: 'P0001'));
    expect(f.code, 'GWM_DEPART_IN_PAST');
    expect(failureMessage(f), 'เลือกเวลาที่ยังมาไม่ถึง');
  });

  test('GWM_RATE_LIMITED is retryable', () {
    final f = mapError(const PostgrestException(message: 'GWM_RATE_LIMITED', code: 'P0001'));
    expect(f.retryable, isTrue);
  });

  test('RLS vs column permission', () {
    expect(
      mapError(const PostgrestException(
        message: 'new row violates row-level security policy',
        code: '42501',
      )).code,
      FailureCode.forbiddenRls,
    );
    expect(
      mapError(const PostgrestException(message: 'permission denied for table x', code: '42501'))
          .code,
      FailureCode.forbiddenColumn,
    );
  });

  test('postgres codes', () {
    String c(String code) => mapError(PostgrestException(message: 'm', code: code)).code;
    expect(c('23505'), FailureCode.duplicate);
    expect(c('23503'), FailureCode.staleReference);
    expect(c('23514'), FailureCode.validation);
    expect(c('PGRST116'), FailureCode.notFound);
    expect(c('PGRST301'), FailureCode.sessionExpired);
    expect(c('57014'), FailureCode.serverUnavailable);
    expect(c('XX000'), FailureCode.unknown);
  });

  test('unknown GWM code falls back to generic Thai text', () {
    final f = mapError(const PostgrestException(message: 'GWM_NEW_THING', code: 'P0001'));
    expect(f.code, 'GWM_NEW_THING');
    expect(failureMessage(f), failureMessage(const AppFailure(FailureCode.unknown)));
  });

  test('auth codes', () {
    AppFailure a(String code, [String? status]) =>
        mapError(AuthException('x', statusCode: status, code: code));
    expect(a('invalid_credentials', '400').code, FailureCode.authInvalidCredentials);
    expect(a('email_exists', '422').code, FailureCode.authEmailTaken);
    expect(a('email_exists', '422').field, 'email');
    expect(a('weak_password', '422').code, FailureCode.authWeakPassword);
    expect(a('email_not_confirmed', '400').code, FailureCode.authEmailUnconfirmed);
    expect(a('over_email_send_rate_limit', '429').retryAfter, const Duration(seconds: 30));
  });

  test('network errors', () {
    expect(mapError(const SocketException('x')).code, FailureCode.networkOffline);
    expect(mapError(TimeoutException('x')).code, FailureCode.networkTimeout);
    expect(mapError(StateError('boom')).code, FailureCode.unknown);
  });

  group('service HTTP errors', () {
    test('429/403 mean throttled: not retryable, Retry-After honoured, default 60 s', () {
      final a = mapServiceHttpError(429, retryAfterHeader: '45');
      expect(a.code, FailureCode.rateLimited);
      expect(a.retryable, isFalse);
      expect(a.retryAfter, const Duration(seconds: 45));
      expect(mapServiceHttpError(403).retryAfter, const Duration(seconds: 60));
    });

    test('5xx retryable, other 4xx unknown', () {
      expect(mapServiceHttpError(503).code, FailureCode.serverUnavailable);
      expect(mapServiceHttpError(503).retryable, isTrue);
      expect(mapServiceHttpError(404).code, FailureCode.unknown);
    });
  });

  group('Phase 3 codes have specific Thai messages', () {
    final generic = failureMessage(const AppFailure(FailureCode.unknown));
    for (final code in [
      'GWM_ADULT_REQUIRED',
      'GWM_CONSENT_REQUIRED',
      'GWM_EMAIL_NOT_VERIFIED',
      'GWM_INVALID_POINT',
      'GWM_MATCH_CLOSED',
      'GWM_NO_PROPOSAL',
      'GWM_OWN_PROPOSAL',
      'GWM_PENDING_LIMIT',
      'GWM_TRIP_HAS_MATCHES',
      FailureCode.routeNotFound,
      FailureCode.locationDenied,
      FailureCode.locationUnavailable,
    ]) {
      test(code, () => expect(failureMessage(AppFailure(code)), isNot(generic)));
    }

    test('server message text is never surfaced', () {
      final f = mapError(const PostgrestException(message: 'GWM_PENDING_LIMIT', code: 'P0001'));
      expect(failureMessage(f), isNot(contains('GWM_')));
    });
  });

  group('Round 7 Stage D codes (US-50, migration 0016)', () {
    final generic = failureMessage(const AppFailure(FailureCode.unknown));

    test('GWM_DETOUR_IMPLAUSIBLE has a specific, non-generic Thai message', () {
      final f = mapError(const PostgrestException(message: 'GWM_DETOUR_IMPLAUSIBLE', code: 'P0001'));
      expect(failureMessage(f), isNot(generic));
      expect(failureMessage(f), isNot(contains('GWM_')));
    });

    test('DETOUR_CALC_FAILED (client-side, no server round trip) has a specific '
        '"ลองใหม่อีกครั้ง" Thai message, distinct from GWM_DETOUR_IMPLAUSIBLE', () {
      const calcFailed = AppFailure(FailureCode.detourCalcFailed, retryable: true);
      const implausible = AppFailure('GWM_DETOUR_IMPLAUSIBLE');
      expect(failureMessage(calcFailed), isNot(generic));
      expect(failureMessage(calcFailed), contains('ลองใหม่อีกครั้ง'));
      expect(failureMessage(calcFailed), isNot(failureMessage(implausible)));
    });
  });
}
