import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/core/providers.dart';
import 'package:gowithme/features/push/domain/push_models.dart';
import 'package:gowithme/features/push/domain/push_repository.dart';
import 'package:gowithme/features/push/presentation/push_providers.dart';
import 'package:gowithme/features/push/presentation/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePushService implements PushService {
  PushPermissionStatus status = PushPermissionStatus.notDetermined;
  String? token = 'tok-1';

  @override
  DevicePlatform? platform = DevicePlatform.android;

  @override
  Future<PushPermissionStatus> requestPermission() async {
    status = PushPermissionStatus.granted;
    return status;
  }

  @override
  Future<PushPermissionStatus> currentPermission() async => status;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<PushMessage> get onForegroundMessage => const Stream.empty();

  @override
  Stream<PushMessage> get onMessageTap => const Stream.empty();
}

class _FakePushRepository implements PushRepository {
  final registered = <String, DevicePlatform>{};
  final unregisterCalls = <String>[];

  @override
  Future<Result<void>> registerToken(String token, DevicePlatform platform) async {
    registered[token] = platform;
    return const Ok(null);
  }

  @override
  Future<Result<void>> unregisterToken(String token) async {
    unregisterCalls.add(token);
    registered.remove(token);
    return const Ok(null);
  }
}

Future<ProviderContainer> _container(_FakePushService service, _FakePushRepository repo) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    pushServiceProvider.overrideWithValue(service),
    pushRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('PushController (R7.3/R7.4, G-1/G-2)', () {
    test('requestPermission(): granted registers a token and turns the master toggle on', () async {
      final service = _FakePushService();
      final repo = _FakePushRepository();
      final c = await _container(service, repo);
      final controller = c.read(pushControllerProvider);

      expect(controller.everAsked, isFalse);
      final status = await controller.requestPermission();

      expect(status, PushPermissionStatus.granted);
      expect(controller.everAsked, isTrue);
      expect(controller.masterEnabled, isTrue);
      expect(repo.registered, {'tok-1': DevicePlatform.android});
    });

    test('markAsked(): "ไว้ทีหลัง" still marks the sheet decided, without registering anything', () async {
      final service = _FakePushService();
      final repo = _FakePushRepository();
      final c = await _container(service, repo);
      final controller = c.read(pushControllerProvider);

      await controller.markAsked();
      expect(controller.everAsked, isTrue);
      expect(repo.registered, isEmpty);
    });

    test('setMasterEnabled(false): unregisters this device\'s token immediately (G-2)', () async {
      final service = _FakePushService();
      final repo = _FakePushRepository();
      final c = await _container(service, repo);
      final controller = c.read(pushControllerProvider);

      await controller.requestPermission(); // registers tok-1
      expect(repo.registered, isNotEmpty);

      await controller.setMasterEnabled(false);
      expect(controller.masterEnabled, isFalse);
      expect(repo.unregisterCalls, ['tok-1']);
      expect(repo.registered, isEmpty);
    });

    test('setMasterEnabled(true) without OS permission does not register (caller must show G-1 again)', () async {
      final service = _FakePushService(); // status stays notDetermined
      final repo = _FakePushRepository();
      final c = await _container(service, repo);
      final controller = c.read(pushControllerProvider);

      await controller.setMasterEnabled(true);
      expect(repo.registered, isEmpty);
    });

    test('unregisterThisDevice() (sign-out/delete-account, Q1): only this device, no-op if never registered', () async {
      final service = _FakePushService();
      final repo = _FakePushRepository();
      final c = await _container(service, repo);
      final controller = c.read(pushControllerProvider);

      // Never registered -> no-op, no repository call at all.
      await controller.unregisterThisDevice();
      expect(repo.unregisterCalls, isEmpty);

      await controller.requestPermission();
      await controller.unregisterThisDevice();
      expect(repo.unregisterCalls, ['tok-1']);
    });

    test('ensureRegisteredIfEnabled(): silently re-registers a returning, already-granted user', () async {
      final service = _FakePushService()..status = PushPermissionStatus.granted;
      final repo = _FakePushRepository();
      final c = await _container(service, repo);
      final controller = c.read(pushControllerProvider);

      expect(controller.masterEnabled, isTrue); // default on (nothing decided yet)
      await controller.ensureRegisteredIfEnabled();
      expect(repo.registered, {'tok-1': DevicePlatform.android});
    });

    test('ensureRegisteredIfEnabled(): does nothing once the master toggle is off', () async {
      final service = _FakePushService()..status = PushPermissionStatus.granted;
      final repo = _FakePushRepository();
      final c = await _container(service, repo);
      final controller = c.read(pushControllerProvider);

      await controller.setMasterEnabled(false);
      await controller.ensureRegisteredIfEnabled();
      expect(repo.registered, isEmpty);
    });

    test('no platform (e.g. unsupported target) never registers, never throws', () async {
      final service = _FakePushService()
        ..status = PushPermissionStatus.granted
        ..platform = null;
      final repo = _FakePushRepository();
      final c = await _container(service, repo);
      final controller = c.read(pushControllerProvider);

      await controller.ensureRegisteredIfEnabled();
      expect(repo.registered, isEmpty);
    });
  });
}
