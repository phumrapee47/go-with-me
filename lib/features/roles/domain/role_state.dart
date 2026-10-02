import '../../../core/error/result.dart';
import '../../../core/theme/tone.dart';
import '../../trip/domain/trip.dart' show TripRole;
import '../../vehicle/domain/vehicle.dart';

/// Text version of the licence self-declaration shown in the app (l10n `driverreg.decl`).
/// It must equal the server config `driver.declaration_version` (`register_driver` rejects any
/// other value with GWM_DECLARATION_VERSION_STALE). Legal review may bump both together.
const driverDeclarationVersion = 'd1-draft';

/// The mode the user works in (US-20). Drives the app tone and the default role of a
/// new car trip ONLY: it never grants or removes a permission (the server decides
/// from "registered?" and the trip's own role).
enum ActiveRole {
  rider('rider'),
  driver('driver');

  const ActiveRole(this.db);
  final String db;

  TripRole get tripRole => this == driver ? TripRole.driver : TripRole.rider;
  AppTone get tone => this == driver ? AppTone.driver : AppTone.rider;

  static ActiveRole? fromDb(Object? v) {
    for (final r in values) {
      if (r.db == v) return r;
    }
    return null;
  }
}

/// Own registration state = `get_my_role_state()` (owner only; other users can never read it).
class DriverRegistration {
  const DriverRegistration({
    this.registered = false,
    this.registeredAt,
    this.declaredAt,
    this.declarationVersion,
    this.activeRole = ActiveRole.rider,
    this.hasVehicle = false,
    this.currentDeclarationVersion,
  });

  final bool registered;
  final DateTime? registeredAt;
  final DateTime? declaredAt;
  final String? declarationVersion;
  final ActiveRole activeRole;

  /// A vehicle row exists (also after unregistering: kept, owner-only).
  final bool hasVehicle;

  /// Server's current declaration text version.
  final String? currentDeclarationVersion;

  static const rider = DriverRegistration();

  /// Defensive parse: a state that claims Driver mode without registration is read as Rider
  /// (the DB CHECK forbids it; this only guards against a stale/odd payload).
  static DriverRegistration? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final registered = j['driver_registered'] == true;
    var role = ActiveRole.fromDb(j['active_role']) ?? ActiveRole.rider;
    if (role == ActiveRole.driver && !registered) role = ActiveRole.rider;
    DateTime? ts(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return DriverRegistration(
      registered: registered,
      registeredAt: ts(j['driver_registered_at']),
      declaredAt: ts(j['licence_declared_at']),
      declarationVersion: j['licence_declaration_version'] as String?,
      activeRole: role,
      hasVehicle: j['has_vehicle'] == true,
      currentDeclarationVersion: j['current_declaration_version'] as String?,
    );
  }

  DriverRegistration copyWith({bool? registered, ActiveRole? activeRole, bool? hasVehicle}) => DriverRegistration(
        registered: registered ?? this.registered,
        registeredAt: registeredAt,
        declaredAt: declaredAt,
        declarationVersion: declarationVersion,
        activeRole: activeRole ?? this.activeRole,
        hasVehicle: hasVehicle ?? this.hasVehicle,
        currentDeclarationVersion: currentDeclarationVersion,
      );
}

abstract class RoleRepository {
  /// `get_my_role_state`.
  Future<Result<DriverRegistration>> getMyRoleState();

  /// `register_driver(plate, model, colour, declaration_version)`: vehicle + declaration in one transaction.
  Future<Result<DriverRegistration>> registerDriver({
    required String plate,
    required String model,
    required String colour,
    required String declarationVersion,
  });

  /// `unregister_driver`: GWM_DRIVER_ACTIVE_TRIP / GWM_DRIVER_ACTIVE_MATCH when blocked.
  Future<Result<DriverRegistration>> unregisterDriver();

