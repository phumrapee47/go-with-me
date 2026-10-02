import 'package:flutter/foundation.dart' show ValueNotifier;

import '../core/error/app_failure.dart';
import '../core/error/result.dart';
import '../features/matching/domain/match_models.dart';
import '../features/roles/domain/role_state.dart';
import '../features/trip/domain/trip.dart';
import '../features/vehicle/domain/vehicle.dart';
import 'demo_data.dart';
import 'demo_fakes.dart';

const _latency = Duration(milliseconds: 250);
Future<void> _wait() => Future<void>.delayed(_latency);

/// In-memory role state for DEMO_MODE. Enforces the rules the real server enforces so both roles,
/// registration, unregistration and the refusals are visible without Supabase:
/// - switching to Driver needs registration (GWM_NOT_A_DRIVER);
/// - unregistering is refused while a Driver trip is active or a Driver-side match is accepted
///   (GWM_DRIVER_ACTIVE_TRIP / GWM_DRIVER_ACTIVE_MATCH), and allowed afterwards;
/// - register needs the declaration and the current declaration version.
class DemoRoleRepository implements RoleRepository {
  DemoRoleRepository(this._vehicles, this._trips, this._matches) {
    _vehicles.isRegistered = () => registered;
  }

  final DemoVehicleRepository _vehicles;
  final DemoTripRepository _trips;
  final DemoMatchRepository _matches;

  bool registered = true;
  ActiveRole active = ActiveRole.rider;
  DateTime? _at = DateTime(2026, 1, 1);

  /// Hub switches.
  final offline = ValueNotifier<bool>(false);
  final rejectRegistration = ValueNotifier<bool>(false);

  DriverRegistration get state => DriverRegistration(
        registered: registered,
        registeredAt: registered ? _at : null,
        declaredAt: registered ? _at : null,
        declarationVersion: registered ? driverDeclarationVersion : null,
        activeRole: registered ? active : ActiveRole.rider,
        hasVehicle: _vehicles.hasVehicle,
        currentDeclarationVersion: driverDeclarationVersion,
      );

  /// Demo hub: "Rider only" account.
  void asRiderOnly({bool keepVehicle = false}) {
    registered = false;
    active = ActiveRole.rider;
    _at = null;
    if (!keepVehicle) _vehicles.clear();
  }

  /// Demo hub: account with both roles.
  void asTwoRoles({ActiveRole mode = ActiveRole.rider}) {
    registered = true;
    active = mode;
    _at = DateTime.now();
  }

  /// Demo hub: registration lost on "another device" (the app still believes it is a driver).
  void unregisterElsewhere() {
    registered = false;
    active = ActiveRole.rider;
    _at = null;
  }

  void reset(DemoScenario scenario) {
    registered = scenario != DemoScenario.rider;
    active = scenario == DemoScenario.driver ? ActiveRole.driver : ActiveRole.rider;
    _at = registered ? DateTime(2026, 1, 1) : null;
    offline.value = false;
    rejectRegistration.value = false;
  }

  Result<T>? _offline<T>() => offline.value ? Err<T>(const AppFailure(FailureCode.networkOffline, retryable: true)) : null;

  @override
  Future<Result<DriverRegistration>> getMyRoleState() async {
    await _wait();
    return _offline<DriverRegistration>() ?? Ok(state);
  }

  @override
  Future<Result<DriverRegistration>> registerDriver({
    required String plate,
    required String model,
    required String colour,
    required String declarationVersion,
  }) async {
    await _wait();
    final off = _offline<DriverRegistration>();
    if (off != null) return off;
    if (rejectRegistration.value || declarationVersion != driverDeclarationVersion) {
      return const Err(AppFailure('GWM_DECLARATION_VERSION_STALE'));
    }
    final check = VehicleValidator.validate(VehicleInput(plate: plate, model: model, color: colour));
    if (check.isNotEmpty) return const Err(AppFailure('GWM_VEHICLE_INVALID'));
    await _vehicles.save(VehicleInput(plate: plate, model: model, color: colour));
    if (!registered) {
      registered = true;
      _at = DateTime.now();
    }
    return Ok(state);
  }

  @override
  Future<Result<DriverRegistration>> unregisterDriver() async {
    await _wait();
    final off = _offline<DriverRegistration>();
    if (off != null) return off;
    if (registered) {
      final t = _trips.active;
      if (t != null && t.role == TripRole.driver && t.status.isActive) {
        return const Err(AppFailure('GWM_DRIVER_ACTIVE_TRIP'));
      }
      final m = _matches.acceptedCar;
      if (m != null && m.iAmDriver && m.status == MatchStatus.accepted) {
        return const Err(AppFailure('GWM_DRIVER_ACTIVE_MATCH'));
      }
    }
    registered = false;
    active = ActiveRole.rider;
    _at = null; // the vehicle is kept (owner only), like the server
    return Ok(state);
  }

  @override
  Future<Result<DriverRegistration>> setActiveRole(ActiveRole role) async {
    await _wait();
    final off = _offline<DriverRegistration>();
    if (off != null) return off;
    if (role == ActiveRole.driver && !registered) return const Err(AppFailure('GWM_NOT_A_DRIVER'));
    active = role;
    return Ok(state);
  }
}
