import 'package:flutter/animation.dart';

/// Timing/curve knobs for the PNG-based mascot transitions (AnimatedSwitcher
/// today; swap-in point for Rive later without touching call sites).
abstract final class MascotAnimationConfig {
  static const stateTransition = Duration(milliseconds: 280);
  static const curve = Curves.easeOutCubic;
}
