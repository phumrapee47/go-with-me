/// Single place for tunables (T1.7). Server-side values live in `app_config`;
/// these are client defaults only.
abstract final class AppConstants {
  static const appName = 'กลับด้วยกันมั้ย';
  static const tagline = 'ทางเดียวกัน กลับด้วยกัน';

  /// Sent with sign-up so the server can record consent (design-api section 5).
  static const policyVersion = '0.1-draft';

  static const minPasswordLength = 8;
  /// Matches assets/mascot/video/splash_intro.mp4's length exactly so the
  /// clip finishes right as the router moves on — never cut off, never lingers.
  static const splashDuration = Duration(milliseconds: 6042);
  static const resendCooldown = Duration(seconds: 60);

  /// Live location push cadence (T5.17). Dart constant, default 15 s (no remote config key).
  /// The DB rate guard (5 s per trip) is deliberately NOT changed: it gives 3x headroom.
  static const livePushIntervalSec = 15;
  static const livePushIntervalMinSec = 15;
  static const livePushIntervalMaxSec = 30;

  /// Clamps a configured value into the allowed 15-30 s range.
  static Duration livePushInterval([int? secs]) => Duration(
        seconds: (secs ?? livePushIntervalSec).clamp(livePushIntervalMinSec, livePushIntervalMaxSec),
      );

  // Matching limits (informational until Phase 3).
  static const maxActiveTrips = 1;
  static const maxMatchesPerTrip = 3;
  static const tripExpiry = Duration(hours: 2);
  static const arrivalRadiusMeters = 300;

  // Third-party endpoints (used from Phase 3+).
  static const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
  static const osrmBaseUrl = 'https://router.project-osrm.org';
}
