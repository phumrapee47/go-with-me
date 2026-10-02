import '../../../core/error/result.dart';

/// Server limits (`vehicles` CHECKs and `upsert_my_vehicle`). The server
/// re-validates; these give fast, specific feedback.
abstract final class VehicleLimits {
  static const plateMax = 25;
  static const modelMax = 60;
  static const colorMax = 30;
}

/// The owner's own vehicle (1 per account). [shareConsent] mirrors
/// `share_consent_at IS NOT NULL` (R3-1): false = the plate is never forwarded
/// with a Rider's share/SOS text. Default false.
class Vehicle {
  const Vehicle({
    required this.plate,
    required this.model,
    required this.color,
    this.shareConsent = false,
    this.verified = false,
  });

  final String plate;
  final String model;
  final String color;
  final bool shareConsent;

  /// P1 extension point (`verified_at`); MVP vehicles are always self-declared.
  final bool verified;

  Vehicle copyWith({String? plate, String? model, String? color, bool? shareConsent}) => Vehicle(
        plate: plate ?? this.plate,
        model: model ?? this.model,
        color: color ?? this.color,
        shareConsent: shareConsent ?? this.shareConsent,
        verified: verified,
      );

  static Vehicle? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final plate = j['plate'];
    final model = j['model'];
    final color = j['color'];
    if (plate is! String || model is! String || color is! String) return null;
    return Vehicle(
      plate: plate,
      model: model,
      color: color,
      shareConsent: j['share_consent_at'] != null,
      verified: j['verified_at'] != null,
    );
  }
}

class VehicleInput {
  const VehicleInput({required this.plate, required this.model, required this.color});
  final String plate;
  final String model;
  final String color;
}

enum VehicleField { plate, model, color }

enum VehicleIssue { required, tooLong }

/// Client validation: not empty after trim, within server length limits.
/// Thai plates come in many shapes, so the format itself is not enforced.
class VehicleValidator {
  const VehicleValidator._();

  static String normalise(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');

  static Map<VehicleField, VehicleIssue> validate(VehicleInput i) {
    final out = <VehicleField, VehicleIssue>{};
    void check(VehicleField f, String v, int max) {
      final n = normalise(v);
      if (n.isEmpty) {
        out[f] = VehicleIssue.required;
      } else if (n.length > max || RegExp(r'[\u0000-\u001F\u007F]').hasMatch(v)) {
        out[f] = VehicleIssue.tooLong;
      }
    }

    check(VehicleField.plate, i.plate, VehicleLimits.plateMax);
    check(VehicleField.model, i.model, VehicleLimits.modelMax);
    check(VehicleField.color, i.color, VehicleLimits.colorMax);
    return out;
  }
}

/// What a matched Rider may see (`get_match_vehicle`). [shareAllowed] says
/// whether the Driver lets the plate (only) travel with the Rider's share/SOS.
class VehicleView {
  const VehicleView({
    required this.plate,
    required this.model,
    required this.color,
    this.verified = false,
    this.shareAllowed = false,
  });

  final String plate;
  final String model;
  final String color;
  final bool verified;
  final bool shareAllowed;

  static VehicleView? fromJson(Map<String, dynamic> j) {
    final plate = j['plate'];
    final model = j['model'];
    final color = j['color'];
    if (plate is! String || model is! String || color is! String) return null;
    return VehicleView(
      plate: plate,
      model: model,
      color: color,
      verified: j['verified'] == true,
      shareAllowed: j['share_allowed'] == true,
    );
  }
}

abstract class VehicleRepository {
  /// The caller's vehicle or null (none saved yet).
  Future<Result<Vehicle?>> mine();

  /// `upsert_my_vehicle`; does not touch the share switch.
  Future<Result<void>> save(VehicleInput input);

  /// `set_vehicle_share_consent`: server time, false = off.
  Future<Result<void>> setShareConsent(bool on);

  /// `delete_my_vehicle`: GWM_VEHICLE_IN_USE while a Driver trip is active.
  Future<Result<void>> deleteMine();

  /// `get_match_vehicle`: null when the caller may not see it (no rows).
  Future<Result<VehicleView?>> forMatch(String matchId);
}

/// Only in-app paths may be used as `returnTo` (no scheme/host, no `//`).
String? safeReturnTo(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (!raw.startsWith('/') || raw.startsWith('//') || raw.contains('\\') || raw.contains('://')) return null;
  return raw;
}
