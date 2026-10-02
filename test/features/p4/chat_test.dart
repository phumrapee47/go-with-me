import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/l10n/strings.dart';
import 'package:gowithme/core/l10n/strings_p4.dart';
import 'package:gowithme/core/router/redirect.dart';
import 'package:gowithme/features/chat/domain/chat_models.dart';
import 'package:gowithme/features/safety/domain/safety_models.dart';

import '../../support/fakes.dart';
import '../../support/p4_helpers.dart';

ChatMessage _partnerMsg(String body, {DateTime? at, String id = 'p1'}) => ChatMessage(
      id: id,
      matchId: 'm1',
      body: body,
      createdAt: at ?? DateTime.now().subtract(const Duration(minutes: 1)),
      senderId: 'partner-1',
    );

Fakes _fakes() => Fakes()
  ..trips.active = runningTrip()
  ..matches.matches = [acceptedMatch()];

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Future<void> _tapSend(WidgetTester tester) async {
  await tester.tap(find.byTooltip(P.chatSend));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows history, sends with a client id, reconciles with the server row', (tester) async {
    final f = _fakes();
    f.chat.messages.add(_partnerMsg('สวัสดี'));
    await openApp(tester, f);
    await goTo(tester, Routes.chat('m1'));

    expect(find.text('สวัสดี'), findsOneWidget);
    expect(find.text(P.chatNotice), findsOneWidget);

    await _type(tester, 'ออกแล้วนะ');
    await _tapSend(tester);
    expect(find.text('ออกแล้วนะ'), findsOneWidget, reason: 'single bubble after reconcile');
    expect(f.chat.sent.single.$2, 'ออกแล้วนะ');
    expect(f.chat.sent.single.$3, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('failed send shows retry; retry reuses the same client id and never duplicates', (tester) async {
    final f = _fakes();
    await openApp(tester, f);
    await goTo(tester, Routes.chat('m1'));

    f.chat.sendFailure = const AppFailure(FailureCode.networkOffline, retryable: true);
    await _type(tester, 'ลองส่ง');
    await _tapSend(tester);
    expect(find.text(P.chatSendFailed), findsOneWidget);

    f.chat.sendFailure = null;
    await tester.tap(find.text(P.chatSendFailed));
    await tester.pumpAndSettle();

    expect(find.text(P.chatSendFailed), findsNothing);
    expect(find.text('ลองส่ง'), findsOneWidget);
    expect(f.chat.sent, hasLength(2));
    expect(f.chat.sent[0].$3, f.chat.sent[1].$3, reason: 'same client_msg_id');
    expect(f.chat.messages, hasLength(1), reason: 'the server stored it once');
  });

  testWidgets('send throttle: the 9th quick message is held back and the text is kept', (tester) async {
    final f = _fakes();
    await openApp(tester, f);
    await goTo(tester, Routes.chat('m1'));

    for (var i = 0; i < 8; i++) {
      await _type(tester, 'ข้อความ $i');
      await tester.tap(find.byTooltip(P.chatSend));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(f.chat.sendCalls, 8);

    await _type(tester, 'ข้อความที่เก้า');
    await tester.tap(find.byTooltip(P.chatSend));
    await tester.pumpAndSettle();
    expect(f.chat.sendCalls, 8, reason: 'not sent');
    expect(find.text(P.chatThrottled), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'ข้อความที่เก้า');
  });

  testWidgets('over 1000 characters: counter shows and send is disabled', (tester) async {
    final f = _fakes();
    await openApp(tester, f);
    await goTo(tester, Routes.chat('m1'));
    await _type(tester, 'ก' * 1005);
    expect(find.text('1005/1000'), findsOneWidget);
    final btn = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));
    expect(btn.onPressed, isNull);
  });

  for (final (state, banner) in [
    (ChatState.tripEnded, P.chatReadOnlyTripEnded),
    (ChatState.blocked, P.chatReadOnlyBlocked),
    (ChatState.matchClosed, P.chatReadOnlyClosed),
  ]) {
    testWidgets('chat_state $state turns the composer into a read-only banner', (tester) async {
      final f = _fakes();
      f.chat
        ..chatState = state
        ..messages.add(_partnerMsg('ข้อความเก่า'));
      await openApp(tester, f);
      await goTo(tester, Routes.chat('m1'));
      expect(find.text(banner), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('ข้อความเก่า'), findsOneWidget, reason: 'history stays readable');
    });
  }

  testWidgets('a system message from the server flips an open room to read-only', (tester) async {
    final f = _fakes();
    await openApp(tester, f);
    await goTo(tester, Routes.chat('m1'));
    expect(find.byType(TextField), findsOneWidget);

    f.chat.chatState = ChatState.tripEnded;
    f.chat.push(ChatMessage(
      id: 'sys1',
      matchId: 'm1',
      body: 'system.trip_cancelled',
      createdAt: DateTime.now(),
      isSystem: true,
    ));
    await tester.pumpAndSettle();
    expect(find.text(P.sysTripCancelled), findsOneWidget);
    expect(find.text(P.chatReadOnlyTripEnded), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('an RLS rejection on send re-reads chat_state and shows read-only', (tester) async {
    final f = _fakes();
    await openApp(tester, f);
    await goTo(tester, Routes.chat('m1'));

    f.chat
      ..sendFailure = const AppFailure(FailureCode.forbiddenRls)
      ..chatState = ChatState.tripEnded;
    await _type(tester, 'ทันไหม');
    await _tapSend(tester);
    expect(find.text(P.chatReadOnlyTripEnded), findsOneWidget);
  });

  testWidgets('realtime: a partner message appears without a refresh', (tester) async {
    final f = _fakes();
    await openApp(tester, f);
    await goTo(tester, Routes.chat('m1'));
    f.chat.push(_partnerMsg('ถึงแล้ว', id: 'rt1', at: DateTime.now()));
    await tester.pumpAndSettle();
    expect(find.text('ถึงแล้ว'), findsOneWidget);
  });

  testWidgets('block from chat: confirm dialog, block saved, room becomes read-only', (tester) async {
    final f = _fakes();
    await openApp(tester, f);
    await goTo(tester, Routes.chat('m1'));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(P.chatMenuBlock));
    await tester.pumpAndSettle();
    expect(find.text(P.chatBlockTitle), findsOneWidget);

    f.chat.chatState = ChatState.blocked; // what chat_state returns after the block
    await tester.tap(find.text(P.chatBlockConfirm));
    await tester.pumpAndSettle();

    expect(f.safety.blockedIds, ['partner-1']);
    expect(find.text(P.chatReadOnlyBlocked), findsOneWidget);
  });

  testWidgets('declining the block dialog blocks nobody', (tester) async {
    final f = _fakes();
    await openApp(tester, f);
    await goTo(tester, Routes.chat('m1'));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(P.chatMenuBlock));
    await tester.pumpAndSettle();
    await tester.tap(find.text(P.chatBlockKeep));
    await tester.pumpAndSettle();
    expect(f.safety.blockedIds, isEmpty);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('report from chat: pick a reason, optionally block, submit', (tester) async {
    final f = _fakes();
    await openApp(tester, f);
    await goTo(tester, Routes.chat('m1'));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(P.chatMenuReport));
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, P.reportSubmit);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull, reason: 'needs a reason');
    await tester.tap(find.text(P.reasonHarassment));
    await tester.pump();
    await tester.tap(find.text(P.reportAlsoBlock));
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(f.safety.reports.single.$1, 'partner-1');
    expect(f.safety.reports.single.$2, ReportReason.harassment);
    expect(f.safety.blockedIds, ['partner-1']);
    expect(find.text(P.reportThanks), findsOneWidget);
  });

  testWidgets('SOS is reachable from the chat app bar in one tap', (tester) async {
    final f = _fakes();
    await openApp(tester, f);
    await goTo(tester, Routes.chat('m1'));
    await tester.tap(find.text(P.sos));
    await tester.pumpAndSettle();
    expect(find.text(P.sosTitle), findsOneWidget);
  });

  group('unread dots', () {
    testWidgets('dot on the tab and the row until the room is opened', (tester) async {
      final f = _fakes();
      f.chat.messages.add(_partnerMsg('อ่านหน่อย'));
      await openApp(tester, f);

      // Bottom-nav badge on the chats tab.
      final visible = tester.widgetList<Badge>(find.byType(Badge)).where((b) => b.isLabelVisible);
      expect(visible, isNotEmpty);

      await tester.tap(find.text(S.tabChats));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unread-m1')), findsOneWidget);
      expect(find.text('อ่านหน่อย'), findsOneWidget, reason: 'last message preview');

      await tester.tap(find.text('นุ่น'));
      await tester.pumpAndSettle();
      await goBack(tester);
      expect(find.byKey(const Key('unread-m1')), findsNothing);
    });

    testWidgets('my own last message never lights the dot', (tester) async {
      final f = _fakes();
      f.chat.messages.add(ChatMessage(
        id: 'mine',
        matchId: 'm1',
        body: 'ของฉัน',
        createdAt: DateTime.now(),
        senderId: 'u1',
      ));
      await openApp(tester, f);
      await tester.tap(find.text(S.tabChats));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unread-m1')), findsNothing);
    });

    testWidgets('a realtime message while on the list lights the dot', (tester) async {
      final f = _fakes();
      await openApp(tester, f);
      await tester.tap(find.text(S.tabChats));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unread-m1')), findsNothing);
      f.chat.push(_partnerMsg('ใหม่', id: 'rt', at: DateTime.now()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unread-m1')), findsOneWidget);
    });
  });
}
