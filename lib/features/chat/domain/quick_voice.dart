import '../../../core/net/throttle.dart';

/// US-48(B) (round 7): "วลีสำเร็จรูปพูดด้วยเสียง" — a FIXED allow-list, reusing the
/// existing quick-reply pattern (US-8/US-24/US-47). Sending is just a normal
/// chat message (no new backend, no `kind` column needed); the receiving
/// device recognises the exact text against this same list and reads it
/// aloud via on-device TTS (see `QuickVoiceTtsService`). This is fully
/// separate from US-48(A) recorded audio clips: no file, no upload, no bucket.
abstract final class QuickVoicePresets {
  static const phrases = <String>[
    'ถึงจุดนัดรับแล้ว',
    'ขอโทษที่มาช้านิดนึง',
    'รอสักครู่นะ',
    'เดี๋ยวถึงแล้ว',
  ];

  static bool isPreset(String body) => phrases.contains(body.trim());
}

/// Q16 (PM decision): 1 quick-voice send per 10s per match — same shape as the
/// existing chat `SendThrottle`, kept separate because it gates a DIFFERENT
/// action (opening/using the quick-voice sheet), not the general chat send box.
class QuickVoiceThrottle {
  QuickVoiceThrottle({this.window = const Duration(seconds: 10), Clock? clock}) : _clock = clock ?? DateTime.now;

  final Duration window;
  final Clock _clock;
  final _lastSentByMatch = <String, DateTime>{};

  bool canSend(String matchId) {
    final last = _lastSentByMatch[matchId];
    if (last == null) return true;
    return _clock().difference(last) >= window;
  }

  void recordSent(String matchId) => _lastSentByMatch[matchId] = _clock();

  Duration retryAfter(String matchId) {
    final last = _lastSentByMatch[matchId];
    if (last == null) return Duration.zero;
    final elapsed = _clock().difference(last);
    return elapsed >= window ? Duration.zero : window - elapsed;
  }
}
