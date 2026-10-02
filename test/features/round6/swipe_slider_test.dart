import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/l10n/strings_r6.dart';
import 'package:gowithme/core/widgets/swipe_to_confirm_slider.dart';

const _k = ValueKey('s');

/// Harness: a plain MaterialApp (Rider tone) around one slider.
Widget _app(
  SwipeToConfirmSlider Function() slider, {
  double textScale = 1,
  bool reduceMotion = false,
  double width = 358,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width + 32, 800),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: Center(child: SizedBox(width: width, child: slider())),
        ),
      ),
    );

Finder get _thumb => find.byKey(const Key('slider-thumb'));

Future<void> _drag(WidgetTester t, double dx) async {
  await t.drag(_thumb, Offset(dx, 0));
  await t.pump();
}

void main() {
  group('SwipeToConfirmSlider (US-31)', () {
    testWidgets('dragging all the way confirms exactly once; the track is 64 dp and the thumb 56 dp', (tester) async {
      var calls = 0;
      var done = 0;
      await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
            key: _k,
            label: R6.sliderBoard,
            successLabel: R6.boardedSuccess,
            onConfirm: () async {
              calls++;
              return null;
            },
            onSucceeded: () => done++,
          )));
      expect(tester.getSize(_thumb), const Size(56, 56));
      expect(tester.getSize(find.byType(AnimatedContainer)).height, 64);
      expect(find.text(R6.sliderBoard), findsOneWidget);

      await _drag(tester, 900);
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, 1);
      expect(find.text(R6.boardedSuccess), findsOneWidget, reason: 'success is shown as text + tick, not only motion');
      expect(find.byIcon(Icons.check), findsOneWidget);
      // a second drag while the success state is shown cannot call again
      await tester.drag(_thumb, const Offset(-50, 0));
      await tester.pump();
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 700));
      expect(done, 1);
    });

    testWidgets('released before the end: springs back, nothing is called', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
            label: R6.sliderStart,
            successLabel: R6.startedSuccess,
            onConfirm: () async {
              calls++;
              return null;
            },
          )));
      final before = tester.getTopLeft(_thumb).dx;
      final g = await tester.startGesture(tester.getCenter(_thumb));
      await g.moveBy(const Offset(40, 0));
      await g.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(tester.getTopLeft(_thumb).dx, greaterThan(before + 60));
      await g.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_thumb).dx, before);
      expect(calls, 0);
    });

    testWidgets('a plain tap does nothing except show a written hint', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
            label: R6.sliderStart,
            successLabel: R6.startedSuccess,
            onConfirm: () async {
              calls++;
              return null;
            },
          )));
      await tester.tap(find.byKey(const Key('slider-label')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 0);
      expect(find.text(R6.sliderTapHint), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text(R6.sliderTapHint), findsNothing, reason: 'hint goes away after 3 s');
    });

    testWidgets('busy lock: while the call is running no second call can start', (tester) async {
      final c = Completer<String?>();
      var calls = 0;
      await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
            label: R6.sliderArriveDest,
            successLabel: R6.arrivedDest,
            onConfirm: () {
              calls++;
              return c.future;
            },
          )));
      await _drag(tester, 900);
      expect(calls, 1);
      expect(find.text(R6.sliderSubmitting), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.drag(_thumb, const Offset(-30, 0));
      await tester.pump();
      await tester.drag(_thumb, const Offset(900, 0));
      await tester.pump();
      // the long-press path is locked too
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('slider-label'))));
      await tester.pump(const Duration(seconds: 2));
      await g.up();
      await tester.pump();
      expect(calls, 1);
      c.complete(null);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('failure: back to idle with a Thai message (alert) and it can be tried again', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
            label: R6.sliderBoard,
            successLabel: R6.boardedSuccess,
            onConfirm: () async => ++calls == 1 ? 'ยืนยันไม่สำเร็จ ลองอีกครั้ง' : null,
          )));
      final rest = tester.getTopLeft(_thumb).dx;
      await _drag(tester, 900);
      await tester.pumpAndSettle();
      expect(find.text('ยืนยันไม่สำเร็จ ลองอีกครั้ง'), findsOneWidget);
      expect(find.text(R6.sliderRetryHint), findsOneWidget);
      expect(find.text(R6.sliderBoard), findsOneWidget, reason: 'idle again');
      expect(tester.getTopLeft(_thumb).dx, rest);
      await _drag(tester, 900);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, 2);
      expect(find.text('ยืนยันไม่สำเร็จ ลองอีกครั้ง'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a flow the user backed out of resets quietly (no message)', (tester) async {
      await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
            label: R6.sliderStart,
            successLabel: R6.startedSuccess,
            onConfirm: () async => sliderCancelled,
          )));
      await _drag(tester, 900);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slider-error')), findsNothing);
      expect(find.text(R6.sliderStart), findsOneWidget);
    });

    testWidgets('disabled: visible reason, lock icon, drag / hold / semantics do nothing', (tester) async {
      var calls = 0;
      final h = tester.ensureSemantics();
      await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
            label: R6.sliderBoard,
            successLabel: R6.boardedSuccess,
            disabledReason: 'รอคนขับเริ่มเดินทางก่อน',
            onConfirm: () async {
              calls++;
              return null;
            },
          )));
      expect(find.text('รอคนขับเริ่มเดินทางก่อน'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      await _drag(tester, 900);
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('slider-label'))));
      await tester.pump(const Duration(seconds: 2));
      await g.up();
      expect(calls, 0);
      final node = tester.getSemantics(find.text(R6.sliderBoard));
      expect(node, isSemantics(hasEnabledState: true, isEnabled: false, isButton: true));
      expect(node.value, contains('รอคนขับเริ่มเดินทางก่อน'));
      h.dispose();
    });

    group('accessible alternatives', () {
      testWidgets('press and hold for 1.5 s confirms; releasing earlier does not', (tester) async {
        var calls = 0;
        await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
              label: R6.sliderBoard,
              successLabel: R6.boardedSuccess,
              onConfirm: () async {
                calls++;
                return null;
              },
            )));
        final c = tester.getCenter(find.byKey(const Key('slider-label')));
        var g = await tester.startGesture(c);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(R6.sliderHoldingLabel), findsOneWidget, reason: 'progress is shown in text');
        await tester.pump(const Duration(milliseconds: 900));
        await g.up();
        await tester.pump();
        expect(calls, 0, reason: 'released at ~1.1 s');
        expect(find.text(R6.sliderBoard), findsOneWidget);

        g = await tester.startGesture(c);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 1600));
        await g.up();
        await tester.pump(const Duration(milliseconds: 100));
        expect(calls, 1);
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('screen reader: one label, hint, "ready" value, a custom action; confirming shows no dialog',
          (tester) async {
        var calls = 0;
        final h = tester.ensureSemantics();
        await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
              label: R6.sliderBoard,
              successLabel: R6.boardedSuccess,
              successSemanticsLabel: R6.boardedSuccessSemantics,
              onConfirm: () async {
                calls++;
                return null;
              },
            )));
        final node = tester.getSemantics(find.text(R6.sliderBoard));
        expect(node.label, R6.sliderBoard);
        expect(node.hint, R6.sliderSemanticsHint);
        expect(node.value, R6.sliderValueReady);
        expect(node, isSemantics(isButton: true));
        final actionId = CustomSemanticsAction.getIdentifier(CustomSemanticsAction(label: R6.sliderActionName(R6.sliderBoard)));
        expect(node.getSemanticsData().customSemanticsActionIds, contains(actionId));

        // custom action from the actions menu
        node.owner!.performAction(node.id, SemanticsAction.customAction, actionId);
        await tester.pump(const Duration(milliseconds: 100));
        expect(calls, 1);
        expect(find.byType(AlertDialog), findsNothing);
        // success is announced with the emoji-free sentence
        expect(find.bySemanticsLabel(R6.boardedSuccessSemantics), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        h.dispose();
      });

      testWidgets('screen reader: activate (double tap) confirms once', (tester) async {
        var calls = 0;
        final h = tester.ensureSemantics();
        await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
              label: R6.sliderStart,
              successLabel: R6.startedSuccess,
              onConfirm: () async {
                calls++;
                return null;
              },
            )));
        final node = tester.getSemantics(find.text(R6.sliderStart));
        node.owner!.performAction(node.id, SemanticsAction.tap);
        node.owner!.performAction(node.id, SemanticsAction.tap); // a second activation while busy is ignored
        await tester.pump(const Duration(milliseconds: 100));
        expect(calls, 1);
        await tester.pump(const Duration(seconds: 1));
        h.dispose();
      });

      testWidgets('keyboard: Enter on the focused slider confirms', (tester) async {
        var calls = 0;
        await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
              label: R6.sliderStart,
              successLabel: R6.startedSuccess,
              onConfirm: () async {
                calls++;
                return null;
              },
            )));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 100));
        expect(calls, 1);
        await tester.pump(const Duration(seconds: 1));
      });
    });

    testWidgets('near mode: text + icon + semantics value "ใกล้ถึงแล้ว" (not colour only); never disables', (tester) async {
      final h = tester.ensureSemantics();
      var calls = 0;
      await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
            label: R6.sliderArriveDest,
            successLabel: R6.arrivedDest,
            near: true,
            onConfirm: () async {
              calls++;
              return null;
            },
          )));
      expect(find.text(R6.sliderNearDest), findsOneWidget);
      expect(find.byIcon(Icons.where_to_vote_outlined), findsOneWidget);
      final node = tester.getSemantics(find.text(R6.sliderArriveDest));
      expect(node.value, R6.sliderNearDest);
      await _drag(tester, 900);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      h.dispose();
    });

    testWidgets('reduce motion: no bounce animation, state still conveyed by text; drag still works', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(
        reduceMotion: true,
        () => SwipeToConfirmSlider(
          label: R6.sliderBoard,
          successLabel: R6.boardedSuccess,
          onConfirm: () async {
            calls++;
            return null;
          },
        ),
      ));
      final before = tester.getTopLeft(_thumb).dx;
      final g = await tester.startGesture(tester.getCenter(_thumb));
      await g.moveBy(const Offset(100, 0));
      await tester.pump();
      await g.up();
      await tester.pump(); // one frame: already back, no 200 ms animation
      expect(tester.getTopLeft(_thumb).dx, before);
      await _drag(tester, 900);
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, 1);
      expect(find.text(R6.boardedSuccess), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('text scale 2.0 and a 288 dp track: the label grows the track and is never clipped', (tester) async {
      await tester.pumpWidget(_app(
        textScale: 2.0,
        width: 288,
        () => SwipeToConfirmSlider(
          label: R6.sliderArriveHome,
          successLabel: R6.arrivedHome,
          near: true,
          onConfirm: () async => null,
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(AnimatedContainer)).height, greaterThanOrEqualTo(64));
      expect(tester.getSize(_thumb), const Size(56, 56), reason: 'the thumb does not grow with the text');
    });

    testWidgets('the help caption is shown for Half/Full and can be hidden for Collapsed', (tester) async {
      await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
            label: R6.sliderStart,
            successLabel: R6.startedSuccess,
            onConfirm: () async => null,
          )));
      expect(find.text(R6.sliderHelp), findsOneWidget);
      await tester.pumpWidget(_app(() => SwipeToConfirmSlider(
            label: R6.sliderStart,
            successLabel: R6.startedSuccess,
            showHelp: false,
            onConfirm: () async => null,
          )));
      expect(find.text(R6.sliderHelp), findsNothing);
    });
  });
}
