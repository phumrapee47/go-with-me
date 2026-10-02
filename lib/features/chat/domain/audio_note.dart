/// US-48(A) (round 7): recorded voice clips. The private storage bucket +
/// purge-queue extension this depends on have NOT been designed/applied yet
/// (that is a separate /db-architect task — see docs/dev-notes.md "Round 7
/// stage B"). This flag keeps the whole upload/playback path visibly
/// "ยังไม่เปิดใช้งาน" (not-yet-enabled) instead of silently failing a network call.
///
/// The UI/permission-copy/hold-to-record/duration-cap/state-machine below are
/// still fully built and tested; only the final upload call is gated.
const audioNoteUploadEnabled = false;

/// Hard cap per the AC (US-48 A): hold-to-record stops automatically at 10s.
const audioNoteMaxDuration = Duration(seconds: 10);

enum AudioNoteState {
  /// Nothing recorded yet; mic permission not asked this session.
  idle,

  /// The Thai mic-permission explainer is showing (first use only).
  explainingPermission,

  /// Actively recording (hold-to-record button is down).
  recording,

  /// Recording finished (released early or hit the 10s cap); ready to send/discard.
  recorded,

  /// [audioNoteUploadEnabled] is false: send is disabled with a clear notice.
  uploadDisabled,
}

/// Pure state machine for the hold-to-record button (design-spec-round7 US-48
/// AC: "ปล่อยนิ้วหรือครบ 10 วินาที = หยุดบันทึกอัตโนมัติ"). No platform mic access here —
/// a real recorder implementation plugs into [onStart]/[onStop] once the
/// bucket/RPC work lands; until then this only tracks elapsed time.
class AudioNoteController {
  AudioNoteController({this.maxDuration = audioNoteMaxDuration, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Duration maxDuration;
  final DateTime Function() _clock;

  AudioNoteState _state = AudioNoteState.idle;
  DateTime? _startedAt;
  Duration _recordedDuration = Duration.zero;
  bool _permissionExplained = false;

  AudioNoteState get state => _state;
  Duration get recordedDuration => _recordedDuration;

  /// Elapsed time while [state] is recording (clamped to [maxDuration]).
  Duration elapsedWhileRecording() {
    final started = _startedAt;
    if (_state != AudioNoteState.recording || started == null) return Duration.zero;
    final e = _clock().difference(started);
    return e > maxDuration ? maxDuration : e;
  }

  /// Call on the first hold-to-record attempt this session.
  bool needsPermissionExplainer() => !_permissionExplained;

  void acknowledgePermissionExplainer() => _permissionExplained = true;

  void startRecording() {
    if (_state == AudioNoteState.recording) return;
    _state = AudioNoteState.recording;
    _startedAt = _clock();
  }

  /// Called on release, or by a timer once [maxDuration] elapses.
  void stopRecording() {
    if (_state != AudioNoteState.recording) return;
    _recordedDuration = elapsedWhileRecording();
    _state = audioNoteUploadEnabled ? AudioNoteState.recorded : AudioNoteState.uploadDisabled;
    _startedAt = null;
  }

  void discard() {
    _state = AudioNoteState.idle;
    _recordedDuration = Duration.zero;
    _startedAt = null;
  }
}
