import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/l10n/strings_r6_cd.dart';
import 'package:gowithme/features/avatar/presentation/user_avatar.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';

MatchSummary _m(MatchStatus s, {bool requester = true, String id = 'm1'}) =>
    sampleMatch(id: id, status: s, iAmRequester: requester, myRole: TripRole.rider);

Future<Fakes> _open(WidgetTester tester, Fakes f) async {
  await openApp(tester, f);
  return f;
}

Future<void> _accept(WidgetTester tester, Fakes f, {String id = 'm1'}) async {
  f.matches.matches = [for (final m in f.matches.matches) m.id == id ? m.copyWith(status: MatchStatus.accepted) : m];
  f.matches.emitChange();
  await tester.pumpAndSettle();
}

void main() {
  Fakes base() => Fakes()
    ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.rider)
    ..matches.matches = [_m(MatchStatus.pending)];

  testWidgets('shows after the other side accepts: both photos slots, title, two actions, safety line', (tester) async {
    final f = await _open(tester, base());
    expect(find.byKey(const Key('match-moment')), findsNothing);
    await _accept(tester, f);
    expect(find.byKey(const Key('match-moment')), findsOneWidget);
    expect(find.byKey(const Key('match-moment-title')), findsOneWidget);
    expect(find.text(R6C.momentGreet), findsOneWidget);
    expect(find.text(R6C.momentMap), findsOneWidget);
    expect(find.byType(UserAvatar), findsNWidgets(2));
    expect(find.byKey(const Key('moment-safety')), findsOneWidget);
    // The partner's destination is never part of it.
    expect(find.textContaining('ปลายทาง'), findsNothing);
  });

  testWidgets('title has a spoken form without the emoji name', (tester) async {
    final handle = tester.ensureSemantics();
    final f = await _open(tester, base());
    await _accept(tester, f);
    expect(find.bySemanticsLabel(R6C.momentTitleSemantics), findsOneWidget);
    handle.dispose();
  });

  testWidgets('only once per match: closing marks it seen, a later refresh does not bring it back', (tester) async {
    final f = await _open(tester, base());
    await _accept(tester, f);
    await tester.tap(find.byKey(const Key('moment-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('match-moment')), findsNothing);
    f.matches.emitChange();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('match-moment')), findsNothing);
  });

  testWidgets('"ทักทายนัดจุดรับ" opens the chat with the sentence in the box, NOT sent', (tester) async {
    final f = await _open(tester, base());
    await _accept(tester, f);
    await tester.tap(find.byKey(const Key('moment-greet')));
    await tester.pumpAndSettle();
    expect(find.text(R6C.momentGreetText), findsWidgets);
    expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, R6C.momentGreetText);
    expect(f.chat.sent, isEmpty);
  });

  testWidgets('"ดูแผนที่การเดินทาง" goes to the ride screen when the trip is active', (tester) async {
    final f = await _open(tester, base());
    await _accept(tester, f);
    await tester.tap(find.byKey(const Key('moment-map')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('match-moment')), findsNothing);
    expect(find.byKey(const Key('ride-sheet-handle')), findsOneWidget);
  });

  testWidgets('back / scrim close it without losing the match', (tester) async {
    final f = await _open(tester, base());
    await _accept(tester, f);
    await tester.tapAt(const Offset(4, 4)); // scrim
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('match-moment')), findsNothing);
    expect(f.matches.matches.single.status, MatchStatus.accepted);
  });

  testWidgets('a match that was already accepted before this device saw it pending: no celebration', (tester) async {
    final f = Fakes()
      ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.rider)
      ..matches.matches = [_m(MatchStatus.accepted)];
    await _open(tester, f);
    expect(find.byKey(const Key('match-moment')), findsNothing);
  });

  testWidgets('the accepter (not the requester) gets no modal', (tester) async {
    final f = Fakes()
      ..trips.active = sampleTrip(mode: TravelMode.car, role: TripRole.rider)
      ..matches.matches = [_m(MatchStatus.pending, requester: false)];
    await _open(tester, f);
    await _accept(tester, f);
    expect(find.byKey(const Key('match-moment')), findsNothing);
  });

  testWidgets('cancelled before it is shown: no modal', (tester) async {
    final f = await _open(tester, base());
    f.matches.matches = [_m(MatchStatus.cancelled)];
    f.matches.emitChange();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('match-moment')), findsNothing);
  });

  testWidgets('reduce motion: no confetti, still shown', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final f = await _open(tester, base());
    await _accept(tester, f);
    expect(find.byKey(const Key('match-moment')), findsOneWidget);
    expect(find.byIcon(Icons.celebration), findsOneWidget);
  });
}
