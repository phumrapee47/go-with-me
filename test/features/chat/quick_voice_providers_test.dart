import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/core/providers.dart';
import 'package:gowithme/features/chat/domain/chat_models.dart';
import 'package:gowithme/features/chat/presentation/quick_voice_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSpeaker implements TtsSpeaker {
  final spoken = <String>[];
  @override
  Future<void> speak(String text) async => spoken.add(text);
}

ChatMessage _msg(String body, {String? senderId, bool isSystem = false}) => ChatMessage(
      id: 'm1',
      matchId: 'match1',
      body: body,
      createdAt: DateTime(2026, 1, 1),
      senderId: senderId,
      isSystem: isSystem,
    );

final _testProvider = FutureProvider.family<void, ChatMessage>(
  (ref, m) => maybeSpeakQuickVoice(ref, m, selfUserId: 'me'),
);

ProviderContainer _makeContainer(_FakeSpeaker speaker, SharedPreferences prefs) => ProviderContainer(overrides: [
      ttsSpeakerProvider.overrideWithValue(speaker),
      sharedPrefsProvider.overrideWithValue(prefs),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('speaks a preset message sent by someone else when the setting is on (default)', () async {
    final speaker = _FakeSpeaker();
    final container = _makeContainer(speaker, prefs);
    addTearDown(container.dispose);

    await container.read(_testProvider(_msg('ถึงจุดนัดรับแล้ว', senderId: 'other')).future);
    expect(speaker.spoken, ['ถึงจุดนัดรับแล้ว']);
  });

  test('never speaks its own message', () async {
    final speaker = _FakeSpeaker();
    final container = _makeContainer(speaker, prefs);
    addTearDown(container.dispose);

    await container.read(_testProvider(_msg('ถึงจุดนัดรับแล้ว', senderId: 'me')).future);
    expect(speaker.spoken, isEmpty);
  });

  test('never speaks a non-preset message', () async {
    final speaker = _FakeSpeaker();
    final container = _makeContainer(speaker, prefs);
    addTearDown(container.dispose);

    await container.read(_testProvider(_msg('สวัสดีจ้า', senderId: 'other')).future);
    expect(speaker.spoken, isEmpty);
  });

  test('respects the off setting', () async {
    final speaker = _FakeSpeaker();
    final container = _makeContainer(speaker, prefs);
    addTearDown(container.dispose);
    container.read(quickVoiceTtsEnabledProvider.notifier).state = false;

    await container.read(_testProvider(_msg('เดี๋ยวถึงแล้ว', senderId: 'other')).future);
    expect(speaker.spoken, isEmpty);
  });

  test('never speaks a system message', () async {
    final speaker = _FakeSpeaker();
    final container = _makeContainer(speaker, prefs);
    addTearDown(container.dispose);

    await container.read(_testProvider(_msg('system.trip_completed', senderId: 'other', isSystem: true)).future);
    expect(speaker.spoken, isEmpty);
  });
}
