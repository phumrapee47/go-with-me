/// Short frame sequences played back-and-forth (ping-pong) to add subtle
/// motion to an otherwise-static [MascotState] pose. Frames are pre-rendered
/// PNGs under `assets/mascot/frames/{loop name}/` — same "never regenerate
/// the character ad hoc" rule as the discrete poses in mascot_state.dart.
enum MascotLoop {
  idleBreathing;

  /// frame_0 is always the pose's neutral/approved still (so this loop can
  /// start and end lined up with the static [MascotState.idle] asset).
  List<String> get frames => switch (this) {
        MascotLoop.idleBreathing => List.generate(
            4,
            (i) => 'assets/mascot/frames/idle_breathing/frame_$i.png',
          ),
      };
}
