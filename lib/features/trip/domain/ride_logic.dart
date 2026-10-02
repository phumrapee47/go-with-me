import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo/geo.dart';
import '../../../core/l10n/strings_r6.dart';
import '../../matching/domain/match_models.dart';
import '../../presets/presentation/preset_providers.dart' show homePresetPointProvider;
import 'trip.dart';

// ---------------------------------------------------------------------------
// Geofence highlight (US-32). PRESENTATION ONLY: it never gates a status change,
// is computed on the device from the user's OWN pickup / destination, and nothing
// derived from it is sent anywhere.
// ---------------------------------------------------------------------------

/// Entering "near": strictly closer than this (149 m yes, 150 m / 151 m no).
const nearEnterM = 150.0;

/// Leaving "near": at or beyond this distance (hysteresis so a wobbling GPS does not blink).
const nearExitM = 180.0;

/// Once near, stay near at least this long before any exit.
const nearMinHold = Duration(seconds: 3);

/// Fixes worse than this are ignored (treated as "no reliable position").
const nearMaxAccuracyM = 100.0;

/// Entry/exit hysteresis around [nearEnterM] / [nearExitM]. Pure and deterministic
/// (callers pass the clock) so it is unit-testable.
class NearGate {
  bool _near = false;
  DateTime? _enteredAt;

  bool get near => _near;

  /// Feeds one sample; returns the (possibly unchanged) near flag.
  /// A missing position/target or a poor fix means "no highlight, no error".
  bool update({required DateTime now, LatLng? me, LatLng? target, double? accuracyM}) {
    if (me == null || target == null || (accuracyM != null && accuracyM > nearMaxAccuracyM)) {
      // No reliable input: never keep a highlight that cannot be justified.
      if (me == null || target == null) {
        _near = false;
        _enteredAt = null;
      }
      return _near;
    }
    final d = haversineM(me, target);
    if (!_near) {
      if (d < nearEnterM) {
        _near = true;
        _enteredAt = now;
      }
    } else if (d >= nearExitM && now.difference(_enteredAt ?? now) >= nearMinHold) {
      _near = false;
      _enteredAt = null;
    }
    return _near;
  }

  void reset() {
    _near = false;
    _enteredAt = null;
  }
}

// ---------------------------------------------------------------------------
// Arrival wording (Q5 / P-4). "Home" only when the destination matches the saved
// Home preset (stage D). Until presets exist the matcher answers "unknown", which
// is the safe generic fallback.
// ---------------------------------------------------------------------------

enum HomeMatch { home, notHome, unknown }

/// Compares a trip destination with the saved Home preset ON DEVICE. Nothing is
/// sent to a server. Stage D replaces the default implementation.
abstract class HomeDestinationMatcher {
  HomeMatch match(Trip trip);
}

class UnknownHomeDestinationMatcher implements HomeDestinationMatcher {
  const UnknownHomeDestinationMatcher();
  @override
  HomeMatch match(Trip trip) => HomeMatch.unknown;
}

/// Same radius as the one-tap card (a trip made from the card ends exactly on the Home preset).
const homeMatchRadiusM = 150.0;

/// Q5 / P-4, on device: no Home preset = [HomeMatch.unknown]; a car trip whose destination is within
/// [homeMatchRadiusM] of the Home preset = [HomeMatch.home]; anything else (other place, Peer modes) = [HomeMatch.notHome].
class PresetHomeDestinationMatcher implements HomeDestinationMatcher {
  const PresetHomeDestinationMatcher(this.home, {this.radiusM = homeMatchRadiusM});
  final LatLng? home;
  final double radiusM;

  @override
  HomeMatch match(Trip trip) {
    final h = home;
    if (h == null) return HomeMatch.unknown;
    if (!trip.isCar) return HomeMatch.notHome;
    return haversineM(trip.dest, h) <= radiusM ? HomeMatch.home : HomeMatch.notHome;
  }
}

final homeDestinationMatcherProvider =
    Provider<HomeDestinationMatcher>((ref) => PresetHomeDestinationMatcher(ref.watch(homePresetPointProvider)));

/// Only an explicit [HomeMatch.home] earns the "home" wording.
bool isHomeArrival(HomeMatch m) => m == HomeMatch.home;

String arriveSliderLabel(HomeMatch m) => isHomeArrival(m) ? R6.sliderArriveHome : R6.sliderArriveDest;
String arrivedMessage(HomeMatch m) => isHomeArrival(m) ? R6.arrivedHome : R6.arrivedDest;
String arrivedMessageSemantics(HomeMatch m) => isHomeArrival(m) ? R6.arrivedHomeSemantics : R6.arrivedDestSemantics;

// ---------------------------------------------------------------------------
// Ride state (F.3.4)
// ---------------------------------------------------------------------------

enum RideState { scheduled, onTheWay, boarded, arrived, peerEnded }

/// Which primary action the Collapsed sheet shows.
enum RidePrimary { none, waiting, sliderStart, sliderBoard, sliderArrive, arrivedAtPickup, arrivedSummary }

/// One-tap "arrived at pickup" cooldown (US-33): at most once per minute.
const arrivedAtPickupCooldown = Duration(seconds: 60);

/// Pure per-screen limiter so the rule is testable without a widget.
class CooldownGate {
  CooldownGate({this.window = arrivedAtPickupCooldown});
  final Duration window;
  DateTime? _last;

  bool tryAcquire(DateTime now) {
    final l = _last;
    if (l != null && now.difference(l) < window) return false;
    _last = now;
    return true;
  }

  void release() => _last = null; // failed send: allow an immediate retry

  int secondsLeft(DateTime now) {
    final l = _last;
    if (l == null) return 0;
    final left = window - now.difference(l);
    return left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
  }
}

/// The match shown on the ride screen for my trip [t]: the accepted one, else (car only) one
/// that just ended while I am still travelling (Driver "carry on" line / Rider who had boarded).
MatchSummary? rideMatchFor(Trip t, List<MatchSummary> inbox) {
  MatchSummary? ended;
  for (final x in inbox) {
    if (x.myTripId != t.id) continue;
    if (x.status == MatchStatus.accepted) return x;
    final live = x.boarded && x.status == MatchStatus.cancelled;
    final driverEnded = x.iAmDriver && x.status == MatchStatus.cancelled && !x.autoClosed;
    if (x.isCar && (live || driverEnded)) ended = x;
  }
  return ended;
}

/// Which primary action the Collapsed sheet shows (design-spec F.3.4 + P-5/P-9).
RidePrimary ridePrimaryFor({required Trip trip, required MatchSummary? match, required bool arrivedState}) {
  if (arrivedState) return RidePrimary.arrivedSummary;
  if (trip.status == TripStatus.scheduled) return RidePrimary.sliderStart;
  if (match != null && match.status == MatchStatus.accepted && match.isCar && !match.boarded) {
    return match.iAmRider ? RidePrimary.sliderBoard : RidePrimary.arrivedAtPickup;
  }
  return RidePrimary.sliderArrive;
}
