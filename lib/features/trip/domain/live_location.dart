import 'package:latlong2/latlong.dart';

import '../../../core/config/app_constants.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/error/result.dart';
import '../../../core/geo/geo.dart';
import '../../../core/net/throttle.dart';
import '../../geo/domain/location_service.dart';
import 'trip.dart';

class PartnerLocation {
  const PartnerLocation({required this.point, required this.recordedAt});
  final LatLng point;
  final DateTime recordedAt;
}

abstract class LiveLocationRepository {
  /// Appends one breadcrumb (`trip_locations`). The server accepts at most
  /// one row per 5 s per trip (`GWM_RATE_LIMITED` otherwise).
  Future<Result<void>> push(String tripId, LocationFix fix);

  /// `get_partner_live_location`: null when nothing may be shown (partner not
  /// travelling, near their destination, a block exists, not consented...).
  Future<Result<PartnerLocation?>> partnerLocation(String matchId);
}

enum PushOutcome { sent, throttled, stale, inactive, dropped, stopped }

/// Decides which fixes are worth sending while a trip is active (design-api
/// 7.5): at most one per [minInterval], nothing older than [maxAge], fire and
/// forget (no queue: an old position has no value), and it stops for good on
/// a permission denial from the server.
class LiveLocationSharer {
  LiveLocationSharer({
    required this.repo,
    Clock? clock,
    Duration? minInterval,
    this.maxAge = const Duration(minutes: 2),
  })  : minInterval = minInterval ?? livePushInterval,
        _clock = clock ?? DateTime.now;

  /// Default push cadence (15 s, from the Dart constant AppConstants.livePushIntervalSec).
  /// The DB rate guard (1 row / 5 s / trip) stays as 3x headroom.
  static final livePushInterval = AppConstants.livePushInterval();

  final LiveLocationRepository repo;
  final Clock _clock;
  final Duration minInterval;
  final Duration maxAge;

  String? _tripId;
  DateTime? _lastPush;
  bool _stoppedByServer = false;

  bool get active => _tripId != null && !_stoppedByServer;

  void start(String tripId) {
    _tripId = tripId;
    _lastPush = null;
    _stoppedByServer = false;
  }

  void stop() {
    _tripId = null;
  }

  Future<PushOutcome> onFix(LocationFix fix) async {
    final trip = _tripId;
    if (trip == null || _stoppedByServer) return PushOutcome.inactive;
    final now = _clock();
    if (now.difference(fix.at) > maxAge) return PushOutcome.stale;
    final last = _lastPush;
    if (last != null && now.difference(last) < minInterval) return PushOutcome.throttled;
    _lastPush = now; // count attempts too, so failures cannot burst
    final res = await repo.push(trip, fix);
    // The trip may have ended while the request was in flight.
    if (_tripId != trip) return PushOutcome.inactive;
    return res.when(
      ok: (_) => PushOutcome.sent,
      err: (f) {
        if (f.code == FailureCode.forbiddenRls || f.code == 'GWM_FORBIDDEN') {
          // No consent / trip not in progress: stop asking until restarted.
          _stoppedByServer = true;
          return PushOutcome.stopped;
        }
        return PushOutcome.dropped; // rate limited or transient: drop silently
      },
    );
  }
}

enum ArrivalPrompt { none, near, overdue }

/// Arrival banner logic (US-12): "near" within 300 m of the destination
/// (from local GPS), "overdue" 30 min after the expected arrival. Dismissed
/// prompts are the caller's business.
ArrivalPrompt arrivalPromptFor({
  required Trip trip,
  required DateTime now,
  LatLng? position,
  Duration overdueAfter = const Duration(minutes: 30),
}) {
  if (position != null && haversineM(position, trip.dest) <= AppConstants.arrivalRadiusMeters) {
    return ArrivalPrompt.near;
  }
  final start = trip.startedAt ?? trip.departAt;
  final expected = start.add(Duration(seconds: trip.durationS));
  if (trip.durationS > 0 && now.isAfter(expected.add(overdueAfter))) return ArrivalPrompt.overdue;
  return ArrivalPrompt.none;
}

/// Remaining distance to the destination in metres, or null without a fix.
int? remainingDistanceM(Trip trip, LatLng? position) =>
    position == null ? null : haversineM(position, trip.dest).round();
