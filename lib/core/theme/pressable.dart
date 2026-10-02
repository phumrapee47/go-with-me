import 'package:flutter/material.dart';

/// Soft-depth press feedback (scale 0.97 + shadow compress) for tappable cards that
/// aren't already a Material button — e.g. a whole `Card` acting as a nav target.
/// Duration/curve match `MascotAnimationConfig.stateTransition` (280ms) so press and
/// mascot motion feel like one rhythm.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.onTap, required this.child, this.longPress});

  final VoidCallback? onTap;
  final VoidCallback? longPress;
  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap == null && widget.longPress == null) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.longPress,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
