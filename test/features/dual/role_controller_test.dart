import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/providers.dart';
import 'package:gowithme/features/auth/presentation/auth_providers.dart';
import 'package:gowithme/features/roles/domain/role_state.dart';
import 'package:gowithme/features/roles/presentation/role_providers.dart';
import 'package:gowithme/features/vehicle/presentation/vehicle_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repos.dart';
import '../../support/fake_repos_roles.dart';
import '../../support/p4_helpers.dart';

Future<(ProviderContainer, FakeRoleRepository, SharedPreferences)> _make({
  FakeRoleRepository? repo,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final r = repo ?? FakeRoleRepository(registered: false);
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(sp),
    authUserProvider.overrideWith((ref) => Stream.value(testUser)),
    roleRepositoryProvider.overrideWithValue(r),
    vehicleRepositoryProvider.overrideWithValue(FakeVehicleRepository()),
  ]);
  addTearDown(c.dispose);
  await c.read(authUserProvider.future);
  return (c, r, sp);
}

/// Builds the controller (if nobody read it yet) and lets its first server refresh finish.
Future<void> _settle(ProviderContainer c) async {
  c.read(roleControllerProvider);
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  test('first read comes from the local cache (no tone flicker), the server then confirms', () async {
    final (c, _, _) = await _make(
      repo: FakeRoleRepository(registered: true, active: ActiveRole.driver),
      prefs: {'gwm.activeRole.u1': 'driver'},
    );
    final ctrl = c.read(roleControllerProvider);
    expect(ctrl.active, ActiveRole.driver, reason: 'cached value is available synchronously');
    expect(ctrl.registration, isNull, reason: 'server not asked yet');
    await _settle(c);
    expect(c.read(roleControllerProvider).registration!.registered, isTrue);
    expect(c.read(roleControllerProvider).active, ActiveRole.driver);
    expect(c.read(roleControllerProvider).notice, isNull);
  });

  test('nothing cached: the mode is unknown (neutral skeleton), never guessed', () async {
    final (c, _, _) = await _make(repo: FakeRoleRepository(registered: true));
    expect(c.read(roleControllerProvider).active, isNull);
    expect(c.read(appToneProvider).name, 'rider');
    await _settle(c);
    expect(c.read(roleControllerProvider).active, ActiveRole.rider);
  });

  test('cached Driver but the account is no longer registered: falls back to Rider once and says so', () async {
    final (c, _, sp) = await _make(prefs: {'gwm.activeRole.u1': 'driver'});
    expect(c.read(roleControllerProvider).active, ActiveRole.driver);
    await _settle(c);
    final s = c.read(roleControllerProvider);
    expect(s.active, ActiveRole.rider);
    expect(s.notice, RoleNotice.reconciledToRider);
    expect(sp.getString('gwm.activeRole.u1'), 'rider', reason: 'cache corrected');
    expect(c.read(roleControllerProvider.notifier).consumeNotice(), RoleNotice.reconciledToRider);
    expect(c.read(roleControllerProvider).notice, isNull, reason: 'told only once');
  });

  test('switch to Driver: waits for the server, then tone + cache change', () async {
    final (c, repo, sp) = await _make(repo: FakeRoleRepository(registered: true));
    await _settle(c);
    final ctrl = c.read(roleControllerProvider.notifier);
    final f = ctrl.switchTo(ActiveRole.driver);
    expect(c.read(roleControllerProvider).switching.isSwitching, isTrue);
    expect(c.read(roleControllerProvider).active, ActiveRole.rider, reason: 'tone does not change before the server confirms');
    expect(await f, RoleSwitchOutcome.switched);
    expect(c.read(roleControllerProvider).active, ActiveRole.driver);
    expect(c.read(roleControllerProvider).switching.isSwitching, isFalse);
    expect(sp.getString('gwm.activeRole.u1'), 'driver');
    expect(repo.switchCalls, [ActiveRole.driver]);
  });

  test('a second tap while switching is ignored', () async {
    final (c, repo, _) = await _make(repo: FakeRoleRepository(registered: true));
    await _settle(c);
    final ctrl = c.read(roleControllerProvider.notifier);
    final a = ctrl.switchTo(ActiveRole.driver);
    final b = await ctrl.switchTo(ActiveRole.driver);
    expect(b, RoleSwitchOutcome.unchanged);
    await a;
    expect(repo.switchCalls.length, 1);
  });

  test('switch to Driver offline: reported at once, role and tone unchanged', () async {
    final repo = FakeRoleRepository(registered: true);
    final (c, _, sp) = await _make(repo: repo);
    await _settle(c);
    repo.failNextSwitch = const AppFailure(FailureCode.networkOffline, retryable: true);
    final out = await c.read(roleControllerProvider.notifier).switchTo(ActiveRole.driver);
    expect(out, RoleSwitchOutcome.offlineToDriver);
    expect(c.read(roleControllerProvider).active, ActiveRole.rider);
    expect(c.read(roleControllerProvider).switching.failure, RoleSwitchFailure.offline);
    expect(sp.getString('gwm.activeRole.u1'), 'rider');
    c.read(roleControllerProvider.notifier).dismissSwitchFailure();
    expect(c.read(roleControllerProvider).switching.phase, RoleSwitchPhase.idle);
  });

  test('switch to Driver without registration is refused locally; a server refusal fixes the local view', () async {
    final (c, repo, _) = await _make();
    await _settle(c);
    final ctrl = c.read(roleControllerProvider.notifier);
    expect(await ctrl.switchTo(ActiveRole.driver), RoleSwitchOutcome.notRegistered);
    expect(repo.switchCalls, isEmpty, reason: 'no round trip for a known-unregistered account');

    // Registered here, but unregistered on another device: the server says NOT_A_DRIVER.
    repo.registered = true;
    await ctrl.refresh();
    repo.registered = false;
    expect(await ctrl.switchTo(ActiveRole.driver), RoleSwitchOutcome.notRegistered);
    expect(c.read(roleControllerProvider).registered, isFalse);
    expect(c.read(roleControllerProvider).active, ActiveRole.rider);
  });

  test('switch to Rider always works: at once, and synced later when offline (F-D1.7, Q-D5)', () async {
    final repo = FakeRoleRepository(registered: true, active: ActiveRole.driver);
    final (c, _, sp) = await _make(repo: repo, prefs: {'gwm.activeRole.u1': 'driver'});
    await _settle(c);
    final ctrl = c.read(roleControllerProvider.notifier);
    repo.failAll = const AppFailure(FailureCode.networkOffline, retryable: true);
    expect(await ctrl.switchTo(ActiveRole.rider), RoleSwitchOutcome.switchedSavedLater);
    expect(c.read(roleControllerProvider).active, ActiveRole.rider, reason: 'tone changes immediately');
    expect(c.read(roleControllerProvider).pendingRiderSync, isTrue);
    expect(sp.getBool('gwm.roleSync.u1'), isTrue, reason: 'survives an app restart');

    // Refresh while still offline keeps showing Rider.
    await ctrl.refresh();
    expect(c.read(roleControllerProvider).active, ActiveRole.rider);

    // Back online: the pending switch is pushed first, then the server state is read.
    repo.failAll = null;
    await ctrl.refresh();
    expect(repo.active, ActiveRole.rider);
    expect(c.read(roleControllerProvider).pendingRiderSync, isFalse);
    expect(sp.getBool('gwm.roleSync.u1'), isNull);
    expect(c.read(roleControllerProvider).active, ActiveRole.rider);
  });

  test('registering does not switch the mode (US-19 AC7)', () async {
    final (c, repo, _) = await _make();
    await _settle(c);
    final ctrl = c.read(roleControllerProvider.notifier);
    final res = await ctrl.register(const DriverRegistrationInput(
      plate: '  1กก   1234 ',
      model: 'Yaris',
      colour: 'ขาว',
      declared: true,
    ));
    expect(res.failureOrNull, isNull);
    expect(c.read(roleControllerProvider).registered, isTrue);
    expect(c.read(roleControllerProvider).active, ActiveRole.rider);
    expect(repo.registerCalls.single['plate'], '1กก 1234', reason: 'whitespace normalised like the server');
    expect(repo.registerCalls.single['version'], driverDeclarationVersion);
  });

  test('a rejected registration changes nothing', () async {
    final (c, repo, _) = await _make();
    await _settle(c);
    repo.failNextRegister = const AppFailure('GWM_DECLARATION_VERSION_STALE');
    final res = await c.read(roleControllerProvider.notifier).register(const DriverRegistrationInput(
      plate: 'a',
      model: 'b',
      colour: 'c',
      declared: true,
    ));
    expect(res.failureOrNull!.code, 'GWM_DECLARATION_VERSION_STALE');
    expect(c.read(roleControllerProvider).registered, isFalse);
  });

  test('unregister returns to Rider; a blocked unregister keeps everything', () async {
    final repo = FakeRoleRepository(registered: true, active: ActiveRole.driver);
    final (c, _, sp) = await _make(repo: repo, prefs: {'gwm.activeRole.u1': 'driver'});
    await _settle(c);
    final ctrl = c.read(roleControllerProvider.notifier);
    repo.failNextUnregister = const AppFailure('GWM_DRIVER_ACTIVE_TRIP');
    final blocked = await ctrl.unregister();
    expect(unregisterBlockOf(blocked.failureOrNull!), UnregisterBlock.activeTrip);
    expect(c.read(roleControllerProvider).registered, isTrue);
    expect(c.read(roleControllerProvider).active, ActiveRole.driver);

    expect((await ctrl.unregister()).failureOrNull, isNull);
    expect(c.read(roleControllerProvider).registered, isFalse);
    expect(c.read(roleControllerProvider).active, ActiveRole.rider);
    expect(sp.getString('gwm.activeRole.u1'), 'rider');
  });

  test('a failed state load leaves the cached mode alone and flags the failure', () async {
    final repo = FakeRoleRepository(registered: true, active: ActiveRole.driver)
      ..failAll = const AppFailure(FailureCode.networkOffline, retryable: true);
    final (c, _, _) = await _make(repo: repo, prefs: {'gwm.activeRole.u1': 'driver'});
    await _settle(c);
    final s = c.read(roleControllerProvider);
    expect(s.loadFailed, isTrue);
    expect(s.active, ActiveRole.driver);
    expect(s.registration, isNull);
  });
}
