import '../../../core/geo/geo.dart';
import 'travel_mode.dart';
import 'trip.dart';

/// Pure client-side validation for the create-trip flow. The server re-checks
/// everything (trips_guard); this only gives fast, specific UX feedback.
enum TripFormIssue { originMissing, destMissing, tooClose, departInPast, modeMissing, roleMissing, vehicleMissing }

abstract final class TripRules {
  /// Mirrors app_config `trip.min_distance_m` (server is the authority).
  static const minDistanceM = 200.0;

  /// Mirrors `trip.depart_grace_min`.
  static const departGrace = Duration(minutes: 5);
}

class TripFormValidator {
  const TripFormValidator._();

  /// Step 1: both places chosen and not closer than 200 m in a straight line.
  static TripFormIssue? validatePlaces(Place? origin, Place? dest) {
    if (origin == null) return TripFormIssue.originMissing;
    if (dest == null) return TripFormIssue.destMissing;
    if (haversineM(origin.point, dest.point) < TripRules.minDistanceM) {
      return TripFormIssue.tooClose;
    }
    return null;
  }

  /// Step 2: mode chosen (exactly one) and a departure time that is not in
  /// the past. [departAt] null means "now".
  static TripFormIssue? validateOptions({
    required TravelMode? mode,
    required DateTime? departAt,
    required DateTime now,
    TripRole? role,
    bool hasVehicle = true,
  }) {
    if (mode == null) return TripFormIssue.modeMissing;
    // US-16: a car trip needs an explicit role (no default); a Driver needs a vehicle.
    if (mode == TravelMode.car) {
      if (role == null) return TripFormIssue.roleMissing;
      if (role == TripRole.driver && !hasVehicle) return TripFormIssue.vehicleMissing;
    }
    if (departAt != null && departAt.isBefore(now.subtract(TripRules.departGrace))) {
      return TripFormIssue.departInPast;
    }
    return null;
  }
}

/// "วันนี้ 18:30" / "พรุ่งนี้ 00:30" / "27 ก.ย. 08:00": the day is spelled out
/// whenever it is not today so trips across midnight are unambiguous.
String formatDeparture(DateTime t, DateTime now) {
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'วันนี้ $hm';
  if (diff == 1) return 'พรุ่งนี้ $hm';
  const months = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  return '${t.day} ${months[t.month - 1]} $hm';
}

/// "ประมาณ 8.4 กม. ราว 25 นาที"
String formatRouteSummary(int distanceM, int durationS) {
  final km = distanceM >= 1000 ? '${(distanceM / 1000).toStringAsFixed(1)} กม.' : '$distanceM ม.';
  final min = (durationS / 60).round().clamp(1, 100000);
  return 'ประมาณ $km ราว $min นาที';
}
