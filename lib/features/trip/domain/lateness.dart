import 'package:latlong2/latlong.dart';

import '../../../core/geo/geo.dart';

/// US-49 (round 7 Stage C): client-side lateness DETECTION only — used to decide when to SHOW the
/// two-choice card ("รอต่ออีก 10 นาที" / "ยกเลิกการเดินทาง (ไม่เสียประวัติ)"). The server
/// (`cancel_match_no_fault` RPC, migration 0014) re-verifies both conditions itself from
/// `trips.depart_at`/`trip_locations` and NEVER trusts this client computation — see
/// docs/design-roles.md #15.3. This file mirrors the server's config defaults
/// (`lateness.overdue_min`/`eta_stall_window_min`/`eta_stall_m`) as client-side constants purely for
/// UX responsiveness; only `overdue_min` is `is_public` server-side (shown to the user as "N นาที").
abstract final class LatenessRules {
  /// Mirrors `lateness.overdue_min` (Q11(a)).
  static const overdueMin = Duration(minutes: 10);

  /// Mirrors `lateness.eta_stall_window_min` (Q11(b)): look at samples within this many minutes back.
  static const staleWindow = Duration(minutes: 5);

  /// Mirrors `lateness.eta_stall_m` (Q11(b)): must shrink by at least this many metres to NOT be stalled.
  static const stallM = 100.0;

  /// The "wait 10 more minutes" snooze duration (client-only UI state; no RPC/schema — see #15.3).
  static const snooze = Duration(minutes: 10);
}

enum LatenessTrigger { none, overdue, etaStalled }

/// One breadcrumb: a live position + when it was recorded. Reuses whatever the existing
/// live-tracking poll already produces (own GPS fixes and/or the partner's `trip_locations` reads
/// via `get_partner_live_location`) — no new tracking infrastructure.
class LocationSample {
  const LocationSample({required this.point, required this.at});
  final LatLng point;
  final DateTime at;
}

/// Q11(a): overdue when now() is more than [LatenessRules.overdueMin] past the later of the two
/// matched trips' `depart_at` (the best available proxy for "the agreed meeting time" — there is no
/// separate stored pickup TIME, only a pickup POINT via `matches.meeting_point`; see design-roles.md
/// #15.3/#15.4 open question 1).
bool isOverdueByTime({
  required DateTime driverDepartAt,
  required DateTime riderDepartAt,
  required DateTime now,
  Duration overdueMin = LatenessRules.overdueMin,
}) {
  final agreed = driverDepartAt.isAfter(riderDepartAt) ? driverDepartAt : riderDepartAt;
  return now.isAfter(agreed.add(overdueMin));
}

/// Q11(b): "ETA ไม่ดีขึ้นเลย" — approximated (like the server) as the straight-line distance to the
/// meeting point across the LAST 3 samples inside [window] not shrinking by at least [stallM] metres
/// between the oldest and the newest of those 3. Fewer than 3 samples in the window = not stalled
/// (never a false positive from sparse data).
bool isEtaStalled({
  required List<LocationSample> samples,
  required LatLng meetingPoint,
  required DateTime now,
  Duration window = LatenessRules.staleWindow,
  double stallM = LatenessRules.stallM,
}) {
  final inWindow = [for (final s in samples) if (now.difference(s.at) <= window) s]
    ..sort((a, b) => b.at.compareTo(a.at)); // newest first
  if (inWindow.length < 3) return false;
  final last3 = inWindow.take(3).toList();
  final dNewest = haversineM(last3.first.point, meetingPoint);
  final dOldest = haversineM(last3.last.point, meetingPoint);
  return (dOldest - dNewest) < stallM;
}

/// Combines Q11(a) OR Q11(b) (either condition alone is enough — see requirements US-49 AC1).
LatenessTrigger checkLateness({
  required DateTime driverDepartAt,
  required DateTime riderDepartAt,
  required DateTime now,
  required List<LocationSample> samples,
  required LatLng meetingPoint,
}) {
  if (isOverdueByTime(driverDepartAt: driverDepartAt, riderDepartAt: riderDepartAt, now: now)) {
    return LatenessTrigger.overdue;
  }
  if (isEtaStalled(samples: samples, meetingPoint: meetingPoint, now: now)) {
    return LatenessTrigger.etaStalled;
  }
  return LatenessTrigger.none;
}

/// Tiny stateful helper the screen owns: remembers when "รอต่ออีก 10 นาที" was last tapped so the
/// card is not re-shown until the snooze window elapses, even if [checkLateness] keeps triggering
/// (AC: "ไม่รบกวนถี่เกินไปในระหว่างนับเวลา"). Not persisted (per-screen-session only, matching the
/// requirement that this needs no RPC/schema).
class LatenessSnooze {
  LatenessSnooze({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  DateTime? _until;

  void snooze([Duration duration = LatenessRules.snooze]) => _until = _clock().add(duration);

  void clear() => _until = null;

  bool get isSnoozed {
    final u = _until;
    if (u == null) return false;
    if (_clock().isAfter(u)) {
      _until = null;
      return false;
    }
    return true;
  }
}
