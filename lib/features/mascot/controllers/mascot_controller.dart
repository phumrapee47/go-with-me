import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mascot_state.dart';

/// Centralized mascot state so any screen can call
/// `ref.read(mascotControllerProvider.notifier).show(MascotState.happy)`
/// instead of each feature owning its own mascot logic.
class MascotController extends Notifier<MascotState> {
  @override
  MascotState build() => MascotState.idle;

  void show(MascotState next) => state = next;
}

final mascotControllerProvider = NotifierProvider<MascotController, MascotState>(
  MascotController.new,
);
