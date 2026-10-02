import 'package:flutter_test/flutter_test.dart';
import 'package:gowithme/features/chat/domain/audio_note.dart';

void main() {
  test('upload is gated off this round (no bucket/RPC yet)', () {
    // Documents the intentional gate from dev-notes: flip only after the
    // private audio bucket + purge-queue extension are designed/applied.
    expect(audioNoteUploadEnabled, isFalse);
  });

  group('AudioNoteController', () {
    test('starts idle and needs the permission explainer once', () {
      final c = AudioNoteController();
      expect(c.state, AudioNoteState.idle);
      expect(c.needsPermissionExplainer(), isTrue);
      c.acknowledgePermissionExplainer();
      expect(c.needsPermissionExplainer(), isFalse);
    });

    test('recording tracks elapsed time and clamps to the 10s cap', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final c = AudioNoteController(clock: () => now);
      c.startRecording();
      expect(c.state, AudioNoteState.recording);
      now = now.add(const Duration(seconds: 4));
      expect(c.elapsedWhileRecording(), const Duration(seconds: 4));
      now = now.add(const Duration(seconds: 20));
      // Never reports more than the 10s cap even if stop() is late.
      expect(c.elapsedWhileRecording(), audioNoteMaxDuration);
    });

    test('stopRecording ends in uploadDisabled while the feature flag is off', () {
      var now = DateTime(2026, 1, 1, 12);
      final c = AudioNoteController(clock: () => now);
      c.startRecording();
      now = now.add(const Duration(seconds: 3));
      c.stopRecording();
      expect(c.state, AudioNoteState.uploadDisabled);
      expect(c.recordedDuration, const Duration(seconds: 3));
    });

    test('discard resets to idle', () {
      final c = AudioNoteController();
      c.startRecording();
      c.stopRecording();
      c.discard();
      expect(c.state, AudioNoteState.idle);
      expect(c.recordedDuration, Duration.zero);
    });

    test('elapsedWhileRecording is zero outside the recording state', () {
      final c = AudioNoteController();
      expect(c.elapsedWhileRecording(), Duration.zero);
    });
  });
}
