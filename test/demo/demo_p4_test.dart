import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/demo/demo_data.dart';
import 'package:gowithme/demo/demo_fakes.dart';
import 'package:gowithme/demo/demo_fakes_p4.dart';
import 'package:gowithme/features/chat/domain/chat_models.dart';
import 'package:gowithme/features/safety/domain/safety_models.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/domain/trip_state_machine.dart';

T _ok<T>(Result<T> r) => (r as Ok<T>).value;

void main() {
  test('demo trip walks the whole lifecycle and lands in history', () async {
    final repo = DemoTripRepository();
    expect(repo.active!.status, TripStatus.scheduled);
    final started = _ok(await repo.transition('demo-trip-me', TripAction.start));
    expect(started.status, TripStatus.inProgress);
    // A repeated start is a success (idempotent retry), a complete is legal.
    expect(_ok(await repo.transition('demo-trip-me', TripAction.start)).status, TripStatus.inProgress);
    final done = _ok(await repo.transition('demo-trip-me', TripAction.complete));
    expect(done.status, TripStatus.completed);
    expect(repo.active, isNull);
    final history = _ok(await repo.myTrips(history: true));
    expect(history.first.id, 'demo-trip-me');
    expect(history.map((t) => t.status), containsAll([TripStatus.completed, TripStatus.cancelled, TripStatus.expired]));
    expect(await repo.transition('demo-trip-me', TripAction.start), isA<Err<Trip>>());
  });

  test('demo history has one trip per finished state', () {
    final h = demoHistoryTrips();
    expect({for (final t in h) t.status}, {TripStatus.completed, TripStatus.cancelled, TripStatus.expired});
  });

  test('demo chat: seeded history, chat_state follows the trip, forced states work', () async {
    final trips = DemoTripRepository();
    final chat = DemoChatRepository(trips);
    expect(_ok(await chat.history('demo-match-accepted')).items, hasLength(3));
    expect(_ok(await chat.state('demo-match-accepted')), ChatState.open);
    chat.forceState(ChatState.blocked);
    expect(_ok(await chat.state('demo-match-accepted')), ChatState.blocked);
    chat.forceState(null);
    trips.clear();
    expect(_ok(await chat.state('demo-match-accepted')), ChatState.tripEnded);
  });

  test('demo chat send is idempotent on the client id', () async {
    final chat = DemoChatRepository(DemoTripRepository());
    final a = _ok(await chat.send('demo-match-accepted', 'สวัสดี', 'cid-1'));
    final b = _ok(await chat.send('demo-match-accepted', 'สวัสดี', 'cid-1'));
    expect(a.id, b.id);
    expect(_ok(await chat.history('demo-match-accepted')).items.where((m) => m.clientMsgId == 'cid-1'), hasLength(1));
  });

  test('blocking the partner in the demo closes the chat and shows in the block list', () async {
    final chat = DemoChatRepository(DemoTripRepository());
    final safety = DemoSafetyRepository(chat);
    await safety.block('demo-user-$demoAcceptedCandidateId');
    expect(_ok(await chat.state('demo-match-accepted')), ChatState.blocked);
    expect(_ok(await safety.blocked()).single.displayName, 'ต้นไม้');
    await safety.unblock('demo-user-$demoAcceptedCandidateId');
    expect(_ok(await chat.state('demo-match-accepted')), ChatState.open);
  });

  test('demo contacts obey the limit of 3', () async {
    final repo = DemoContactRepository();
    expect(_ok(await repo.list()), hasLength(1));
    await repo.add(name: 'ก', phone: '0811111111');
    await repo.add(name: 'ข', phone: '0822222222');
    expect(await repo.add(name: 'ค', phone: '0833333333'), isA<Err<EmergencyContact>>());
  });

  test('demo SOS sink can be switched offline', () async {
    final sos = DemoSosRepository();
    final e = SosEvent(id: 'a', clientCreatedAt: DateTime.now());
    sos.offline.value = true;
    expect(await sos.submit(e), isA<Err<void>>());
    sos.offline.value = false;
    expect(await sos.submit(e), isA<Ok<void>>());
    expect(sos.rows.keys, ['a']);
  });

  test('demo share repo mints and revokes links', () async {
    final repo = DemoTripShareRepository();
    final link = _ok(await repo.create('demo-trip-me'));
    expect(_ok(await repo.active()), hasLength(1));
    await repo.revoke(link.id);
    expect(_ok(await repo.active()), isEmpty);
  });

  test('demo partner walks along a route and stays inside Bangkok', () async {
    final live = DemoLiveLocationRepository();
    final p = _ok(await live.partnerLocation('demo-match-accepted'))!;
    expect(p.point.latitude, inInclusiveRange(13.6, 14.0));
    expect(_ok(await live.partnerLocation('other')), isNull);
  });
}
