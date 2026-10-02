import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/map/app_map.dart';
import '../../geo/presentation/geo_providers.dart';
import '../../trip/presentation/trip_providers.dart';

/// Drives the mascot rain-mode banner. Uses the active trip's origin when
/// there is one, else the app's default map center — never asks for a fresh
/// GPS fix here (decorative only, must never risk the location-timeout ANR).
final isRainingProvider = FutureProvider.autoDispose<bool>((ref) async {
  final trip = ref.watch(activeTripProvider).valueOrNull;
  final point = trip?.origin ?? defaultMapCenter;
  return ref.watch(weatherServiceProvider).isRainingAt(point);
});
