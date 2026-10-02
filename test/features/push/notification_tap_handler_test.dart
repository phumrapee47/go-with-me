import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/push/domain/push_models.dart';
import 'package:gowithme/features/push/presentation/notification_tap_handler.dart';
import 'package:gowithme/features/push/presentation/push_copy.dart';

void main() {
  group('routeForPushMessage (G-3, design-spec-round7 G.1.4)', () {
    test('new_request -> /nearby/requests (no id needed)', () {
      const m = PushMessage(kind: PushKind.newRequest);
      expect(routeForPushMessage(m), Routes.nearbyRequests);
    });

    test('match_accepted -> /matches/:matchId', () {
      const m = PushMessage(kind: PushKind.matchAccepted, matchId: 'm1');
      expect(routeForPushMessage(m), Routes.match('m1'));
    });

    test('driver_arrived -> /matches/:matchId/live', () {
      const m = PushMessage(kind: PushKind.driverArrived, matchId: 'm1');
      expect(routeForPushMessage(m), Routes.live('m1'));
    });

    test('match_cancelled -> /matches/:matchId', () {
      const m = PushMessage(kind: PushKind.matchCancelled, matchId: 'm1');
      expect(routeForPushMessage(m), Routes.match('m1'));
    });

    test('new_message -> /chats/:matchId', () {
      const m = PushMessage(kind: PushKind.newMessage, matchId: 'm1');
      expect(routeForPushMessage(m), Routes.chat('m1'));
    });

    test('missing required id: unresolvable (null), never crashes/navigates blindly', () {
      const m = PushMessage(kind: PushKind.matchAccepted); // no matchId
      expect(routeForPushMessage(m), isNull);
    });
  });

  group('PushMessage.fromData (opaque payload parsing)', () {
    test('parses a well-formed payload', () {
      final m = PushMessage.fromData({'kind': 'driver_arrived', 'match_id': 'm9'});
      expect(m, isNotNull);
      expect(m!.kind, PushKind.driverArrived);
      expect(m.matchId, 'm9');
    });

    test('unknown kind -> null (drop silently, never crash)', () {
      expect(PushMessage.fromData({'kind': 'something_new'}), isNull);
    });

    test('missing kind -> null', () {
      expect(PushMessage.fromData({'match_id': 'm9'}), isNull);
    });
  });

  test('pushKindText covers all 5 kinds with distinct, non-empty Thai copy', () {
    final texts = PushKind.values.map(pushKindText).toSet();
    expect(texts.length, PushKind.values.length);
    for (final t in texts) {
      expect(t, isNotEmpty);
    }
  });
}
