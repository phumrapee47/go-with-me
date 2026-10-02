import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_r5.dart';
import 'package:gowithme/core/l10n/strings_r6_cd.dart';
import 'package:gowithme/core/l10n/strings_roles.dart';
import 'package:gowithme/core/l10n/strings_trip.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/matching/presentation/deck_controller.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';

Future<Fakes> _openDeck(WidgetTester tester, Fakes f, {Size size = const Size(800, 1600), String view = 'deck'}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await buildTestApp(
    repo: FakeAuthRepository(initial: testUser),
    prefs: {'onboarding_done': true, 'gwm.nearbyView': view},
    fakes: f,
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text(S.tabNearby));
  await tester.pumpAndSettle();
  return f;
}

Fakes _fakes({List<MatchCandidate>? items, Trip? trip}) => Fakes()
  ..trips.active = trip ?? sampleTrip()
  ..finder.result = items ??
      [
        sampleCandidate(tripId: 'a', name: 'นุ่น', score: 90),
        sampleCandidate(tripId: 'b', name: 'บอม', score: 80),
        sampleCandidate(tripId: 'c', name: 'ใบเตย', score: 70),
      ];

Future<void> _tapInvite(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('deck-invite')));
  await tester.pumpAndSettle();
}

void main() {
  group('deck: card rating slot (US-36, migration 0010)', () {
    testWidgets('shown only when both rating_avg and rating_count are present', (tester) async {
      await _openDeck(tester, _fakes(items: [
        sampleCandidate(tripId: 'a', name: 'นุ่น', ratingAvg: 4.6, ratingCount: 5),
      ]));
      expect(find.byKey(const Key('card-rating')), findsOneWidget);
      expect(find.text(R6C.ratingLine(4.6, 5)), findsOneWidget);
    });

    testWidgets('hidden completely (no placeholder text) when null (older server or < 3 reviews)', (tester) async {
      await _openDeck(tester, _fakes(items: [sampleCandidate(tripId: 'a', name: 'นุ่น')]));
      expect(find.byKey(const Key('card-rating')), findsNothing);
    });
  });

  group('deck: the card', () {
    testWidgets('is the default view: initials + nickname, no photo, overlap, time, counter', (tester) async {
      final f = await _openDeck(tester, _fakes());
      expect(find.byKey(const Key('view-toggle')), findsOneWidget);
      expect(find.byKey(const Key('commute-card-a')), findsOneWidget);
      expect(find.text('นุ่น'), findsOneWidget);
      expect(find.text(R6C.overlapLine(72)), findsOneWidget);
      expect(find.textContaining('ออกเดินทาง'), findsOneWidget);
      expect(find.text(R6C.counter(1, 3)), findsOneWidget);
      expect(find.text(R6C.privacyCaption), findsOneWidget);
      expect(find.byType(Image), findsNothing, reason: 'no photo before a match (US-22)');
      expect(f.finder.calls, 1);
    });

    testWidgets('a Driver card: short limit wording only', (tester) async {
      final f = _fakes(
        trip: sampleTrip(mode: TravelMode.car, role: TripRole.rider),
        items: [sampleCandidate(tripId: 'd1', name: 'คนขับ', mode: TravelMode.car, role: TripRole.driver, maxDropoffM: 1500)],
      );
      await _openDeck(tester, f);
      expect(find.text(R6C.driverShortLimit('1.5 กม.')), findsOneWidget);
      expect(find.text(R.roleBadgeDriver), findsWidgets);
      expect(find.text(R5.matchDriverMaxDropoff('1.5 กม.')), findsNothing, reason: 'long form is on the detail page');
    });

    testWidgets('no rating block without data (hidden hook, no gap)', (tester) async {
      await _openDeck(tester, _fakes());
      expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
    });

    testWidgets('empty: the no-match hint from get_match_hint shows', (tester) async {
      final f = _fakes(items: []);
      await _openDeck(tester, f);
      expect(find.text(T.nearbyEmpty), findsOneWidget);
      expect(find.byKey(const Key('no-match-hint')), findsOneWidget);
      expect(f.finder.hintCalls, greaterThan(0));
    });

    testWidgets('error: retry state', (tester) async {
      final f = _fakes()..finder.failure = const AppFailure(FailureCode.networkOffline, retryable: true);
      await _openDeck(tester, f);
      expect(find.text(S.retry), findsOneWidget);
    });

    testWidgets('never shows myself, duplicates or people with an existing request', (tester) async {
      final f = _fakes(items: [
        sampleCandidate(tripId: 'trip-1', name: 'ฉันเอง'),
        sampleCandidate(tripId: 'a', name: 'นุ่น'),
        sampleCandidate(tripId: 'a', name: 'นุ่น'),
        sampleCandidate(tripId: 'p', name: 'ชวนแล้ว', status: MatchStatus.pending),
      ]);
      await _openDeck(tester, f);
      expect(find.text('ฉันเอง'), findsNothing);
      expect(find.text('ชวนแล้ว'), findsNothing);
      expect(find.text(R6C.counter(1, 1)), findsOneWidget);
    });
  });

  group('deck: skip', () {
    testWidgets('X button goes to the next card and sends nothing', (tester) async {
      final f = await _openDeck(tester, _fakes());
      await tester.tap(find.byKey(const Key('deck-skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('commute-card-b')), findsOneWidget);
      expect(find.text(R6C.counter(2, 3)), findsOneWidget);
      expect(f.matches.requests, isEmpty);
    });

    testWidgets('swipe left skips; a short drag snaps back', (tester) async {
      final f = await _openDeck(tester, _fakes());
      await tester.drag(find.byKey(const Key('commute-card-a')), const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('commute-card-a')), findsOneWidget);
      await tester.drag(find.byKey(const Key('commute-card-a')), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('commute-card-b')), findsOneWidget);
      expect(f.matches.requests, isEmpty);
    });

    testWidgets('stamps carry icon + text while dragging', (tester) async {
      await _openDeck(tester, _fakes());
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('commute-card-a'))));
      await g.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(find.byKey(const Key('stamp-invite')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('stamp-invite')), matching: find.text(R6C.stampInvite)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('stamp-invite')), matching: find.byIcon(Icons.favorite)), findsOneWidget);
      await g.moveBy(const Offset(-500, 0));
      await tester.pump();
      expect(find.byKey(const Key('stamp-skip')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('stamp-skip')), matching: find.text(R6C.stampSkip)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('stamp-skip')), matching: find.byIcon(Icons.close)), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('skipped cards come back on refresh (nothing stored)', (tester) async {
      final f = _fakes(items: [sampleCandidate(tripId: 'a', name: 'นุ่น')]);
      await _openDeck(tester, f);
      await tester.tap(find.byKey(const Key('deck-skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deck-end')), findsOneWidget);
      expect(find.byKey(const Key('deck-end-sent')), findsNothing, reason: 'skips are never counted');
      await tester.tap(find.byKey(const Key('deck-end-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('commute-card-a')), findsOneWidget);
    });
  });

  group('deck: invite + undo (Q6)', () {
    testWidgets('heart sends at once through request_match; banner then offers undo', (tester) async {
      final f = await _openDeck(tester, _fakes());
      await _tapInvite(tester);
      expect(f.matches.requests, [('trip-1', 'a')]);
      expect(find.byKey(const Key('undo-banner')), findsOneWidget);
      expect(find.text(T.requestSent), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(const Key('undo-button'))).onPressed, isNotNull);
      expect(find.byKey(const Key('commute-card-b')), findsOneWidget);
    });

    testWidgets('swipe right = one request; a second call for the same card is ignored', (tester) async {
      final f = await _openDeck(tester, _fakes());
      await tester.drag(find.byKey(const Key('commute-card-a')), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(f.matches.requests, [('trip-1', 'a')]);
      await containerOf(tester).read(deckProvider.notifier).invite(sampleCandidate(tripId: 'a'), windowSeconds: 5);
      expect(f.matches.requests.length, 1);
    });

    testWidgets('undo cancels the pending request and the card comes back', (tester) async {
      final f = await _openDeck(tester, _fakes());
      await _tapInvite(tester);
      await tester.tap(find.byKey(const Key('undo-button')));
      await tester.pumpAndSettle();
      expect(f.matches.matches.firstWhere((m) => m.id == 'm-new').status, MatchStatus.cancelled);
      expect(find.text(R6C.undone), findsOneWidget);
      expect(find.byKey(const Key('commute-card-a')), findsOneWidget);
      expect(find.text(R6C.counter(1, 3)), findsOneWidget);
    });

    testWidgets('undo calls cancel_pending_match (0010), never the plain cancel_match path', (tester) async {
      final f = await _openDeck(tester, _fakes());
      await _tapInvite(tester);
      await tester.tap(find.byKey(const Key('undo-button')));
      await tester.pumpAndSettle();
      expect(f.matches.cancelPendingCalls, ['m-new']);
    });

    testWidgets('undo is idempotent: cancel_pending_match returning already_cancelled still shows "เลิกชวนแล้ว"', (tester) async {
      final f = await _openDeck(tester, _fakes());
      await _tapInvite(tester);
      // The local pre-read (UX only) still sees the request as pending; the RPC itself finds it already
      // cancelled (e.g. a retried undo) and answers 'already_cancelled' -- an idempotent success, not an error.
      f.matches.frozenInbox = List.of(f.matches.matches);
      f.matches.matches = [for (final m in f.matches.matches) m.id == 'm-new' ? m.copyWith(status: MatchStatus.cancelled) : m];
      await tester.tap(find.byKey(const Key('undo-button')));
      await tester.pumpAndSettle();
      expect(f.matches.cancelPendingCalls, ['m-new']);
      expect(find.text(R6C.undone), findsOneWidget);
    });

    testWidgets('server-side accept races the pre-read: cancel_pending_match answers GWM_MATCH_NOT_PENDING, '
        'polite message shown, the match stays accepted', (tester) async {
      final f = await _openDeck(tester, _fakes());
      await _tapInvite(tester);
      f.matches.frozenInbox = List.of(f.matches.matches); // pre-read still sees "pending"
      f.matches.matches = [for (final m in f.matches.matches) m.id == 'm-new' ? m.copyWith(status: MatchStatus.accepted) : m];
      f.matches.cancelPendingFailure = const AppFailure('GWM_MATCH_NOT_PENDING');
      await tester.tap(find.byKey(const Key('undo-button')));
      await tester.pumpAndSettle();
      expect(find.text(R6C.undoAccepted), findsOneWidget);
      expect(f.matches.matches.firstWhere((m) => m.id == 'm-new').status, MatchStatus.accepted);
    });

    testWidgets('the undo window is 5 s, then only the plain message', (tester) async {
      await _openDeck(tester, _fakes());
      await _tapInvite(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const Key('undo-button')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('undo-button')), findsNothing);
      expect(find.text(T.requestSent), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('undo-banner')), findsNothing);
    });

    testWidgets('a screen reader gets 8 s', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _openDeck(tester, _fakes());
      await _tapInvite(tester);
      await tester.pump(const Duration(seconds: 6));
      expect(find.byKey(const Key('undo-button')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('undo-button')), findsNothing);
    });

    testWidgets('while the request is in flight the phase is "sending" (undo disabled)', (tester) async {
      final f = _fakes();
      await _openDeck(tester, f);
      final c = containerOf(tester);
      final future = c.read(deckProvider.notifier).invite(sampleCandidate(tripId: 'a'), windowSeconds: 5);
      expect(c.read(deckProvider).banner?.phase, InvitePhase.sending);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await future;
      expect(c.read(deckProvider).banner?.phase, InvitePhase.undoable);
    });

    testWidgets('undo after the other side accepted: refused politely, the match stays accepted', (tester) async {
      final f = await _openDeck(tester, _fakes());
      await _tapInvite(tester);
      f.matches.matches = [for (final m in f.matches.matches) m.id == 'm-new' ? m.copyWith(status: MatchStatus.accepted) : m];
      await tester.tap(find.byKey(const Key('undo-button')));
      await tester.pumpAndSettle();
      expect(find.text(R6C.undoAccepted), findsOneWidget);
      expect(f.matches.matches.firstWhere((m) => m.id == 'm-new').status, MatchStatus.accepted);
    });

    testWidgets('send throttle: clear Thai message, the card stays', (tester) async {
      final f = _fakes();
      f.matches.requestFailure = const AppFailure('GWM_RATE_LIMITED', retryable: true);
      await _openDeck(tester, f);
      await _tapInvite(tester);
      expect(find.text(R6C.throttled), findsOneWidget);
      expect(find.byKey(const Key('commute-card-a')), findsOneWidget);
      expect(find.byKey(const Key('undo-banner')), findsNothing);
    });

    testWidgets('pending cap: message, heart disabled, bar with a way to the requests', (tester) async {
      final f = _fakes();
      f.matches.requestFailure = const AppFailure('GWM_PENDING_LIMIT');
      // The server only says "limit" when open requests exist: one is already in the inbox.
      f.matches.matches = [sampleMatch(id: 'p1', status: MatchStatus.pending, iAmRequester: true)];
      await _openDeck(tester, f);
      await _tapInvite(tester);
      expect(find.text(R.pendingCap), findsOneWidget);
      expect(find.byKey(const Key('deck-cap-bar')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('deck-invite'))).onPressed, isNull);
      final before = f.matches.requests.length;
      await tester.drag(find.byKey(const Key('commute-card-a')), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(f.matches.requests.length, before);
      expect(find.byKey(const Key('commute-card-a')), findsOneWidget);
    });

    testWidgets('a rule error removes the card for good, with a Thai reason', (tester) async {
      final f = _fakes();
      f.matches.requestFailure = const AppFailure('GWM_NOT_ELIGIBLE');
      await _openDeck(tester, f);
      await _tapInvite(tester);
      expect(find.textContaining('ชวนไม่สำเร็จ'), findsOneWidget);
      expect(find.byKey(const Key('commute-card-a')), findsNothing);
    });

    testWidgets('mutual request: matched at once, no undo button', (tester) async {
      final f = _fakes();
      f.matches.requestStatus = MatchStatus.accepted;
      await _openDeck(tester, f);
      await _tapInvite(tester);
      expect(find.text(T.requestMatchedNow), findsOneWidget);
      expect(find.byKey(const Key('undo-button')), findsNothing);
    });

    testWidgets('end of deck: summary counts only what I invited', (tester) async {
      final f = _fakes(items: [sampleCandidate(tripId: 'a'), sampleCandidate(tripId: 'b', name: 'บอม')]);
      await _openDeck(tester, f);
      await _tapInvite(tester);
      await tester.tap(find.byKey(const Key('deck-skip')));
      await tester.pumpAndSettle();
      expect(find.text(R6C.endTitle), findsOneWidget);
      expect(find.text(R6C.endSummary(1)), findsOneWidget);
    });
  });

  group('deck: accessibility + toggle', () {
    testWidgets('X and heart are real buttons with the spoken labels', (tester) async {
      final handle = tester.ensureSemantics();
      await _openDeck(tester, _fakes());
      expect(find.bySemanticsLabel(R6C.skip), findsWidgets);
      expect(find.bySemanticsLabel(R6C.invite), findsWidgets);
      expect(find.byKey(const Key('deck-invite')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the card reads as one sentence with role, badges, overlap and time', (tester) async {
      final handle = tester.ensureSemantics();
      await _openDeck(tester, _fakes());
      expect(find.bySemanticsLabel(RegExp('นุ่น, .*ทางเดียวกันประมาณ 72 เปอร์เซ็นต์.*ออกเดินทาง')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('reduce motion: a swipe still works and the timer is a static text', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final f = await _openDeck(tester, _fakes());
      await tester.drag(find.byKey(const Key('commute-card-a')), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(f.matches.requests, [('trip-1', 'a')]);
      expect(find.byKey(const Key('undo-left')), findsOneWidget);
    });

    testWidgets('toggle to the list keeps the old list; an invited person leaves the deck', (tester) async {
      final f = _fakes();
      await _openDeck(tester, f);
      await tester.tap(find.byKey(const Key('view-list')));
      await tester.pumpAndSettle();
      expect(find.text(T.goTogether), findsWidgets);
      expect(find.byKey(const Key('commute-card-a')), findsNothing);
      await tester.tap(find.text(T.goTogether).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(T.sendRequest));
      await tester.pumpAndSettle();
      expect(f.matches.requests, [('trip-1', 'a')]);
      await tester.tap(find.byKey(const Key('view-card')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('commute-card-a')), findsNothing);
      expect(find.byKey(const Key('commute-card-b')), findsOneWidget);
    });

    for (final scale in [1.0, 1.4, 2.0]) {
      testWidgets('layout at 390 px, text x$scale: no overflow, buttons reachable', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _openDeck(
          tester,
          _fakes(trip: sampleTrip(mode: TravelMode.car, role: TripRole.rider), items: [
            sampleCandidate(tripId: 'd1', name: 'คนขับที่มีชื่อยาวมากๆๆๆ', mode: TravelMode.car, role: TripRole.driver, maxDropoffM: 2000),
          ]),
          size: const Size(390, 844),
        );
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('deck-invite')), findsOneWidget);
        await tester.tap(find.byKey(const Key('deck-invite')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 12));
      });
    }
  });
}
