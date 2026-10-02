import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/trip/presentation/unified_ride_screen.dart';

/// Keys of the routine sliders on the unified ride screen.
const sliderStartKey = ValueKey('slider-start');
const sliderBoardKey = ValueKey('slider-board');
const sliderArriveKey = ValueKey('slider-arrive');

Finder sliderFinder(ValueKey<String> key) => find.byKey(key);
Finder thumbOf(ValueKey<String> key) =>
    find.descendant(of: find.byKey(key), matching: find.byKey(const Key('slider-thumb')));

/// Drags the thumb of [key] [fraction] of a (very long) way to the right; 1.0 = to the end.
Future<void> dragSlider(WidgetTester tester, ValueKey<String> key, {double dx = 700, bool settle = true}) async {
  await tester.drag(thumbOf(key), Offset(dx, 0));
  await tester.pump();
  if (settle) {
    // 600 ms success hold + animations
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }
}

/// Press and hold on the track for [d] (accessible alternative to dragging).
Future<void> holdSlider(WidgetTester tester, ValueKey<String> key, Duration d, {bool release = true}) async {
  final g = await tester.startGesture(tester.getCenter(find.byKey(key)));
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(d);
  if (release) {
    await g.up();
    await tester.pumpAndSettle();
  }
}

/// Runs the slider's screen-reader path (double tap = the semantics tap action) and settles.
/// [label] is the slider's spoken label.
Future<void> activateSliderViaSemantics(WidgetTester tester, String label) async {
  final handle = tester.ensureSemantics();
  tester.semantics.performAction(find.semantics.byLabel(label), SemanticsAction.tap);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  handle.dispose();
}

/// Same, through the custom action "ยืนยัน: <label>" that appears in the screen reader's actions menu.
Future<void> activateSliderViaCustomAction(WidgetTester tester, String label, String actionLabel) async {
  final handle = tester.ensureSemantics();
  final node = find.semantics.byLabel(label).evaluate().single;
  final data = node.getSemanticsData();
  final id = CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: actionLabel));
  expect(data.customSemanticsActionIds, contains(id));
  tester.semantics.performAction(find.semantics.byLabel(label), SemanticsAction.customAction, args: id);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  handle.dispose();
}

/// Taps the sheet handle until the sheet is at [level] (collapsed -> half -> full -> collapsed).
Future<void> sheetTo(WidgetTester tester, SheetLevel level) async {
  for (var i = 0; i < 4; i++) {
    if (find.byKey(Key('ride-level-${level.name}')).evaluate().isNotEmpty) break;
    await tester.tap(find.byKey(const Key('ride-sheet-handle')));
    await tester.pumpAndSettle();
  }
  expect(find.byKey(Key('ride-level-${level.name}')), findsOneWidget);
}
