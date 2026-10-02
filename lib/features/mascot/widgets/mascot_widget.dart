import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../animations/mascot_animation_config.dart';
import '../controllers/mascot_controller.dart';
import '../models/mascot_state.dart';
import 'mascot_breathing_loop.dart';

/// Reusable mascot avatar. Reacts to [mascotControllerProvider] by default;
/// pass [state] to render a fixed pose instead (e.g. a static screenshot-safe
/// spot) without touching the shared controller.
///
/// PNG + AnimatedSwitcher today; the swap-in point for a Rive implementation
/// later — screens only ever depend on this widget, never on a pose's asset
/// path directly. [MascotState.idle] gets a looping breathing animation
/// ([MascotBreathingLoop]); every other pose is a single static frame.
class MascotWidget extends ConsumerWidget {
  const MascotWidget({super.key, this.state, this.size = 96});

  final MascotState? state;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MascotState current = state ?? ref.watch(mascotControllerProvider);
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedSwitcher(
        duration: MascotAnimationConfig.stateTransition,
        switchInCurve: MascotAnimationConfig.curve,
        switchOutCurve: MascotAnimationConfig.curve,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: current == MascotState.idle
            ? MascotBreathingLoop(key: ValueKey(current), size: size)
            : Image.asset(
                current.asset,
                key: ValueKey(current),
                width: size,
                height: size,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                semanticLabel: 'มาสคอต: ${current.name}',
              ),
      ),
    );
  }
}