  /// `set_active_role`: GWM_NOT_A_DRIVER when switching to driver without registering.
  Future<Result<DriverRegistration>> setActiveRole(ActiveRole role);
}

// ---------------------------------------------------------------------------------------------
// Registration form validation

class DriverRegistrationInput {
  const DriverRegistrationInput({
    required this.plate,
    required this.model,
    required this.colour,
    required this.declared,
  });
  final String plate;
  final String model;
  final String colour;

  /// The self-declaration checkbox. Never pre-ticked.
  final bool declared;
}

class DriverRegistrationCheck {
  const DriverRegistrationCheck(this.fields, this.declarationMissing);
  final Map<VehicleField, VehicleIssue> fields;
  final bool declarationMissing;
  bool get isValid => fields.isEmpty && !declarationMissing;
}

abstract final class DriverRegistrationValidator {
  /// Vehicle rules are the existing [VehicleValidator] (same limits as the server's
  /// `upsert_my_vehicle`) plus the mandatory declaration tick.
  static DriverRegistrationCheck validate(DriverRegistrationInput i) => DriverRegistrationCheck(
        VehicleValidator.validate(VehicleInput(plate: i.plate, model: i.model, color: i.colour)),
        !i.declared,
      );
}

// ---------------------------------------------------------------------------------------------
// Default role for a new car trip

/// Initial role of the create-trip form (US-20 / US-5): follows the active role, but only
/// while the user has not chosen one themselves ([roleTouched]) and never Driver for an
/// unregistered account. [current] is what the form holds now.
TripRole resolveTripRole({
  required ActiveRole? activeRole,
  required bool registered,
  required bool roleTouched,
  TripRole? current,
}) {
  if (roleTouched && current != null) {
    // An explicit Driver choice cannot survive losing the registration.
    return current == TripRole.driver && !registered ? TripRole.rider : current;
  }
  return activeRole == ActiveRole.driver && registered ? TripRole.driver : TripRole.rider;
}

// ---------------------------------------------------------------------------------------------
// Switch state machine

enum RoleSwitchPhase { idle, switching, failed }

enum RoleSwitchFailure { offline, notRegistered, generic }

class RoleSwitchState {
  const RoleSwitchState._(this.phase, {this.target, this.failure});
  static const idle = RoleSwitchState._(RoleSwitchPhase.idle);
  final RoleSwitchPhase phase;
  final ActiveRole? target;
  final RoleSwitchFailure? failure;

  bool get isSwitching => phase == RoleSwitchPhase.switching;

  /// idle/failed -> switching. A second request while switching is ignored (returns this).
  RoleSwitchState start(ActiveRole to) => isSwitching ? this : RoleSwitchState._(RoleSwitchPhase.switching, target: to);

  /// switching -> idle (server confirmed).
  RoleSwitchState succeed() => isSwitching ? idle : this;

  /// switching -> failed (role/tone unchanged).
  RoleSwitchState fail(RoleSwitchFailure why) =>
      isSwitching ? RoleSwitchState._(RoleSwitchPhase.failed, target: target, failure: why) : this;

  /// failed -> idle (message shown).
  RoleSwitchState dismiss() => phase == RoleSwitchPhase.failed ? idle : this;
}

// ---------------------------------------------------------------------------------------------
// Reconcile (F-D8): the server is the source of truth, the local cache only avoids tone flicker.

class RoleReconcile {
  const RoleReconcile(this.role, {this.forcedToRider = false});
  final ActiveRole role;

  /// The device believed Driver mode but the account is no longer registered: the user is told once.
  final bool forcedToRider;
}

RoleReconcile reconcileRole({ActiveRole? cached, required DriverRegistration server}) {
  final forced = cached == ActiveRole.driver && !server.registered;
  return RoleReconcile(forced ? ActiveRole.rider : server.activeRole, forcedToRider: forced);
}

/// Blocked reasons of `unregister_driver` (design-spec D-11).
enum UnregisterBlock { activeTrip, activeMatch, both }
