import 'dart:async';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../../core/geo/geo.dart';
import '../../../core/l10n/strings_r5.dart';
import '../../../core/net/throttle.dart' show Clock;
import '../../geo/domain/geo_services.dart';
import 'travel_mode.dart';

// ---------------------------------------------------------------------------------------------
// Heading, interpolation, staleness (US-23, round 5 decisions D4 / D13)
// ---------------------------------------------------------------------------------------------

/// Initial bearing a -> b in degrees (0 = north, clockwise), 0..360.
double bearingDeg(LatLng a, LatLng b) {
  final p1 = a.latitudeInRad;
  final p2 = b.latitudeInRad;
  final dl = (b.longitude - a.longitude) * math.pi / 180;
  final y = math.sin(dl) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Heading that only changes when the latest fix is at least [minMoveM] (15 m) away from the
/// previous reference point, so a parked or jittering icon does not spin (E-7).
class HeadingTracker {
  HeadingTracker({this.minMoveM = 15});
  final double minMoveM;
  LatLng? _ref;
  double? _heading;

  double? get heading => _heading;

  /// Returns the current heading (null until the first real movement).
  double? update(LatLng p) {
    final ref = _ref;
    if (ref == null) {
      _ref = p;
      return _heading;
    }
    if (haversineM(ref, p) >= minMoveM) {
      _heading = bearingDeg(ref, p);
      _ref = p;
    }
    return _heading;
  }

  void reset() {
    _ref = null;
    _heading = null;
  }
}

/// Smooth movement between two received fixes. Never extrapolates: at t >= duration the icon rests on the
/// last received position. A jump farther than [jumpM] (2 km), or reduce-motion, moves instantly.
class PositionInterpolator {
  PositionInterpolator({
    this.duration = const Duration(seconds: 1),
    this.jumpM = 2000,
    this.reduceMotion = false,
    Clock? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration duration;
  final double jumpM;
  bool reduceMotion;
  final Clock _clock;

  LatLng? _from;
  LatLng? _to;
  DateTime? _start;

  LatLng? get target => _to;

  /// Feeds a newly received fix. The animation starts from where the icon is drawn right now.
  void moveTo(LatLng next) {
    final now = _clock();
    final shown = valueAt(now);
    if (_to != null && _to == next) return;
    if (shown == null || reduceMotion || haversineM(shown, next) > jumpM) {
      _from = next;
      _to = next;
      _start = now;
      return;
    }
    _from = shown;
    _to = next;
    _start = now;
  }

  double _ease(double t) => t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;

  LatLng? valueAt(DateTime now) {
    final to = _to;
    final from = _from;
    final start = _start;
    if (to == null || from == null || start == null) return null;
    final ms = duration.inMilliseconds;
    if (ms <= 0) return to;
    final t = (now.difference(start).inMilliseconds / ms).clamp(0.0, 1.0);
    if (t >= 1) return to;
    final e = _ease(t);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * e,
      from.longitude + (to.longitude - from.longitude) * e,
    );
  }

  bool isAnimating(DateTime now) {
    final start = _start;
    return start != null && now.difference(start) < duration && _from != _to;
  }

  void clear() {
    _from = _to = null;
    _start = null;
  }
}

const staleAfter = Duration(seconds: 45);

/// A peer fix is stale once nothing newer arrived for [threshold] (45 s, config).
bool isStale(DateTime now, DateTime recordedAt, {Duration threshold = staleAfter}) =>
    now.difference(recordedAt) > threshold;

/// "อัปเดตเมื่อ N วินาทีที่แล้ว" while stale; minutes up to 10 min, then "ตำแหน่งล่าสุดเมื่อ HH:mm".
/// Null while the fix is still fresh.
String? staleLabel(DateTime now, DateTime recordedAt, {Duration threshold = staleAfter}) {
  if (!isStale(now, recordedAt, threshold: threshold)) return null;
  final d = now.difference(recordedAt);
  if (d < const Duration(minutes: 1)) return R5.liveUpdatedSeconds(d.inSeconds);
  if (d <= const Duration(minutes: 10)) return R5.liveUpdatedMinutes(d.inMinutes);
  final hh = recordedAt.hour.toString().padLeft(2, '0');
  final mm = recordedAt.minute.toString().padLeft(2, '0');
  return R5.liveLastSeenAt('$hh:$mm');
}

// ---------------------------------------------------------------------------------------------
// ETA (D13): OSRM duration, at most one routing call / 45 s, straight-line fallback
// ---------------------------------------------------------------------------------------------

class EtaResult {
  const EtaResult({required this.minutes, required this.approximate, this.geometry = const []});

  /// Whole minutes (>= 0). 0 means "almost there".
  final int minutes;

  /// True for the straight-line fallback (shown with "(ไม่แม่น)").
  final bool approximate;

  /// Route to draw (empty for the fallback).
  final List<LatLng> geometry;

  String get text => minutes < 1 ? R5.etaSoon : R5.etaMinutes(minutes) + (approximate ? ' ${R5.etaApproxTag}' : '');
}

/// Straight-line fallback: distance x 1.3 at the mode's average speed, rounded up to a minute.
EtaResult straightLineEta(LatLng from, LatLng to, {TravelMode mode = TravelMode.car}) {
  final metres = haversineM(from, to) * 1.3;
  final seconds = metres / (mode.avgKmh * 1000 / 3600);
  return EtaResult(minutes: (seconds / 60).ceil(), approximate: true);
}

/// Throttled ETA source. Repeated calls inside [minInterval] return the cached value unless the
/// target changed (pickup -> destination), which forces a fresh calculation.
class EtaService {
  EtaService({
    required this.routing,
    this.minInterval = const Duration(seconds: 45),
    this.mode = TravelMode.car,
    Clock? clock,
  }) : _clock = clock ?? DateTime.now;

  final RoutingService routing;
  final Duration minInterval;
  final TravelMode mode;
  final Clock _clock;

  DateTime? _lastCall;
  String? _lastTargetKey;
  EtaResult? _last;
  int routingCalls = 0;

  Future<EtaResult> eta({required LatLng from, required LatLng to}) async {
    final now = _clock();
    final key = coordKey(to);
    final last = _last;
    final at = _lastCall;
    if (last != null && at != null && key == _lastTargetKey && now.difference(at) < minInterval) {
      return last;
    }
    _lastCall = now; // count attempts too: a failing service must not be hammered
    _lastTargetKey = key;
    routingCalls++;
    EtaResult result;
    try {
      final r = await routing.route(mode: mode, from: from, to: to);
      result = EtaResult(minutes: (r.durationS / 60).ceil(), approximate: false, geometry: r.geometry);
    } catch (_) {
      result = straightLineEta(from, to, mode: mode);
    }
    _last = result;
    return result;
  }

  void reset() {
    _lastCall = null;
    _last = null;
    _lastTargetKey = null;
  }
}

/// 8-point compass label (Thai) from bearing degrees.
String compassThai(double deg) => R5.dirs[(((deg % 360) + 22.5) ~/ 45) % 8];

/// Coarse spoken distance for the text alternative (E-13): 0.1 km below 1 km, 0.5 km steps above.
String coarseDistanceText(double metres) {
  if (metres < 100) return 'ไม่ถึง 100 เมตร';
  if (metres < 1000) return '${(metres / 100).round() * 100} เมตร';
  final km = (metres / 500).round() * 0.5;
  return '${km.toStringAsFixed(km == km.roundToDouble() ? 0 : 1)} กิโลเมตร';
}

// ---------------------------------------------------------------------------------------------
// Live markers (what may be drawn). Pure so the privacy rule is testable.
// ---------------------------------------------------------------------------------------------

enum LiveMarkerKind { me, peerDriver, peerRider, pickup, myDestination }

class LiveMarker {
  const LiveMarker(this.kind, this.point, {this.stale = false, this.heading});
  final LiveMarkerKind kind;
  final LatLng point;
  final bool stale;
  final double? heading;
}

/// Markers of the shared map (S-37).
///
/// Privacy (Z-2): the map only ever contains my own destination, the agreed pickup and the
/// partner's LIVE position (icon by role). The partner's destination / drop-off is never an input.
/// A Driver stops seeing the Rider once the Rider boarded.
List<LiveMarker> buildLiveMarkers({
  required bool iAmDriver,
  required bool riderBoarded,
  required LatLng? me,
  required LatLng? peer,
  required bool peerStale,
  required double? peerHeading,
  required LatLng? pickup,
  required LatLng? myDestination,
}) {
  return [
    if (pickup != null && !riderBoarded) LiveMarker(LiveMarkerKind.pickup, pickup),
    if (myDestination != null) LiveMarker(LiveMarkerKind.myDestination, myDestination),
    if (peer != null && !(iAmDriver && riderBoarded))
      LiveMarker(
        iAmDriver ? LiveMarkerKind.peerRider : LiveMarkerKind.peerDriver,
        peer,
        stale: peerStale,
        heading: iAmDriver ? null : peerHeading, // the person pin never rotates
      ),
    if (me != null) LiveMarker(LiveMarkerKind.me, me),
  ];
}
