import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/error/app_failure.dart';
import '../../../core/error/result.dart';
import '../../../core/logging/log.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tone.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../vehicle/domain/vehicle.dart' show VehicleValidator;
import '../../vehicle/presentation/vehicle_providers.dart';
import '../data/supabase_role_repository.dart';
import '../domain/role_state.dart';

final roleRepositoryProvider = Provider<RoleRepository>(
  (ref) => SupabaseRoleRepository(() => Supabase.instance.client),
);

/// One-shot notices raised by the controller and shown once by the shell (polite live region).
enum RoleNotice { reconciledToRider }

enum RoleSwitchOutcome { unchanged, switched, switchedSavedLater, offlineToDriver, notRegistered, failed }

class RoleUiState {
  const RoleUiState({
    this.active,
    this.registration,
    this.loadFailed = false,
    this.switching = RoleSwitchState.idle,
    this.pendingRiderSync = false,
    this.notice,
  });

  /// Effective mode. Comes from the local cache until the server answered; null = not known yet
  /// (first run on this device): the UI shows a neutral skeleton and the neutral (Rider-light) tone.
  final ActiveRole? active;

  /// Last server-confirmed state (null = not fetched yet).
  final DriverRegistration? registration;
  final bool loadFailed;
  final RoleSwitchState switching;

  /// A switch to Rider was made offline and still has to reach the server (F-D1 step 7).
  final bool pendingRiderSync;
  final RoleNotice? notice;

  bool? get registered => registration?.registered;

  RoleUiState copyWith({
    Object? active = _keep,
    Object? registration = _keep,
    bool? loadFailed,
    RoleSwitchState? switching,
    bool? pendingRiderSync,
    Object? notice = _keep,
  }) =>
      RoleUiState(
        active: identical(active, _keep) ? this.active : active as ActiveRole?,
        registration: identical(registration, _keep) ? this.registration : registration as DriverRegistration?,
        loadFailed: loadFailed ?? this.loadFailed,
        switching: switching ?? this.switching,
        pendingRiderSync: pendingRiderSync ?? this.pendingRiderSync,
        notice: identical(notice, _keep) ? this.notice : notice as RoleNotice?,
      );
}

const Object _keep = Object();

bool _isOffline(AppFailure f) =>
    f.code == FailureCode.networkOffline || f.code == FailureCode.networkTimeout || f.code == FailureCode.serverUnavailable;

/// Active role + registration for the signed-in user. The server is the source of truth; the
/// last known active role is cached per account in SharedPreferences (no PII) so the first frame
/// already has the right tone.
class RoleController extends Notifier<RoleUiState> {
  String? _uid;

  static String cacheKey(String uid) => 'gwm.activeRole.$uid';
  static String pendingKey(String uid) => 'gwm.roleSync.$uid';

  @override
  RoleUiState build() {
    final user = ref.watch(authUserProvider.select((a) => a.valueOrNull));
    _uid = (user != null && user.emailConfirmed) ? user.id : null;
    final uid = _uid;
    if (uid == null) return const RoleUiState();
    final prefs = ref.read(sharedPrefsProvider);
    final cached = ActiveRole.fromDb(prefs.getString(cacheKey(uid)));
    final pending = prefs.getBool(pendingKey(uid)) ?? false;
    Future.microtask(() {
      if (ref.exists(roleControllerProvider)) refresh();
    });
    return RoleUiState(active: pending ? ActiveRole.rider : cached, pendingRiderSync: pending);
  }

  void _persist(ActiveRole? role, {bool? pending}) {
    final uid = _uid;
    if (uid == null) return;
    final prefs = ref.read(sharedPrefsProvider);
    if (role != null) prefs.setString(cacheKey(uid), role.db);
    if (pending != null) {
      pending ? prefs.setBool(pendingKey(uid), true) : prefs.remove(pendingKey(uid));
    }
  }

