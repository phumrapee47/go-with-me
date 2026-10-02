import 'package:flutter/material.dart';

import '../models/mascot_loop.dart';

/// Plays [MascotLoop.idleBreathing]'s frames back-and-forth to give the idle
/// pose a subtle breathing motion. Kept separate from [MascotWidget]'s
/// AnimatedSwitcher (which only cross-fades between discrete poses) since
/// this drives its own ticker continuously while mounted.
class MascotBreathingLoop extends StatefulWidget {
  const MascotBreathingLoop({super.key, this.size = 96});

  final double size;

  @override
  State<MascotBreathingLoop> createState() => _MascotBreathingLoopState();
}

class _MascotBreathingLoopState extends State<MascotBreathingLoop> with SingleTickerProviderStateMixin {
  static final _frames = MascotLoop.idleBreathing.frames;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final index = (_controller.value * (_frames.length - 1)).round();
        return Image.asset(
          _frames[index],
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        );
      },
    );
  }
}
