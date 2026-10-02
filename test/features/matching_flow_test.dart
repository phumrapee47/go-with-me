import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_trip.dart';
import 'package:gowithme/features/auth/domain/auth_repository.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:latlong2/latlong.dart';

import '../support/fake_repos.dart';
import '../support/fakes.dart';

const _user = AuthUser(id: 'u1', email: 'a@b.co', displayName: 'มิ้นท์', emailConfirmed: true);

Future<Fakes> _open(WidgetTester tester, Fakes f) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await buildTestApp(
    repo: FakeAuthRepository(initial: _user),
    prefs: {'onboarding_done': true},
    fakes: f,
  ));
  await tester.pumpAndSettle();
  return f;
}

Future<void> _goNearby(WidgetTester tester) async {
  await tester.tap(find.text(S.tabNearby));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no trip: home and nearby show the create prompt, find_matches is never called (P-1)',
      (tester) async {
    final f = await _open(tester, Fakes());
    expect(find.text(T.homeCreatePrompt), findsOneWidget);
    expect(find.text(T.homeNearbyHeader), findsNothing);
    await _goNearby(tester);
    expect(find.text(T.nearbyNoTrip), findsOneWidget);
    expect(f.finder.calls, 0);
  });

  testWidgets('home lists the first 3 blurred candidates with the privacy note', (tester) async {
    final fakes = Fakes()
      ..trips.active = sampleTrip()
      ..finder.result = [
        for (var i = 0; i < 5; i++) sampleCandidate(tripId: 'c$i', name: 'คน$i', score: 90 - i.toDouble()),
      ];
    await _open(tester, fakes);
    expect(find.text('คน0'), findsOneWidget);
    expect(find.text('คน2'), findsOneWidget);
    expect(find.text('คน3'), findsNothing);
    expect(find.text(T.mapPrivacy), findsOneWidget);
  });

  testWidgets('nearby: sorted list, request sheet, idempotent single request, status flips',
      (tester) async {
    final f = Fakes()
      ..trips.active = sampleTrip()
      ..finder.result = [
        sampleCandidate(tripId: 'low', name: 'ต่ำ', score: 60),
        sampleCandidate(tripId: 'high', name: 'สูง', score: 95),
      ];
    await _open(tester, f);
    await _goNearby(tester);

    final high = tester.getTopLeft(find.text('สูง').last).dy;
    final low = tester.getTopLeft(find.text('ต่ำ').last).dy;
    expect(high, lessThan(low), reason: 'highest score first');
    expect(find.textContaining('72%'), findsWidgets);

    await tester.tap(find.text(T.goTogether).first);
    await tester.pumpAndSettle();
    expect(find.text(T.sendRequestTitle), findsOneWidget);
    await tester.tap(find.text(T.sendRequest));
    await tester.pumpAndSettle();

    expect(f.matches.requests, [('trip-1', 'high')]);
    expect(find.text(T.requestSent), findsWidgets);
    // The card is now disabled ("ส่งคำขอแล้ว"), a second request is impossible from the UI.
    expect(find.widgetWithText(FilledButton, T.requested), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, T.requested)).onPressed, isNull);
  });

  testWidgets('mutual request auto-matches and says so', (tester) async {
    final f = Fakes()
      ..trips.active = sampleTrip()
      ..finder.result = [sampleCandidate()];
    f.matches.requestStatus = MatchStatus.accepted;
    await _open(tester, f);
    await _goNearby(tester);
    await tester.tap(find.text(T.goTogether));
    await tester.pumpAndSettle();
    await tester.tap(find.text(T.sendRequest));
    await tester.pumpAndSettle();
    expect(find.text(T.requestMatchedNow), findsOneWidget);
    expect(find.widgetWithText(FilledButton, T.matched), findsOneWidget);
  });

  testWidgets('server error while requesting shows a mapped Thai message', (tester) async {
    final f = Fakes()
      ..trips.active = sampleTrip()
      ..finder.result = [sampleCandidate()];
    f.matches.requestFailure = const AppFailure('GWM_PENDING_LIMIT');
    await _open(tester, f);
    await _goNearby(tester);
    await tester.tap(find.text(T.goTogether));
    await tester.pumpAndSettle();
    await tester.tap(find.text(T.sendRequest));
    await tester.pumpAndSettle();
    expect(find.textContaining('ครบจำนวนสูงสุด'), findsOneWidget);
    // Nothing flipped to "requested".
    expect(find.text(T.goTogether), findsOneWidget);
  });

  testWidgets('nearby empty state explains what to do', (tester) async {
    final f = Fakes()..trips.active = sampleTrip();
    await _open(tester, f);
    await _goNearby(tester);
    expect(find.text(T.nearbyEmpty), findsOneWidget);
    expect(find.text(T.nearbyEmptyHint), findsOneWidget);
  });

  testWidgets('nearby error state offers retry', (tester) async {
    final g = Fakes()
      ..trips.active = sampleTrip()
      ..finder.failure = const AppFailure(FailureCode.networkOffline, retryable: true);
    await _open(tester, g);
    await _goNearby(tester);
    expect(find.textContaining('ไม่มีการเชื่อมต่ออินเทอร์เน็ต'), findsOneWidget);
    g.finder.failure = null;
    g.finder.result = [sampleCandidate(name: 'กลับมาแล้ว')];
    await tester.tap(find.text(S.retry));
    await tester.pumpAndSettle();
    expect(find.text('กลับมาแล้ว'), findsOneWidget);
  });

  testWidgets('incoming request: accept opens the match, decline removes it', (tester) async {
    final f = Fakes()
      ..trips.active = sampleTrip()
      ..matches.matches = [
        sampleMatch(id: 'in1', name: 'แนน'),
        sampleMatch(id: 'in2', name: 'บอล'),
      ];
    await _open(tester, f);
    await _goNearby(tester);
    await tester.tap(find.byTooltip(T.requestsTitle));
    await tester.pumpAndSettle();
    expect(find.text('แนน'), findsOneWidget);
    expect(find.text('บอล'), findsOneWidget);

    await tester.tap(find.text(T.decline).last);
    await tester.pumpAndSettle();
    expect(f.matches.responses, [('in2', false)]);
    expect(find.text('บอล'), findsNothing);

    await tester.tap(find.text(T.accept));
    await tester.pumpAndSettle();
    expect(f.matches.responses.last, ('in1', true));
    expect(find.text(T.matchDetail), findsOneWidget); // navigated to /matches/in1
    // No meeting point yet (P-2: agreed only after matching).
    expect(find.text(T.meetingNone), findsOneWidget);
  });

  testWidgets('meeting point: partner proposal can be confirmed', (tester) async {
    final f = Fakes()
      ..trips.active = sampleTrip()
      ..matches.matches = [
        sampleMatch(
          id: 'm1',
          status: MatchStatus.accepted,
          iAmRequester: true,
          proposed: const LatLng(13.75, 100.53),
        ),
      ];
    await _open(tester, f);
    await tester.tap(find.text(S.tabChats));
    await tester.pumpAndSettle();
    await tester.tap(find.text('นุ่น'));
    await tester.pumpAndSettle();
    // The list opens the chat room; its header leads to the match detail.
    await tester.tap(find.byKey(const Key('chat-header')));
    await tester.pumpAndSettle();

    expect(find.text(T.meetingProposedByPartner), findsOneWidget);
    await tester.tap(find.text(T.meetingConfirm));
    await tester.pumpAndSettle();
    expect(find.text(T.meetingConfirmed), findsOneWidget);
    expect(f.matches.matches.single.meetingPoint, const LatLng(13.75, 100.53));
    expect(find.text(T.meetingProposedByPartner), findsNothing);
  });

  testWidgets('own proposal waits for the other side (no confirm button)', (tester) async {
    final f = Fakes()
      ..trips.active = sampleTrip()
      ..matches.matches = [
        sampleMatch(
          id: 'm1',
          status: MatchStatus.accepted,
          iAmRequester: true,
          proposed: const LatLng(13.75, 100.53),
          proposedByMe: true,
        ),
      ];
    await _open(tester, f);
    await tester.tap(find.text(S.tabChats));
    await tester.pumpAndSettle();
    await tester.tap(find.text('นุ่น'));
    await tester.pumpAndSettle();
    // The list opens the chat room; its header leads to the match detail.
    await tester.tap(find.byKey(const Key('chat-header')));
    await tester.pumpAndSettle();
    expect(find.text(T.meetingWaiting), findsOneWidget);
    expect(find.text(T.meetingConfirm), findsNothing);
  });

  testWidgets('realtime change refreshes the incoming badge', (tester) async {
    final f = Fakes()..trips.active = sampleTrip();
    await _open(tester, f);
    expect(find.byType(Badge), findsWidgets);
    f.matches.matches = [sampleMatch(id: 'in1')];
    f.matches.emitChange();
    await tester.pumpAndSettle();
    final badge = tester.widgetList<Badge>(find.byType(Badge)).where((b) => b.isLabelVisible);
    expect(badge, isNotEmpty);
  });

  testWidgets('cancelling a match asks for confirmation first', (tester) async {
    final f = Fakes()
      ..trips.active = sampleTrip()
      ..matches.matches = [sampleMatch(id: 'm1', status: MatchStatus.accepted, iAmRequester: true)];
    await _open(tester, f);
    await tester.tap(find.text(S.tabChats));
    await tester.pumpAndSettle();
    await tester.tap(find.text('นุ่น'));
    await tester.pumpAndSettle();
    // The list opens the chat room; its header leads to the match detail.
    await tester.tap(find.byKey(const Key('chat-header')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(T.cancelMatch));
    await tester.tap(find.text(T.cancelMatch));
    await tester.pumpAndSettle();
    expect(find.text(T.cancelMatchTitle), findsOneWidget);
    await tester.tap(find.text(T.cancelMatchKeep));
    await tester.pumpAndSettle();
    expect(f.matches.matches.single.status, MatchStatus.accepted);

    await tester.tap(find.text(T.cancelMatch));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, T.cancelMatch));
    await tester.pumpAndSettle();
    expect(f.matches.matches.single.status, MatchStatus.cancelled);
  });
}