  /// Reads the server state (app start, resume, pull to refresh). Pushes a pending offline
  /// "switch to Rider" first; the server's answer then wins (last write, Q-D5).
  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null || state.switching.isSwitching) return;
    final repo = ref.read(roleRepositoryProvider);
    var pending = state.pendingRiderSync;
    if (pending) {
      final pushed = await repo.setActiveRole(ActiveRole.rider);
      if (_uid != uid) return;
      if (pushed.failureOrNull == null) {
        pending = false;
        _persist(null, pending: false);
      } else if (pushed.failureOrNull?.code == 'GWM_INVALID_ROLE') {
        pending = false;
        _persist(null, pending: false);
      }
    }
    final res = await repo.getMyRoleState();
    if (_uid != uid || state.switching.isSwitching) return;
    res.when(
      ok: (server) {
        final r = reconcileRole(cached: pending ? ActiveRole.rider : state.active, server: server);
        // Still waiting to tell the server about a Rider switch: keep showing Rider.
        final effective = pending ? ActiveRole.rider : r.role;
        _persist(effective, pending: pending);
        state = state.copyWith(
          active: effective,
          registration: server,
          loadFailed: false,
          pendingRiderSync: pending,
          notice: r.forcedToRider && !pending ? RoleNotice.reconciledToRider : state.notice,
        );
      },
      err: (f) {
        Log.d('role state load failed: ${f.code}');
        state = state.copyWith(loadFailed: true, pendingRiderSync: pending);
      },
    );
  }

  RoleNotice? consumeNotice() {
    final n = state.notice;
    if (n != null) state = state.copyWith(notice: null);
    return n;
  }

  /// 1-tap switch (US-20). Driver needs the server first (tone does not change until it confirmed);
  /// Rider is applied at once and synced later if the network is down.
  Future<RoleSwitchOutcome> switchTo(ActiveRole role) async {
    final uid = _uid;
    if (uid == null || state.switching.isSwitching) return RoleSwitchOutcome.unchanged;
    if (role == state.active) return RoleSwitchOutcome.unchanged;
    final repo = ref.read(roleRepositoryProvider);

    if (role == ActiveRole.rider) {
      state = state.copyWith(active: ActiveRole.rider);
      _persist(ActiveRole.rider);
      final res = await repo.setActiveRole(ActiveRole.rider);
      if (_uid != uid) return RoleSwitchOutcome.switched;
      final f = res.failureOrNull;
      if (f == null) {
        state = state.copyWith(registration: res.valueOrNull, pendingRiderSync: false);
        _persist(null, pending: false);
        return RoleSwitchOutcome.switched;
      }
      state = state.copyWith(pendingRiderSync: true);
      _persist(null, pending: true);
      return RoleSwitchOutcome.switchedSavedLater;
    }

    if (state.registered == false) return RoleSwitchOutcome.notRegistered;
    state = state.copyWith(switching: state.switching.start(role));
    final res = await repo.setActiveRole(role);
    if (_uid != uid) return RoleSwitchOutcome.failed;
    final f = res.failureOrNull;
    if (f == null) {
      final server = res.valueOrNull!;
      state = state.copyWith(active: server.activeRole, registration: server, switching: state.switching.succeed());
      _persist(server.activeRole, pending: false);
      return RoleSwitchOutcome.switched;
    }
    if (f.code == 'GWM_NOT_A_DRIVER') {
      // The server says we are not registered (e.g. unregistered on another device): fix the local view.
      state = state.copyWith(
        registration: (state.registration ?? DriverRegistration.rider).copyWith(registered: false, activeRole: ActiveRole.rider),
        active: ActiveRole.rider,
        switching: state.switching.fail(RoleSwitchFailure.notRegistered),
      );
      _persist(ActiveRole.rider);
      return RoleSwitchOutcome.notRegistered;
    }
    final offline = _isOffline(f);
    state = state.copyWith(switching: state.switching.fail(offline ? RoleSwitchFailure.offline : RoleSwitchFailure.generic));
    return offline ? RoleSwitchOutcome.offlineToDriver : RoleSwitchOutcome.failed;
  }

  void dismissSwitchFailure() => state = state.copyWith(switching: state.switching.dismiss());

  /// Atomic registration (vehicle + declaration). Does NOT switch the mode (US-19 AC7).
  Future<Result<DriverRegistration>> register(DriverRegistrationInput i) async {
    final res = await ref.read(roleRepositoryProvider).registerDriver(
          plate: VehicleValidator.normalise(i.plate),
          model: VehicleValidator.normalise(i.model),
          colour: VehicleValidator.normalise(i.colour),
          declarationVersion: driverDeclarationVersion,
        );
    final reg = res.valueOrNull;
    if (reg != null) {
      // Registration never changes the active role (it stays what it was).
      state = state.copyWith(registration: reg, active: state.active ?? ActiveRole.rider);
      _persist(state.active);
      ref.invalidate(myVehicleProvider);
    }
    return res;
  }

  Future<Result<DriverRegistration>> unregister() async {
    final res = await ref.read(roleRepositoryProvider).unregisterDriver();
    final reg = res.valueOrNull;
    if (reg != null) {
      state = state.copyWith(registration: reg, active: ActiveRole.rider, pendingRiderSync: false);
      _persist(ActiveRole.rider, pending: false);
      ref.invalidate(myVehicleProvider);
    }
    return res;
  }
}

final roleControllerProvider = NotifierProvider<RoleController, RoleUiState>(RoleController.new);

/// Effective active role (null = not known yet).
final activeRoleProvider = Provider<ActiveRole?>((ref) => ref.watch(roleControllerProvider.select((s) => s.active)));

/// null = unknown (not fetched yet).
final driverRegisteredProvider = Provider<bool?>((ref) => ref.watch(roleControllerProvider.select((s) => s.registered)));

/// Tone of app-level screens (follows the active role; neutral Rider tone while unknown / signed out).
final appToneProvider = Provider<AppTone>(
  (ref) => ref.watch(activeRoleProvider) == ActiveRole.driver ? AppTone.driver : AppTone.rider,
);

/// Maps an `unregister_driver` failure to the reasons sheet (null = not a "blocked" failure).
UnregisterBlock? unregisterBlockOf(AppFailure f) => switch (f.code) {
      'GWM_DRIVER_ACTIVE_TRIP' => UnregisterBlock.activeTrip,
      'GWM_DRIVER_ACTIVE_MATCH' => UnregisterBlock.activeMatch,
      'GWM_DRIVER_UNREG_BLOCKED' => UnregisterBlock.activeTrip,
      _ => null,
    };
