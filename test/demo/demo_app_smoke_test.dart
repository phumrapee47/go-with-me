import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_p4.dart';
import 'package:gowithme/demo/demo_fakes_p4.dart';
import 'package:gowithme/demo/demo_overrides.dart';
import 'package:gowithme/features/geo/presentation/geo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/p4_helpers.dart';

/// Pumps in small steps so the demo's fake latencies and timers run.
Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final steps = d.inMilliseconds ~/ 250;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Smoke test of the real demo wiring (lib/demo): the whole Phase 4 story is
/// reachable without a server.
void main() {
  testWidgets('demo app: chat, start trip, live view, SOS with offline queue, arrive', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Widget app;
    await runDemoApp((w) => app = w, extraOverrides: [mapTilesEnabledProvider.overrideWithValue(false)]);
    await tester.pumpWidget(app);
    await _pumpFor(tester, const Duration(seconds: 4));
    expect(find.text(S.homeGreeting), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Chat tab: seeded conversation with an unread dot logic, then send.
    await tester.tap(find.text(S.tabChats));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('ต้นไม้'), findsWidgets);
    await tester.tap(find.text('ต้นไม้').first);
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('โอเค เจอกันหน้าสถานีนะครับ'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ไปด้วยนะ');
    await tester.pump();
    await tester.tap(find.byTooltip(P.chatSend));
    await _pumpFor(tester, const Duration(seconds: 3));
    expect(find.text('ไปด้วยนะ'), findsOneWidget);
    expect(find.text('ได้เลยครับ'), findsOneWidget, reason: 'canned partner reply');
    await goBack(tester);
    await _pumpFor(tester, const Duration(seconds: 1));

    // Trips tab: start the demo trip (first-time nudge is skippable).
    await tester.tap(find.text(S.tabTrips));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.text(P.statusScheduled), findsOneWidget);
    await tester.tap(find.text(P.startTrip));
    await _pumpFor(tester, const Duration(seconds: 1));
    if (find.text(P.noContactsTitle).evaluate().isNotEmpty) {
      await tester.tap(find.text(P.noContactsSkip));
    }
    await _pumpFor(tester, const Duration(seconds: 3));
    // Round 6: /trips/active is the unified ride screen (map + sheet + arrive slider).
    expect(find.byKey(const Key('ride-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('slider-arrive')), findsOneWidget);

    // Simulated walking: after a while the partner's live position is polled
    // and the sheet header shows its freshness.
    await _pumpFor(tester, const Duration(seconds: 8));
    expect(find.byKey(const Key('peer-status')), findsOneWidget);
    expect(find.byKey(const Key('eta-chip')), findsOneWidget);

    // SOS with the server "offline": queued locally, phone buttons still there.
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    container.read(demoSosRepositoryProvider).offline.value = true;
    await tester.tap(find.text(P.sos).first);
    await _pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text(P.sosTapConfirm));
    await _pumpFor(tester, const Duration(seconds: 3));
    expect(find.text(P.sosCall191), findsOneWidget);
    expect(find.text(P.sosQueued), findsOneWidget);
    expect(demoToast.value, isNotNull, reason: 'share sheet stand-in was shown');
    await tester.tap(find.text(P.sosCall191));
    expect(demoToast.value, contains('191'));

    // Back online: the queued incident is delivered by the background retry.
    final repo = container.read(demoSosRepositoryProvider);
    repo.offline.value = false;
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _pumpFor(tester, const Duration(seconds: 6));
    expect(repo.rows, isNotEmpty);
    expect(find.text(P.sosSaved), findsOneWidget);

    // Unmount so no timers outlive the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
