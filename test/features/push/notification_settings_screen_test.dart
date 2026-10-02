import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/core/l10n/strings_roles.dart';
import 'package:gowithme/core/providers.dart';
import 'package:gowithme/features/push/domain/push_models.dart';
import 'package:gowithme/features/push/domain/push_repository.dart';
import 'package:gowithme/features/push/presentation/notification_settings_screen.dart';
import 'package:gowithme/features/push/presentation/push_providers.dart';
import 'package:gowithme/features/push/presentation/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeService implements PushService {
  PushPermissionStatus status;
  _FakeService(this.status);

  @override
  DevicePlatform? platform = DevicePlatform.android;

  @override
  Future<PushPermissionStatus> requestPermission() async => status;

  @override
  Future<PushPermissionStatus> currentPermission() async => status;

  @override
  Future<String?> getToken() async => 'tok-x';

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<PushMessage> get onForegroundMessage => const Stream.empty();

  @override
  Stream<PushMessage> get onMessageTap => const Stream.empty();
}

class _FakeRepo implements PushRepository {
  final registered = <String>[];
  final unregistered = <String>[];

  @override
  Future<Result<void>> registerToken(String token, DevicePlatform platform) async {
    registered.add(token);
    return const Ok(null);
  }

  @override
  Future<Result<void>> unregisterToken(String token) async {
    unregistered.add(token);
    return const Ok(null);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required PushPermissionStatus status,
  required _FakeRepo repo,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(sp),
        pushServiceProvider.overrideWithValue(_FakeService(status)),
        pushRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: NotificationSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('OS granted, master on by default: switch is on and enabled', (tester) async {
    final repo = _FakeRepo();
    await _pump(tester, status: PushPermissionStatus.granted, repo: repo, prefs: {
      'push.permission_asked': true,
    });

    expect(find.text(R.notifOsOn), findsOneWidget);
    final sw = tester.widget<SwitchListTile>(find.byKey(const Key('notif-master-toggle')));
    expect(sw.value, isTrue);
    expect(sw.onChanged, isNotNull);
  });

  testWidgets('toggling off unregisters this device\'s token immediately', (tester) async {
    final repo = _FakeRepo();
    await _pump(tester, status: PushPermissionStatus.granted, repo: repo, prefs: {
      'push.permission_asked': true,
      'push.device_token': 'existing-tok',
    });

    await tester.tap(find.byKey(const Key('notif-master-toggle')));
    await tester.pumpAndSettle();

    expect(repo.unregistered, ['existing-tok']);
    expect(find.text(R.notifMasterOff), findsWidgets); // subtitle + snackbar both say it
    final sw = tester.widget<SwitchListTile>(find.byKey(const Key('notif-master-toggle')));
    expect(sw.value, isFalse);
  });

  testWidgets('OS denied: switch is off and disabled, with a link to OS settings', (tester) async {
    final repo = _FakeRepo();
    await _pump(tester, status: PushPermissionStatus.denied, repo: repo, prefs: {
      'push.permission_asked': true,
    });

    expect(find.text(R.notifOsOff), findsOneWidget);
    expect(find.text(R.notifOsOpenSettings), findsOneWidget);
    final sw = tester.widget<SwitchListTile>(find.byKey(const Key('notif-master-toggle')));
    expect(sw.value, isFalse);
    expect(sw.onChanged, isNull);
  });

  testWidgets('lists all 5 event kinds, read-only (Q-G1 single master toggle)', (tester) async {
    final repo = _FakeRepo();
    await _pump(tester, status: PushPermissionStatus.granted, repo: repo, prefs: {
      'push.permission_asked': true,
    });
    for (final t in [
      R.notifEventNewRequest,
      R.notifEventMatchAccepted,
      R.notifEventNewMessage,
      R.notifEventDriverArrived,
      R.notifEventCancelled,
    ]) {
      expect(find.text(t), findsOneWidget);
    }
  });
}
