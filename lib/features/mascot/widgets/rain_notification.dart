import 'package:flutter/material.dart';

import 'rain_banner.dart';

/// Drops the [RainBanner] down from off-screen above, holds it for a beat,
/// then retracts it back up — a notification, not a fixture. Plays once per
/// mount; the caller controls when that happens (e.g. only while raining).
class RainNotification extends StatefulWidget {
  const RainNotification({super.key, this.width = 180, this.hold = const Duration(seconds: 3)});

  final double width;
  final Duration hold;

  @override
  State<RainNotification> createState() => _RainNotificationState();
}

class _RainNotificationState extends State<RainNotification> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _play();
  }

  Future<void> _play() async {
    await _controller.forward();
    await Future<void>.delayed(widget.hold);
    if (mounted) await _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
              .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic)),
          child: RainBanner(width: widget.width),
        ),
      ),
    );
  }
}
