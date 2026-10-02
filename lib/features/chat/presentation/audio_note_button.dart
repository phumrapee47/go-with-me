import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/tone.dart';
import '../domain/audio_note.dart';

/// US-48(A): hold-to-record button (design-spec-round7 US-48 AC: ">=56dp",
/// hold-to-record, <=10s auto-stop). The bucket/RPC this needs to actually
/// upload/play back does not exist yet (see `audioNoteUploadEnabled`), so this
/// always ends in a clear "ยังไม่เปิดใช้งาน" state rather than a silent failure.
class AudioNoteButton extends StatefulWidget {
  const AudioNoteButton({super.key});

  @override
  State<AudioNoteButton> createState() => _AudioNoteButtonState();
}

class _AudioNoteButtonState extends State<AudioNoteButton> {
  final _controller = AudioNoteController();
  Timer? _ticker;
  Timer? _autoStop;

  @override
  void dispose() {
    _ticker?.cancel();
    _autoStop?.cancel();
    super.dispose();
  }

  Future<void> _onHoldStart() async {
    if (_controller.needsPermissionExplainer()) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ขอสิทธิ์ใช้ไมโครโฟน'),
          content: const Text(
            'ใช้เพื่อบันทึกเสียงสั้นส่งให้เพื่อนร่วมทางเท่านั้น ไม่มีการแปลงเป็นข้อความหรือวิเคราะห์เนื้อหา '
            'ถ้าปฏิเสธ ยังใช้แอปได้ตามปกติ',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยังไม่อนุญาต')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('เข้าใจแล้ว')),
          ],
        ),
      );
      _controller.acknowledgePermissionExplainer();
      if (ok != true || !mounted) return;
    }
    setState(() => _controller.startRecording());
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => mounted ? setState(() {}) : null);
    _autoStop = Timer(audioNoteMaxDuration, _onHoldEnd);
  }

  void _onHoldEnd() {
    _ticker?.cancel();
    _autoStop?.cancel();
    if (mounted) setState(() => _controller.stopRecording());
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    if (state == AudioNoteState.uploadDisabled) {
      return Card(
        key: const Key('audio-note-disabled-banner'),
        color: context.tone.warningTint,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(children: [
            Icon(Icons.mic_off_outlined, color: context.tone.warningInk),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(child: Text('บันทึกเสียงยังไม่เปิดใช้งานในตอนนี้ (เร็ว ๆ นี้)')),
            TextButton(
              key: const Key('audio-note-discard-btn'),
              onPressed: () => setState(_controller.discard),
              child: const Text('ปิด'),
            ),
          ]),
        ),
      );
    }
    final recording = state == AudioNoteState.recording;
    final elapsed = _controller.elapsedWhileRecording();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (recording)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              key: const Key('audio-note-timer'),
              '${elapsed.inSeconds.toString().padLeft(2, '0')}s / ${audioNoteMaxDuration.inSeconds}s',
              semanticsLabel: 'กำลังบันทึกเสียง ${elapsed.inSeconds} จาก ${audioNoteMaxDuration.inSeconds} วินาที',
            ),
          ),
        Semantics(
          button: true,
          label: recording ? 'กำลังบันทึกเสียง ปล่อยเพื่อหยุด' : 'กดค้างเพื่อบันทึกเสียงสั้น',
          child: GestureDetector(
            key: const Key('audio-note-hold-btn'),
            onLongPressStart: (_) => _onHoldStart(),
            onLongPressEnd: (_) => _onHoldEnd(),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: recording ? context.tone.dangerInk : context.tone.primary,
              ),
              child: Icon(recording ? Icons.stop : Icons.mic, color: context.tone.onPrimary, size: 28),
            ),
          ),
        ),
      ],
    );
  }
}
