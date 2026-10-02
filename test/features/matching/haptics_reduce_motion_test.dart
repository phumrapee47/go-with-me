import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/widgets/swipe_to_confirm_slider.dart';
import 'package:gowithme/features/matching/presentation/commute_card_deck.dart';

/// US-47 (round 7 Stage C): haptics must respect the OS reduce-motion/haptics accessibility setting
/// (the SAME `MediaQuery.disableAnimationsOf` hook the app already uses for reduce-motion elsewhere —
/// see `SwipeToConfirmSlider`/`DeckSwipeCard`'s existing `_reduce` getters). These tests intercept the
/// platform channel HapticFeedback actually calls, so they check the real behaviour is gated, not
/// just that the setting is read somewhere.
void main() {
  late List<String> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments as String? ?? '');
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  Widget withReduceMotion({required bool reduce, required Widget child}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduce),
          child: Scaffold(body: Center(child: child)),
        ),
      );

  group('DeckSwipeCard: light selection haptic on drag start', () {
    Widget card() => SizedBox(
          width: 300,
          height: 300,
          child: DeckSwipeCard(
            cardKey: const Key('card'),
            onSkip: () {},
            onInvite: () {},
            canInvite: () => true,
            child: Container(color: Colors.blue),
          ),
        );

    testWidgets('normal motion: dragging the card fires a haptic', (tester) async {
      await tester.pumpWidget(withReduceMotion(reduce: false, child: card()));
      await tester.drag(find.byKey(const Key('card')), const Offset(40, 0));
      await tester.pump();
      expect(calls, isNotEmpty);
    });

    testWidgets('reduce-motion: dragging the card fires NO haptic', (tester) async {
      await tester.pumpWidget(withReduceMotion(reduce: true, child: card()));
      await tester.drag(find.byKey(const Key('card')), const Offset(40, 0));
      await tester.pump();
      expect(calls, isEmpty);
    });
  });

  group('SwipeToConfirmSlider: heavy impact at the 95% confirm threshold', () {
    Widget slider() => SizedBox(
          width: 300,
          child: SwipeToConfirmSlider(
            key: const Key('s'),
            label: 'สไลด์เพื่อยืนยัน',
            successLabel: 'สำเร็จ',
            onConfirm: () async => null,
          ),
        );

    testWidgets('normal motion: dragging to the end fires haptics', (tester) async {
      await tester.pumpWidget(withReduceMotion(reduce: false, child: slider()));
      await tester.drag(find.byKey(const Key('slider-thumb')), const Offset(900, 0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, isNotEmpty);
    });

    testWidgets('reduce-motion: dragging to the end fires NO haptics, but still confirms', (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(withReduceMotion(
        reduce: true,
        child: SizedBox(
          width: 300,
          child: SwipeToConfirmSlider(
            key: const Key('s'),
            label: 'สไลด์เพื่อยืนยัน',
            successLabel: 'สำเร็จ',
            onConfirm: () async {
              confirmed++;
              return null;
            },
          ),
        ),
      ));
      await tester.drag(find.byKey(const Key('slider-thumb')), const Offset(900, 0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, isEmpty, reason: 'reduce-motion must also disable haptics, not just animation');
      expect(confirmed, 1, reason: 'the confirm action itself still works');
    });
  });
}
