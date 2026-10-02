import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/features/auth/domain/auth_repository.dart';
import 'package:gowithme/features/push/domain/push_models.dart';
import 'package:gowithme/features/push/domain/push_repository.dart';
import 'package:gowithme/features/push/presentation/push_providers.dart';

import '../../support/fakes.dart';

const _confirmed = AuthUser(id: 'u1', email: 'a@b.co', displayName: 'มิ้นท์', emailConfirmed: true);

/// Only records what the app asked it to unregister — proves R7.4/Q1: sign-out
/// removes exactly this device's token, nothing else.
class _RecordingPushRepository implements PushRepository {
  final unregisterCalls = <String>[];

  @override
  Future<Result<void>> registerToken(String token, DevicePlatform platform) async => const Ok(null);

  @override
  Future<Result<void>> unregisterToken(String token) async {
    unregisterCalls.add(token);
    return const Ok(null);
  }
}

void main() {
  testWidgets('signing out from /me unregisters only this device\'s token (R7.4, Q1)', (tester) async {
    final repo = _RecordingPushRepository();
    final f = Fakes()..overrides.add(pushRepositoryProvider.overrideWithValue(repo));

    await tester.pumpWidget(await buildTestApp(
      repo: FakeAuthRepository(initial: _confirmed),
      // Simulates a device that already registered a token in an earlier
      // session (as `PushController._registerCurrentToken` would have saved
      // it) — sign-out must clean up exactly this key.
      // `push.permission_asked: true` keeps the G-1 permission sheet from
      // popping up automatically on sign-in and blocking the tap below —
      // that flow is covered separately by push_permission_sheet tests.
      prefs: {
        'onboarding_done': true,
        'push.device_token': 'device-tok-42',
        'push.permission_asked': true,
      },
      fakes: f,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(S.tabMe));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(S.signOut), 200);
    await tester.tap(find.text(S.signOut));
    await tester.pumpAndSettle();
    // Confirm dialog (C-23): tap the destructive/confirm action.
    await tester.tap(find.text(S.signOut).last);
    await tester.pumpAndSettle();

    expect(repo.unregisterCalls, ['device-tok-42']);
  });
}
