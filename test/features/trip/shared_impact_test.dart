import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/chat/domain/thank_you_sticker.dart';
import 'package:gowithme/features/chat/presentation/chat_providers.dart';
import 'package:gowithme/features/trip/domain/shared_impact.dart';
import 'package:gowithme/features/trip/presentation/ride_widgets.dart';

import '../../support/fake_repos_p4.dart';

void main() {
  group('co2KgFor / formatCo2Kg (US-47)', () {
    test('formula: distance_km * 0.120', () {
      expect(co2KgFor(10000), closeTo(1.2, 1e-9));
      expect(co2KgFor(5000), closeTo(0.6, 1e-9));
    });

    test('hides the number (null) when distance is 0 or negative', () {
      expect(co2KgFor(0), isNull);
      expect(co2KgFor(-5), isNull);
    });

    test('formatCo2Kg renders one decimal with a leading tilde', () {
      expect(formatCo2Kg(1.2), '~1.2 kg');
      expect(formatCo2Kg(0.6), '~0.6 kg');
    });
  });

  group('SharedImpactCard', () {
    testWidgets('shows the friend name, CO2 value, "(โดยประมาณ)" label and a disclaimer footnote',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SharedImpactCard(partnerName: 'ต้นไม้', co2Kg: 1.2)),
      ));
      expect(find.textContaining('ต้นไม้'), findsOneWidget);
      expect(find.textContaining('~1.2 kg'), findsOneWidget);
      expect(find.byKey(const Key('shared-impact-approx')), findsOneWidget);
      expect(find.text('(โดยประมาณ)'), findsOneWidget);
      expect(find.byKey(const Key('shared-impact-disclaimer')), findsOneWidget);
    });
  });

  group('ThankYouStickerRow (US-47: reuses the existing chat quick-reply send path)', () {
    testWidgets('shows every allow-list preset; tapping one sends it through ChatRepository.send (no new kind)',
        (tester) async {
      final chat = FakeChatRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [chatRepositoryProvider.overrideWithValue(chat)],
        child: const MaterialApp(home: Scaffold(body: ThankYouStickerRow(matchId: 'demo-match-accepted'))),
      ));
      for (final t in ThankYouStickerPresets.messages) {
        expect(find.text(t), findsOneWidget);
      }
      await tester.tap(find.text(ThankYouStickerPresets.messages.first));
      await tester.pumpAndSettle();
      expect(chat.sendCalls, 1);
      expect(chat.sent.single.$1, 'demo-match-accepted');
      expect(chat.sent.single.$2, ThankYouStickerPresets.messages.first);
      // Sent sticker shows a check mark (no free-text entry anywhere on this row).
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
