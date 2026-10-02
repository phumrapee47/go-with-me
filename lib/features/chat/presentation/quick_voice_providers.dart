import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart' as tts;

import '../../../core/providers.dart';
import '../domain/chat_models.dart';
import '../domain/quick_voice.dart';

const _prefsKey = 'gwm.quickVoiceTtsEnabled';

/// US-48(B): whether incoming quick-voice preset messages should be read
/// aloud automatically on THIS device. Default on (opt-out, matches the AC's
/// "ฝ่ายรับปิดการอ่านออกเสียงอัตโนมัติได้ในหน้าตั้งค่า" — off is the exception, not the rule).
class QuickVoiceTtsSetting extends Notifier<bool> {
  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_prefsKey) ?? true;

  Future<void> setEnabled(bool v) async {
    state = v;
    await ref.read(sharedPrefsProvider).setBool(_prefsKey, v);
  }
}

final quickVoiceTtsEnabledProvider = NotifierProvider<QuickVoiceTtsSetting, bool>(QuickVoiceTtsSetting.new);

/// Q16: 1 quick-voice SEND per 10s per match. Kept alive for the app session
/// (not per-screen) so leaving/reopening a chat room does not reset cooldown.
final quickVoiceThrottleProvider = Provider<QuickVoiceThrottle>((ref) => QuickVoiceThrottle());

/// Thin wrapper so tests can fake "speaking" without touching a real platform
/// TTS engine (none exists in the test/CI environment).
abstract class TtsSpeaker {
  Future<void> speak(String text);
}

class FlutterTtsSpeaker implements TtsSpeaker {
  FlutterTtsSpeaker() : _engine = tts.FlutterTts() {
    _engine.setLanguage('th-TH');
  }
  final tts.FlutterTts _engine;

  @override
  Future<void> speak(String text) async {
    try {
      await _engine.speak(text);
    } catch (_) {
      // Best-effort only (US-48B AC: TTS failure must fall back to the normal
      // chat message, which is already visible — never crash/block the chat).
    }
  }
}

final ttsSpeakerProvider = Provider<TtsSpeaker>((ref) => FlutterTtsSpeaker());

/// Speaks [message] iff: the setting is on, it is a recognised preset (US-48B
/// allow-list), and it was NOT sent by [selfUserId] (never read your own message aloud).
/// [ref] is a plain `Ref` (works from a `Notifier`'s `ref` or `WidgetRef`, both satisfy `Ref`'s API).
Future<void> maybeSpeakQuickVoice(
  Ref ref,
  ChatMessage message, {
  required String? selfUserId,
}) async {
  if (message.isSystem) return;
  if (message.senderId == null || message.senderId == selfUserId) return;
  if (!QuickVoicePresets.isPreset(message.body)) return;
  if (!ref.read(quickVoiceTtsEnabledProvider)) return;
  await ref.read(ttsSpeakerProvider).speak(message.body);
}
