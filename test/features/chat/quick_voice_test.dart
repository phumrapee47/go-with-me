import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/chat/domain/quick_voice.dart';

void main() {
  group('QuickVoicePresets', () {
    test('fixed allow-list (US-48 AC)', () {
      expect(QuickVoicePresets.phrases, [
        'ถึงจุดนัดรับแล้ว',
        'ขอโทษที่มาช้านิดนึง',
        'รอสักครู่นะ',
        'เดี๋ยวถึงแล้ว',
      ]);
    });

    test('isPreset matches exactly (trims whitespace)', () {
      expect(QuickVoicePresets.isPreset('ถึงจุดนัดรับแล้ว'), isTrue);
      expect(QuickVoicePresets.isPreset('  ถึงจุดนัดรับแล้ว  '), isTrue);
      expect(QuickVoicePresets.isPreset('ถึงจุดนัดรับแล้วนะ'), isFalse);
      expect(QuickVoicePresets.isPreset('สวัสดี'), isFalse);
    });
  });

  group('QuickVoiceThrottle (Q16: 1 per 10s per match)', () {
    test('first send always allowed, second within the window is blocked', () {
      var now = DateTime(2026, 1, 1, 12);
      final t = QuickVoiceThrottle(clock: () => now);
      expect(t.canSend('m1'), isTrue);
      t.recordSent('m1');
      expect(t.canSend('m1'), isFalse);
      now = now.add(const Duration(seconds: 5));
      expect(t.canSend('m1'), isFalse);
      now = now.add(const Duration(seconds: 5));
      expect(t.canSend('m1'), isTrue);
    });

    test('throttle is per-match: another match is unaffected', () {
      final now = DateTime(2026, 1, 1, 12);
      final t = QuickVoiceThrottle(clock: () => now);
      t.recordSent('m1');
      expect(t.canSend('m1'), isFalse);
      expect(t.canSend('m2'), isTrue);
    });

    test('retryAfter counts down to zero', () {
      var now = DateTime(2026, 1, 1, 12);
      final t = QuickVoiceThrottle(clock: () => now);
      expect(t.retryAfter('m1'), Duration.zero);
      t.recordSent('m1');
      expect(t.retryAfter('m1'), const Duration(seconds: 10));
      now = now.add(const Duration(seconds: 4));
      expect(t.retryAfter('m1'), const Duration(seconds: 6));
      now = now.add(const Duration(seconds: 10));
      expect(t.retryAfter('m1'), Duration.zero);
    });
  });
}
