import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_failure.dart';

/// Converts any low-level exception into [AppFailure] (design-api 6.2).
/// Called only at the data-layer boundary.
AppFailure mapError(Object e) {
  if (e is AppFailure) return e;
  if (e is AuthException) return _mapAuth(e);
  if (e is PostgrestException) return _mapPostgrest(e);
  if (e is StorageException) return _mapStorage(e);
  if (e is FunctionException) return _mapStatus(e.status);
  if (e is SocketException) {
    return const AppFailure(FailureCode.networkOffline, retryable: true);
  }
  if (e is TimeoutException) {
    return const AppFailure(FailureCode.networkTimeout, retryable: true);
  }
  // supabase_flutter wraps some socket errors in ClientException-like types.
  final name = e.runtimeType.toString();
  if (name == 'ClientException' || name == 'HandshakeException') {
    return const AppFailure(FailureCode.networkOffline, retryable: true);
  }
  return const AppFailure(FailureCode.unknown);
}

AppFailure _mapAuth(AuthException e) {
  final status = int.tryParse(e.statusCode ?? '');
  final msg = e.message.toLowerCase();
  switch (e.code) {
    case 'invalid_credentials':
      return const AppFailure(FailureCode.authInvalidCredentials);
    case 'user_already_exists':
    case 'email_exists':
      return const AppFailure(FailureCode.authEmailTaken, field: 'email');
    case 'weak_password':
      return const AppFailure(FailureCode.authWeakPassword, field: 'password');
    case 'email_not_confirmed':
      return const AppFailure(FailureCode.authEmailUnconfirmed);
    case 'user_banned':
      return const AppFailure(FailureCode.accountDeleted);
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return const AppFailure(
        FailureCode.rateLimited,
        retryable: true,
        retryAfter: Duration(seconds: 30),
      );
  }
  // Older GoTrue versions send no `code`; fall back to status/message.
  if (status == 429) {
    return const AppFailure(
      FailureCode.rateLimited,
      retryable: true,
      retryAfter: Duration(seconds: 30),
    );
  }
  // T5.11: the handle_new_user trigger rejects signups without 18+/policy; GoTrue only says "Database error saving new user".
  if (msg.contains('database error saving new user')) {
    return const AppFailure(FailureCode.signupRequirements);
  }
  // T5.12: deleted accounts are banned server-side.
  if (msg.contains('user is banned') || msg.contains('user_banned')) {
    return const AppFailure(FailureCode.accountDeleted);
  }
  if (msg.contains('invalid login credentials')) {
    return const AppFailure(FailureCode.authInvalidCredentials);
  }
  if (msg.contains('email not confirmed')) {
    return const AppFailure(FailureCode.authEmailUnconfirmed);
  }
  if (msg.contains('already registered')) {
    return const AppFailure(FailureCode.authEmailTaken, field: 'email');
  }
  if (msg.contains('password') && (msg.contains('weak') || msg.contains('at least'))) {
    return const AppFailure(FailureCode.authWeakPassword, field: 'password');
  }
  if (e is AuthSessionMissingException || status == 401) {
    return const AppFailure(FailureCode.sessionExpired);
  }
  if (e is AuthRetryableFetchException || (status != null && status >= 500)) {
    return const AppFailure(FailureCode.serverUnavailable, retryable: true);
  }
  return const AppFailure(FailureCode.unknown);
}

AppFailure _mapPostgrest(PostgrestException e) {
  final code = e.code ?? '';
  final msg = e.message;

  // Business errors raised by our RPC/triggers: the code is in `message`.
  if (msg.startsWith('GWM_') && (code == 'P0001' || code == '42501')) {
    final gwm = msg.split(RegExp(r'[\s:]')).first;
    return AppFailure(gwm, retryable: gwm == 'GWM_RATE_LIMITED');
  }
  if (code == '42501') {
    return AppFailure(
      msg.contains('row-level security')
          ? FailureCode.forbiddenRls
          : FailureCode.forbiddenColumn,
    );
  }
  switch (code) {
    case '23505':
      return const AppFailure(FailureCode.duplicate);
    case '23514':
      return const AppFailure(FailureCode.validation);
    case '23503':
      return const AppFailure(FailureCode.staleReference);
    case '22P02':
    case '22023':
    case 'PGRST102':
      return const AppFailure(FailureCode.validation);
    case 'PGRST116':
      return const AppFailure(FailureCode.notFound);
    case 'PGRST301':
    case 'PGRST303':
      return const AppFailure(FailureCode.sessionExpired);
    case 'PGRST000':
    case 'PGRST001':
    case 'PGRST002':
    case '57014':
      return const AppFailure(FailureCode.serverUnavailable, retryable: true);
  }
  return _mapStatus(int.tryParse(code));
}

AppFailure _mapStorage(StorageException e) {
  switch (int.tryParse(e.statusCode ?? '')) {
    case 413:
      return const AppFailure(FailureCode.uploadTooLarge);
    case 415:
      return const AppFailure(FailureCode.uploadType);
  }
  return _mapStatus(int.tryParse(e.statusCode ?? ''));
}

AppFailure _mapStatus(int? status) {
  if (status == 401) return const AppFailure(FailureCode.sessionExpired);
  if (status == 429) {
    return const AppFailure(
      FailureCode.rateLimited,
      retryable: true,
      retryAfter: Duration(seconds: 30),
    );
  }
  if (status == 503 || status == 504) {
    return const AppFailure(FailureCode.serverUnavailable, retryable: true);
  }
  return const AppFailure(FailureCode.unknown);
}

/// Maps an HTTP status from a third-party service (Nominatim/OSRM) to a
/// failure. 429/403 mean we are being throttled: never retry immediately,
/// honour `Retry-After` (default 60s, design-api section 9.2).
AppFailure mapServiceHttpError(int status, {String? retryAfterHeader}) {
  if (status == 429 || status == 403) {
    final secs = int.tryParse(retryAfterHeader ?? '');
    return AppFailure(
      FailureCode.rateLimited,
      retryAfter: Duration(seconds: (secs != null && secs > 0) ? secs : 60),
    );
  }
  if (status == 408) return const AppFailure(FailureCode.networkTimeout, retryable: true);
  if (status >= 500) return const AppFailure(FailureCode.serverUnavailable, retryable: true);
  return const AppFailure(FailureCode.unknown);
}
