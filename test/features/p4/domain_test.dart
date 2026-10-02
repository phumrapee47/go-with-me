import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/config/app_constants.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/features/chat/domain/chat_models.dart';
import 'package:gowithme/features/geo/domain/location_service.dart';
import 'package:gowithme/features/safety/domain/safety_models.dart';
import 'package:gowithme/features/sharing/domain/trip_share.dart';
import 'package:gowithme/features/trip/domain/live_location.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/domain/trip_state_machine.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_repos.dart';
import '../../support/fake_repos_p4.dart';

void main() {
  group('chat_state mapping', () {
    test('maps every server value', () {
      expect(ChatState.fromDb('open'), ChatState.open);
      expect(ChatState.fromDb('blocked'), ChatState.blocked);
      expect(ChatState.fromDb('trip_ended'), ChatState.tripEnded);
      expect(ChatState.fromDb('match_closed'), ChatState.matchClosed);
      expect(ChatState.fromDb('not_found'), ChatState.notFound);
    });

    test('unknown or missing values fail safe to read-only', () {
      expect(ChatState.fromDb('something_new').canSend, isFalse);
      expect(ChatState.fromDb(null).canSend, isFalse);
    });

    test('only open allows sending and every other state has a banner', () {
      for (final s in ChatState.values) {
        expect(s.canSend, s == ChatState.open);
        expect(s.readOnlyBanner.isEmpty, s == ChatState.open);
      }
    });
  });

  group('chat messages', () {
    ChatMessage m(String id, int sec, {String? client, SendStatus st = SendStatus.sent}) => ChatMessage(
          id: id,
          matchId: 'm',
          body: id,
          createdAt: DateTime(2026, 1, 1, 12, 0, sec),
          clientMsgId: client,
          status: st,
        );

    test('merge dedupes optimistic row and server echo by client id', () {
      final local = m('local-a', 5, client: 'a', st: SendStatus.sending);
      final server = m('srv-1', 6, client: 'a');
      final merged = mergeMessages([local], [server]);
      expect(merged, hasLength(1));
      expect(merged.single.id, 'srv-1');
      expect(merged.single.status, SendStatus.sent);
    });

    test('merge keeps chronological order and dedupes by id', () {
      final merged = mergeMessages([m('b', 20), m('a', 10)], [m('a', 10), m('c', 30)]);
      expect([for (final x in merged) x.id], ['a', 'b', 'c']);
    });

    test('system rows render as Thai text, never as the raw key', () {
      final sys = ChatMessage(
        id: 's',
        matchId: 'm',
        body: 'system.trip_cancelled',
        createdAt: DateTime(2026),
        isSystem: true,
      );
      expect(sys.displayText, isNot(contains('system.')));
      expect(systemMessageText('system.unknown'), isNotEmpty);
    });

    test('body validation: empty, too long, ok', () {
      expect(validateChatBody('   '), '');
      expect(validateChatBody('x' * 1001), isNotNull);
      expect(validateChatBody('x' * 1000), isNull);
    });
  });

  group('send throttle', () {
    test('allows the budget then blocks until the window slides', () {
      var now = DateTime(2026, 1, 1, 12);
      final t = SendThrottle(maxPerWindow: 3, window: const Duration(seconds: 10), clock: () => now);
      expect([t.tryAcquire(), t.tryAcquire(), t.tryAcquire()], [true, true, true]);
      expect(t.tryAcquire(), isFalse);
      expect(t.retryAfter(), const Duration(seconds: 10));
      now = now.add(const Duration(seconds: 4));
      expect(t.retryAfter(), const Duration(seconds: 6));
      expect(t.tryAcquire(), isFalse);
      now = now.add(const Duration(seconds: 6));
      expect(t.tryAcquire(), isTrue);
    });

    test('default budget stays under the server limit of 10 per 10 s', () {
      expect(SendThrottle().maxPerWindow, lessThan(10));
    });
  });

  group('trip lifecycle state machine', () {
    test('legal transitions', () {
      expect(TripStateMachine.apply(TripStatus.scheduled, TripAction.start), TripStatus.inProgress);
      expect(TripStateMachine.apply(TripStatus.scheduled, TripAction.cancel), TripStatus.cancelled);
      expect(TripStateMachine.apply(TripStatus.inProgress, TripAction.complete), TripStatus.completed);
      expect(TripStateMachine.apply(TripStatus.inProgress, TripAction.cancel), TripStatus.cancelled);
    });

    test('everything else is illegal, terminal states allow nothing', () {
      expect(TripStateMachine.canApply(TripStatus.scheduled, TripAction.complete), isFalse);
      expect(TripStateMachine.canApply(TripStatus.inProgress, TripAction.start), isFalse);
      for (final s in [TripStatus.completed, TripStatus.cancelled, TripStatus.expired]) {
        expect(s.isTerminal, isTrue);
        expect(TripStateMachine.actionsFor(s), isEmpty, reason: '$s is terminal');
      }
    });

    test('expired is reachable only by the system', () {
      expect(TripStateMachine.canTransition(TripStatus.scheduled, TripStatus.expired), isFalse);
      expect(TripStateMachine.canTransition(TripStatus.scheduled, TripStatus.expired, system: true), isTrue);
      expect(TripStateMachine.canTransition(TripStatus.inProgress, TripStatus.expired, system: true), isFalse);
    });

    test('every pair matches the DB trigger table', () {
      const allowed = {
        (TripStatus.scheduled, TripStatus.inProgress),
        (TripStatus.scheduled, TripStatus.cancelled),
        (TripStatus.inProgress, TripStatus.completed),
        (TripStatus.inProgress, TripStatus.cancelled),
      };
      for (final a in TripStatus.values) {
        for (final b in TripStatus.values) {
          expect(TripStateMachine.canTransition(a, b), allowed.contains((a, b)), reason: '$a -> $b');
        }
      }
    });

    test('patch guard sources and idempotent retry detection', () {
      expect(TripStateMachine.sourcesFor(TripAction.start), [TripStatus.scheduled]);
      expect(TripStateMachine.sourcesFor(TripAction.cancel), [TripStatus.scheduled, TripStatus.inProgress]);
      expect(TripStateMachine.isAlreadyDone(TripStatus.inProgress, TripAction.start), isTrue);
      expect(TripStateMachine.isAlreadyDone(TripStatus.completed, TripAction.start), isFalse);
    });
  });

  group('live location sharer', () {
    late FakeLiveLocationRepository repo;
    late DateTime now;
    late LiveLocationSharer sharer;

    LocationFix fix({Duration age = Duration.zero}) =>
        LocationFix(point: const LatLng(13.75, 100.5), at: now.subtract(age));

    setUp(() {
      repo = FakeLiveLocationRepository();
      now = DateTime(2026, 1, 1, 12);
      sharer = LiveLocationSharer(repo: repo, clock: () => now)..start('trip-1');
    });

    test('first fix is sent immediately, then at most one push per 15 s', () async {
      expect(await sharer.onFix(fix()), PushOutcome.sent);
      now = now.add(const Duration(seconds: 5));
      expect(await sharer.onFix(fix()), PushOutcome.throttled);
      now = now.add(const Duration(seconds: 9));
      expect(await sharer.onFix(fix()), PushOutcome.throttled);
      now = now.add(const Duration(seconds: 1));
      expect(await sharer.onFix(fix()), PushOutcome.sent);
      expect(repo.pushes, hasLength(2));
      expect(LiveLocationSharer.livePushInterval, const Duration(seconds: 15));
    });

    test('interval follows config and is clamped to 15-30 s', () async {
      expect(AppConstants.livePushInterval(), const Duration(seconds: 15));
      expect(AppConstants.livePushInterval(5), const Duration(seconds: 15));
      expect(AppConstants.livePushInterval(22), const Duration(seconds: 22));
      expect(AppConstants.livePushInterval(120), const Duration(seconds: 30));
      final s30 = LiveLocationSharer(repo: repo, clock: () => now, minInterval: AppConstants.livePushInterval(30))
        ..start('trip-1');
      expect(await s30.onFix(fix()), PushOutcome.sent);
      now = now.add(const Duration(seconds: 29));
      expect(await s30.onFix(fix()), PushOutcome.throttled);
      now = now.add(const Duration(seconds: 1));
      expect(await s30.onFix(fix()), PushOutcome.sent);
    });

    test('drops fixes older than 2 minutes', () async {
      expect(await sharer.onFix(fix(age: const Duration(minutes: 3))), PushOutcome.stale);
      expect(repo.pushes, isEmpty);
    });

    test('nothing is sent after stop (trip end / block)', () async {
      sharer.stop();
      expect(await sharer.onFix(fix()), PushOutcome.inactive);
      expect(repo.pushes, isEmpty);
    });

    test('server rate limit drops silently and keeps going', () async {
      repo.pushFailure = const AppFailure('GWM_RATE_LIMITED', retryable: true);
      expect(await sharer.onFix(fix()), PushOutcome.dropped);
      repo.pushFailure = null;
      now = now.add(const Duration(seconds: 16));
      expect(await sharer.onFix(fix()), PushOutcome.sent);
    });

    test('a permission denial from the server stops sharing for good', () async {
      repo.pushFailure = const AppFailure(FailureCode.forbiddenRls);
      expect(await sharer.onFix(fix()), PushOutcome.stopped);
      repo.pushFailure = null;
      now = now.add(const Duration(seconds: 10));
      expect(await sharer.onFix(fix()), PushOutcome.inactive);
      expect(sharer.active, isFalse);
    });
  });

  group('arrival prompt', () {
    final trip = sampleTrip().copyWith(status: TripStatus.inProgress, startedAt: DateTime(2026, 1, 1, 12));

    test('near within 300 m of the destination', () {
      final near = LatLng(trip.dest.latitude + 0.0015, trip.dest.longitude); // ~167 m
      final far = LatLng(trip.dest.latitude + 0.01, trip.dest.longitude); // ~1.1 km
      expect(arrivalPromptFor(trip: trip, now: DateTime(2026, 1, 1, 12, 5), position: near), ArrivalPrompt.near);
      expect(arrivalPromptFor(trip: trip, now: DateTime(2026, 1, 1, 12, 5), position: far), ArrivalPrompt.none);
    });

    test('overdue 30 minutes after the expected arrival, without GPS too', () {
      // sampleTrip: 1800 s => expected 12:30, overdue after 13:00.
      expect(arrivalPromptFor(trip: trip, now: DateTime(2026, 1, 1, 12, 50)), ArrivalPrompt.none);
      expect(arrivalPromptFor(trip: trip, now: DateTime(2026, 1, 1, 13, 1)), ArrivalPrompt.overdue);
    });
  });

  group('emergency contact rules', () {
    test('max 3 contacts', () {
      expect(ContactRules.maxContacts, 3);
      expect(ContactRules.canAdd(0), isTrue);
      expect(ContactRules.canAdd(2), isTrue);
      expect(ContactRules.canAdd(3), isFalse);
    });

    test('deleting the last contact needs the SOS warning', () {
      expect(ContactRules.deleteNeedsLastWarning(1), isTrue);
      expect(ContactRules.deleteNeedsLastWarning(2), isFalse);
    });

    test('phone validation matches the DB constraint', () {
      expect(ContactRules.isValidPhone('081-234 5678'), isTrue);
      expect(ContactRules.isValidPhone('+66812345678'), isTrue);
      expect(ContactRules.isValidPhone('12345'), isFalse);
      expect(ContactRules.isValidPhone('08123abc78'), isFalse);
      expect(ContactRules.isValidPhone('1' * 16), isFalse);
      expect(ContactRules.normalizePhone('(081) 234-5678'), '0812345678');
    });

    test('duplicate detection ignores formatting and the edited row', () {
      const a = EmergencyContact(id: '1', name: 'a', phone: '0812345678');
      expect(ContactRules.isDuplicate([a], '081 234 5678'), isTrue);
      expect(ContactRules.isDuplicate([a], '081 234 5678', exceptId: '1'), isFalse);
      expect(ContactRules.isDuplicate([a], '0899999999'), isFalse);
    });

    test('names: required, max 60', () {
      expect(ContactRules.isValidName(' '), isFalse);
      expect(ContactRules.isValidName('x' * 61), isFalse);
      expect(ContactRules.isValidName('แม่'), isTrue);
    });
  });

  group('trip share', () {
    final trip = sampleTrip().copyWith(status: TripStatus.inProgress, startedAt: DateTime(2026, 1, 1, 12));

    test('snapshot text has name, status, destination and no contact data', () {
      final text = buildTripShareText(
        name: 'มิ้นท์',
        trip: trip,
        now: DateTime(2026, 1, 1, 12, 10),
        lastPosition: const LatLng(13.75, 100.52),
      );
      expect(text, contains('มิ้นท์'));
      expect(text, contains('กำลังเดินทาง'));
      expect(text, contains('รังสิต'));
      expect(text, contains('openstreetmap.org'));
      expect(text, isNot(contains('@')));
    });

    test('no link line without a backend token', () {
      final text = buildTripShareText(name: 'ก', trip: trip, now: DateTime(2026, 1, 1, 12));
      expect(text, isNot(contains('ติดตามต่อ')));
    });

    test('link only when a share page is configured, https only, token in the fragment', () {
      expect(shareUrl('', 'tok'), isNull);
      expect(shareUrl('http://x.example', 'tok'), isNull);
      final u = shareUrl('https://share.example/', 'tok')!;
      expect(u.toString(), 'https://share.example/t#tok');
      expect(u.hasQuery, isFalse);
    });
  });
}
