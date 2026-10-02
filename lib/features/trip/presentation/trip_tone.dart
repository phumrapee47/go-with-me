import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tone.dart';
import '../../../core/theme/tone_scope.dart';
import '../../matching/presentation/matching_providers.dart';
import '../domain/trip.dart';
import 'trip_lifecycle_providers.dart';
import 'trip_providers.dart';

AppTone? toneOfTripRole(TripRole? r) => switch (r) {
      TripRole.driver => AppTone.driver,
      TripRole.rider => AppTone.rider,
      null => null,
    };

/// Trip-bound tone (design-spec D.2): the screen uses the tone of the TRIP's role, never the
/// active role, so switching mode elsewhere cannot make a trip page look like it changed role.
/// A trip without a role (walk/transit/taxi) keeps the app-level tone.
class TripRoleTone extends ConsumerWidget {
  /// By trip id (detail, active, arrived, share).
  const TripRoleTone.trip(String this.tripId, {super.key, required this.child})
      : matchId = null,
        useActive = false;

  /// By match id (match, pickup, chat): the role of MY trip in that match.
  const TripRoleTone.match(String this.matchId, {super.key, required this.child})
      : tripId = null,
        useActive = false;

  /// The current active trip (candidate detail, requests, SOS without trip).
  const TripRoleTone.active({super.key, required this.child})
      : tripId = null,
        matchId = null,
        useActive = true;

  final String? tripId;
  final String? matchId;
  final bool useActive;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    TripRole? role;
    if (tripId != null) {
      final active = ref.watch(activeTripProvider).valueOrNull;
      role = active?.id == tripId ? active?.role : ref.watch(tripByIdProvider(tripId!)).valueOrNull?.role;
    } else if (matchId != null) {
      final inbox = ref.watch(inboxProvider).valueOrNull ?? const [];
      for (final m in inbox) {
        if (m.id == matchId) role = m.myRole;
      }
      // A match opened by deep link before the inbox loaded: fall back to the active trip.
      role ??= ref.watch(activeTripProvider).valueOrNull?.role;
    } else if (useActive) {
      role = ref.watch(activeTripProvider).valueOrNull?.role;
    }
    return ToneScope(tone: toneOfTripRole(role), child: child);
  }
}
