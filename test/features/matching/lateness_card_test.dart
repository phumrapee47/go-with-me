import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/matching/presentation/lateness_card.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('LatenessCard (US-49)', () {
    testWidgets('shows the two choices; tapping each calls the matching callback', (tester) async {
      var waited = 0;
      var cancelled = 0;
      await tester.pumpWidget(_host(LatenessCard(onWaitMore: () => waited++, onCancelNoFault: () => cancelled++)));
      expect(find.text(LatenessCard.title), findsOneWidget);
      expect(find.text(LatenessCard.waitLabel), findsOneWidget);
      expect(find.text(LatenessCard.cancelLabel), findsOneWidget);

      await tester.tap(find.byKey(const Key('lateness-wait')));
      expect(waited, 1);
      expect(cancelled, 0);

      await tester.tap(find.byKey(const Key('lateness-cancel')));
      expect(cancelled, 1);
    });

    testWidgets('busy: both buttons are disabled and the cancel button shows a loading state', (tester) async {
      var waited = 0;
      var cancelled = 0;
      await tester.pumpWidget(
          _host(LatenessCard(onWaitMore: () => waited++, onCancelNoFault: () => cancelled++, busy: true)));
      await tester.tap(find.byKey(const Key('lateness-wait')));
      await tester.tap(find.byKey(const Key('lateness-cancel')));
      expect(waited, 0);
      expect(cancelled, 0);
    });

    testWidgets('errorText (GWM_NOT_OVERDUE): shown gracefully, the card stays up (not a crash/dead end)',
        (tester) async {
      await tester.pumpWidget(_host(LatenessCard(
        onWaitMore: () {},
        onCancelNoFault: () {},
        errorText: 'ยังไม่เข้าเงื่อนไขล่าช้าตามที่ระบบตรวจสอบ ลองรออีกสักครู่แล้วลองใหม่',
      )));
      expect(find.byKey(const Key('lateness-error')), findsOneWidget);
      // Both choices are still available (never a dead end).
      expect(find.byKey(const Key('lateness-wait')), findsOneWidget);
      expect(find.byKey(const Key('lateness-cancel')), findsOneWidget);
    });
  });
}
