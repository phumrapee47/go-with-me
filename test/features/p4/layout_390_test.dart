import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_p4.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/safety/domain/safety_models.dart';
import 'package:gowithme/features/trip/domain/trip.dart';

import '../../support/fake_repos.dart';
import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';

const _width = 390.0;

/// Text whose painted box pokes out of the viewport width (= clipped).
List<String> _clipped(WidgetTester tester) {
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) continue;
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
    final left = box.localToGlobal(Offset.zero).dx;
    if (right > _width + 0.5 || left < -0.5) {
      final w = e.widget as Text;
      out.add('${w.data ?? w.textSpan} (left=$left right=$right)');
    }
  }
  return out;
}

Fakes _fakes() {
  final f = Fakes()
    ..trips.active = runningTrip()
    ..matches.matches = [acceptedMatch()]
    ..finder.result = [for (var i = 0; i < 3; i++) sampleCandidate(tripId: 'c$i', name: 'คนที่ $i')];
  f.contacts.items.add(const EmergencyContact(id: 'c1', name: 'แม่', phone: '0812345678'));
  f.trips.finished.add(sampleTrip(id: 'h1').copyWith(status: TripStatus.completed, endedAt: DateTime.now()));
  return f;
}

void main() {
  for (final scale in [1.0, 1.4]) {
    group('390 px wide, text scale $scale: nothing clipped or overflowing', () {
      Future<Fakes> open(WidgetTester tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final f = _fakes();
        await openApp(tester, f, size: const Size(_width, 844));
        return f;
      }

      Future<void> check(WidgetTester tester) async {
        expect(tester.takeException(), isNull);
        expect(_clipped(tester), isEmpty);
      }

      testWidgets('home', (tester) async {
        await open(tester);
        await check(tester);
      });

      for (final tab in [S.tabNearby, S.tabChats, S.tabTrips, S.tabMe]) {
        testWidgets('tab $tab', (tester) async {
          await open(tester);
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
          await check(tester);
        });
      }

      final routes = <String>[
        Routes.chat('m1'),
        Routes.tripActive('trip-1'),
        Routes.tripDetail('trip-1'),
        Routes.tripDetail('h1'),
        Routes.tripShare('trip-1'),
        Routes.sos,
        Routes.safety,
        Routes.safetyContacts,
        Routes.contactEdit(),
        Routes.report('partner-1', matchId: 'm1', name: 'นุ่น'),
        Routes.blocked,
        Routes.settings,
        Routes.settingsPrivacy,
        Routes.settingsDeleteAccount,
      ];
      for (final r in routes) {
        testWidgets('route $r', (tester) async {
          await open(tester);
          await goTo(tester, r);
          await check(tester);
        });
      }

      testWidgets('SOS after confirming', (tester) async {
        await open(tester);
        await goTo(tester, Routes.sos);
        await tester.tap(find.text(P.sosTapConfirm));
        await tester.pumpAndSettle();
        await check(tester);
      });
    });
  }
}
