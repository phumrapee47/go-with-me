import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/mascot_controller.dart';
import '../models/mascot_state.dart';
import '../services/mascot_animation_service.dart';
import 'mascot_widget.dart';

/// Home screen entry: waves hello for a moment, then settles into the
/// breathing idle loop. Drives the shared [mascotControllerProvider], so any
/// other [MascotWidget] on screen follows along.
class MascotGreeting extends ConsumerStatefulWidget {
  const MascotGreeting({super.key, this.size = 64});

  final double size;

  @override
  ConsumerState<MascotGreeting> createState() => _MascotGreetingState();
}

class _MascotGreetingState extends ConsumerState<MascotGreeting> {
  static const _animationService = MascotAnimationService();

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_animationService.precacheAll(context));
      ref.read(mascotControllerProvider.notifier).show(MascotState.hello);
      _timer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) ref.read(mascotControllerProvider.notifier).show(MascotState.idle);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MascotWidget(size: widget.size);
}
