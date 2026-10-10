import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/push/domain/push_models.dart';
import 'package:gowithme/features/push/presentation/push_service.dart';

void main() {
  group('FirebasePushService (no Firebase config in this environment)', () {
    // Round 7 stage A ships with no `firebase_options.dart`/native config
    // (no real Firebase project yet). Every call must fail soft: no
    // exception ever reaches the caller, and every value is a safe neutral
    // one the UI already treats as "not available" (never an error state).
    test('requestPermission() fails soft to unsupported', () async {
      final s = FirebasePushService();
      expect(await s.requestPermission(), PushPermissionStatus.unsupported);
    });

    test('currentPermission() fails soft to unsupported', () async {
      final s = FirebasePushService();
      expect(await s.currentPermission(), PushPermissionStatus.unsupported);
    });

    test('initialTap() (cold-start tap, US-42 AC7) fails soft to null', () async {
      final s = FirebasePushService();
      expect(s, isA<InitialTapSource>());
      expect(await s.initialTap(), isNull);
    });

    test('getToken() fails soft to null', () async {
      final s = FirebasePushService();
      expect(await s.getToken(), isNull);
    });

    test('repeated calls stay guarded (init is attempted only once)', () async {
      final s = FirebasePushService();
      expect(await s.getToken(), isNull);
      expect(await s.requestPermission(), PushPermissionStatus.unsupported);
      expect(await s.currentPermission(), PushPermissionStatus.unsupported);
    });

    test('foreground/tap streams stay open and empty (never crash on listen)', () async {
      final s = FirebasePushService();
      final events = <Object?>[];
      final subs = [
        s.onForegroundMessage.listen(events.add),
        s.onMessageTap.listen(events.add),
        s.onTokenRefresh.listen(events.add),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events, isEmpty);
      for (final sub in subs) {
        await sub.cancel();
      }
    });
  });

  group('NoopPushService (DEMO_MODE)', () {
    const s = NoopPushService();

    test('never touches any plugin, always neutral', () async {
      expect(await s.requestPermission(), PushPermissionStatus.unsupported);
      expect(await s.currentPermission(), PushPermissionStatus.unsupported);
      expect(await s.getToken(), isNull);
    });

    test('streams are empty', () async {
      expect(await s.onForegroundMessage.isEmpty, isTrue);
      expect(await s.onMessageTap.isEmpty, isTrue);
      expect(await s.onTokenRefresh.isEmpty, isTrue);
    });
  });

  test('currentDevicePlatform() is android or web this round (Q3: no iOS yet in tests)', () {
    final p = currentDevicePlatform();
    expect(p, isNotNull);
    expect(p == DevicePlatform.android || p == DevicePlatform.web, isTrue);
  });
}
