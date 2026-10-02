import 'package:flutter/widgets.dart';

import '../models/mascot_loop.dart';
import '../models/mascot_state.dart';

/// Precaches mascot PNGs so the first AnimatedSwitcher transition (or loop
/// frame) never pops in blank. Call once (e.g. from the splash screen's first
/// frame).
class MascotAnimationService {
  const MascotAnimationService();

  Future<void> precacheAll(BuildContext context) async {
    for (final state in MascotState.values) {
      if (!context.mounted) return;
      await precacheImage(AssetImage(state.asset), context);
    }
    for (final loop in MascotLoop.values) {
      for (final frame in loop.frames) {
        if (!context.mounted) return;
        await precacheImage(AssetImage(frame), context);
      }
    }
  }

  Future<void> precache(BuildContext context, MascotState state) {
    return precacheImage(AssetImage(state.asset), context);
  }
}
