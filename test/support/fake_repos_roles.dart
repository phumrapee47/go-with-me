import 'dart:async';

import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/features/roles/domain/role_state.dart';

/// Scriptable role repository. Defaults to an account that is registered and in Rider mode.
class FakeRoleRepository implements RoleRepository {
  FakeRoleRepository({this.registered = true, ActiveRole active = ActiveRole.rider})
      : active = registered ? active : ActiveRole.rider;

  bool registered;
  ActiveRole active;
  bool hasVehicle = false;

  /// When set, every call fails with it (until cleared).
  AppFailure? failAll;

  /// Failure for exactly the next register / unregister / switch call.
  AppFailure? failNextRegister;
  AppFailure? failNextUnregister;
  AppFailure? failNextSwitch;

  /// When set, register waits for it (lets a test look at the "waiting" state).
  Completer<void>? registerGate;

  /// Runs on a successful registration (e.g. to create the vehicle in the vehicle fake).
  void Function()? onRegister;

  int getCalls = 0;
  final switchCalls = <ActiveRole>[];
  final registerCalls = <Map<String, String>>[];
  int unregisterCalls = 0;

  DriverRegistration get state => DriverRegistration(
        registered: registered,
        registeredAt: registered ? DateTime(2026, 1, 1) : null,
        declaredAt: registered ? DateTime(2026, 1, 1) : null,
        declarationVersion: registered ? driverDeclarationVersion : null,
        activeRole: active,
        hasVehicle: hasVehicle,
        currentDeclarationVersion: driverDeclarationVersion,
      );

  @override
  Future<Result<DriverRegistration>> getMyRoleState() async {
    getCalls++;
    if (failAll != null) return Err(failAll!);
    return Ok(state);
  }

  @override
  Future<Result<DriverRegistration>> registerDriver({
    required String plate,
    required String model,
    required String colour,
    required String declarationVersion,
  }) async {
    registerCalls.add({'plate': plate, 'model': model, 'colour': colour, 'version': declarationVersion});
    if (registerGate != null) await registerGate!.future;
    if (failAll != null) return Err(failAll!);
    if (failNextRegister != null) {
      final f = failNextRegister!;
      failNextRegister = null;
      return Err(f);
    }
    registered = true;
    hasVehicle = true;
    onRegister?.call();
    return Ok(state);
  }

  @override
  Future<Result<DriverRegistration>> unregisterDriver() async {
    unregisterCalls++;
    if (failAll != null) return Err(failAll!);
    if (failNextUnregister != null) {
      final f = failNextUnregister!;
      failNextUnregister = null;
      return Err(f);
    }
    registered = false;
    active = ActiveRole.rider;
    return Ok(state);
  }

  @override
  Future<Result<DriverRegistration>> setActiveRole(ActiveRole role) async {
    switchCalls.add(role);
    if (failAll != null) return Err(failAll!);
    if (failNextSwitch != null) {
      final f = failNextSwitch!;
      failNextSwitch = null;
      return Err(f);
    }
    if (role == ActiveRole.driver && !registered) return const Err(AppFailure('GWM_NOT_A_DRIVER'));
    active = role;
    return Ok(state);
  }
}
