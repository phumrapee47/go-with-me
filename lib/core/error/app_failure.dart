/// Canonical client-side error (design-api section 6). Raw Postgrest/Auth
/// exceptions must never leave the data layer.
class AppFailure implements Exception {
  const AppFailure(
    this.code, {
    this.field,
    this.retryable = false,
    this.retryAfter,
  });

  /// Machine-readable, language independent (e.g. `GWM_DEPART_IN_PAST`).
  final String code;

  /// Form field the error belongs to (`email`, `password`, `depart_at`...).
  final String? field;
  final bool retryable;
  final Duration? retryAfter;

  @override
  String toString() => 'AppFailure($code)';
}

abstract final class FailureCode {
  static const unknown = 'UNKNOWN';
  static const validation = 'VALIDATION';
  static const notFound = 'NOT_FOUND';
  static const duplicate = 'DUPLICATE';
  static const staleReference = 'STALE_REFERENCE';
  static const forbiddenRls = 'FORBIDDEN_RLS';
  static const forbiddenColumn = 'FORBIDDEN_COLUMN';
  static const sessionExpired = 'SESSION_EXPIRED';
  static const serverUnavailable = 'SERVER_UNAVAILABLE';
  static const rateLimited = 'RATE_LIMITED';
  static const networkOffline = 'NETWORK_OFFLINE';
  static const networkTimeout = 'NETWORK_TIMEOUT';
  static const realtimeDisconnected = 'REALTIME_DISCONNECTED';
  static const configMissing = 'CONFIG_MISSING';
  static const shareLinkInvalid = 'SHARE_LINK_INVALID';
  static const uploadTooLarge = 'UPLOAD_TOO_LARGE';
  static const uploadType = 'UPLOAD_TYPE';
  static const authInvalidCredentials = 'AUTH_INVALID_CREDENTIALS';
  static const authEmailTaken = 'AUTH_EMAIL_TAKEN';
  static const authWeakPassword = 'AUTH_WEAK_PASSWORD';
  static const authEmailUnconfirmed = 'AUTH_EMAIL_UNCONFIRMED';
  static const signupRequirements = 'GWM_SIGNUP_REQUIREMENTS';
  static const accountDeleted = 'GWM_ACCOUNT_DELETED';
  static const routeNotFound = 'ROUTE_NOT_FOUND';
  static const locationDenied = 'LOCATION_DENIED';
  static const locationUnavailable = 'LOCATION_UNAVAILABLE';

  /// BUG-2 (web current-location fix): the Geolocation API is blocked by the
  /// browser itself on a plain `http://` origin other than localhost (e.g.
  /// Safari on iOS testing over a LAN IP) — distinct from a normal
  /// permission/GPS failure, so it needs its own honest message rather than
  /// falling into the generic `locationUnavailable` bucket.
  static const locationInsecureOrigin = 'LOCATION_INSECURE_ORIGIN';

  /// US-50 (round 7 Stage D): the client-side precise (OSRM) detour calculation
  /// failed/timed out before `request_match` was even called. Distinct from
  /// `GWM_DETOUR_IMPLAUSIBLE` (a server-side rejection of a value that WAS sent):
  /// this means no value was computed at all, so the request is not attempted
  /// with a guessed number (see `computePreciseDetourM`, docs/design-roles.md §16).
  static const detourCalcFailed = 'DETOUR_CALC_FAILED';
}
