import 'package:latlong2/latlong.dart';

import '../../../core/error/result.dart';

enum LocationPermissionState { granted, denied, deniedForever, serviceOff }

/// A position sample. [at] is when the OS measured it (used to drop stale fixes).
class LocationFix {
  const LocationFix({required this.point, required this.at, this.accuracyM});
  final LatLng point;
  final DateTime at;
  final double? accuracyM;
}

/// Foreground location (while-in-use only; no background tracking).
abstract class LocationService {
  Future<LocationPermissionState> permission();

  /// Triggers the OS prompt. Callers must show the consent rationale first.
  Future<LocationPermissionState> request();

  Future<Result<LatLng>> currentPosition();

  /// Continuous fixes for an active trip. The caller cancels the subscription
  /// when the trip ends or the app leaves the foreground.
  Stream<LocationFix> watch();
}
