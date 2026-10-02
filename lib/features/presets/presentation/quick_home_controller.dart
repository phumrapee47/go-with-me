import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/log.dart';
import '../../geo/domain/geo_services.dart' show RouteResult;
import '../../geo/presentation/geo_providers.dart';
import '../../matching/presentation/matching_providers.dart' show refreshClockProvider;
import '../../roles/presentation/role_providers.dart';
import '../../trip/domain/dropoff.dart';
import '../../trip/domain/travel_mode.dart';
import '../../trip/domain/trip.dart';
import '../../trip/domain/trip_form.dart';
import '../../trip/presentation/trip_providers.dart';
import '../../vehicle/presentation/vehicle_providers.dart';
import '../domain/preset.dart';
import 'preset_providers.dart';

/// State of the one-tap "กำลังจะกลับบ้านใช่ไหม?" card.
class QuickHomeState {
  const QuickHomeState({this.creating = false, this.failure, this.needsRegister = false, this.hasActiveTrip = false});
  final bool creating;

  /// Shown on the card as Thai text (never a code); a retry or the step-by-step wizard follows.
  final AppFailure? failure;

  /// Driver role chosen but not registered / no vehicle: inline CTA to register (US-19).
  final bool needsRegister;

  /// A trip is already active (max 1): offer "go to the trip".
  final bool hasActiveTrip;

  bool get hasError => failure != null || needsRegister || hasActiveTrip;
}

/// Creates the Home trip with the SAME building blocks as the wizard: OSRM route + `createTrip`
/// (car only, origin = regular start preset, destination = Home preset). `max_dropoff_m` is sent for the
/// Driver role only. Nothing about the presets is sent except the trip's own origin/destination.
class QuickHomeController extends Notifier<QuickHomeState> {
  static const _uuid = Uuid();
  String? _draftId;
  String? _draftKey;

  @override
  QuickHomeState build() => const QuickHomeState();

  void clearError() {
    if (!state.creating && state.hasError) state = const QuickHomeState();
  }

  /// [departAt] null = "now". Returns true when the trip exists (the caller goes to the deck).
  Future<bool> create({required DateTime? departAt, required TripRole role, required int maxDropoffM}) async {
    if (state.creating) return false; // double tap protection
    state = const QuickHomeState(creating: true);
    try {
      final ok = await _run(departAt, role, maxDropoffM);
      if (ok) state = const QuickHomeState();
      return ok;
    } catch (e) {
      Log.d('quick create failed');
      state = const QuickHomeState(failure: AppFailure(FailureCode.unknown));
      return false;
    }
  }

  Future<bool> _run(DateTime? departAt, TripRole role, int maxDropoffM) async {
    final data = ref.read(presetsProvider).valueOrNull ?? PresetData.empty;
    final home = data.home;
    final start = data.start;
    if (home == null || start == null) {
      state = const QuickHomeState(failure: AppFailure('GWM_VALIDATION'));
      return false;
    }
    final now = ref.read(refreshClockProvider)();

    // Max 1 active trip (server rule, checked first for a clear message).
    final active = await ref.read(tripRepositoryProvider).activeTrip();
    final activeFailure = active.failureOrNull;
    if (activeFailure != null) {
      state = QuickHomeState(failure: activeFailure);
      return false;
    }
    if (active.valueOrNull != null) {
      ref.invalidate(activeTripProvider);
      state = const QuickHomeState(failure: AppFailure('GWM_ACTIVE_TRIP_LIMIT'), hasActiveTrip: true);
      return false;
    }

    // Driver: needs registration + a vehicle.
    var hasVehicle = true;
    if (role == TripRole.driver) {
      final registered = ref.read(driverRegisteredProvider);
      var vehicle = ref.read(myVehicleProvider).valueOrNull != null;
      if (!vehicle) {
        try {
          vehicle = (await ref.read(myVehicleProvider.future)) != null;
        } catch (_) {
          vehicle = ref.read(roleControllerProvider).registration?.hasVehicle ?? false;
        }
      }
      hasVehicle = vehicle;
      if (registered != true || !hasVehicle) {
        state = const QuickHomeState(needsRegister: true);
        return false;
      }
    }

    final origin = start.toPlace();
    final dest = home.toPlace();
    final placesIssue = TripFormValidator.validatePlaces(origin, dest);
    if (placesIssue != null) {
      state = const QuickHomeState(failure: AppFailure('GWM_TRIP_TOO_SHORT'));
      return false;
    }
    final optionsIssue = TripFormValidator.validateOptions(
      mode: TravelMode.car,
      departAt: departAt,
      now: now,
      role: role,
      hasVehicle: hasVehicle,
    );
    if (optionsIssue != null) {
      state = QuickHomeState(
        failure: AppFailure(switch (optionsIssue) {
          TripFormIssue.roleMissing => 'GWM_ROLE_REQUIRED',
          TripFormIssue.vehicleMissing => 'GWM_VEHICLE_REQUIRED',
          _ => 'GWM_DEPART_IN_PAST',
        }),
      );
      return false;
    }

    // Same route service as the wizard; a routing failure is fail-closed (no straight-line fallback).
    final RouteResult route;
    try {
      route = await ref.read(routingServiceProvider).route(mode: TravelMode.car, from: origin.point, to: dest.point);
    } on AppFailure catch (f) {
      state = QuickHomeState(failure: f);
      return false;
    }

    final limit = role == TripRole.driver ? clampDropoff(maxDropoffM) : null;
    final key = '${departAt?.millisecondsSinceEpoch}|${role.db}|$limit';
    if (_draftKey != key) {
      _draftKey = key;
      _draftId = _uuid.v4();
    }
    final draft = TripDraft(
      id: _draftId!,
      mode: TravelMode.car,
      origin: origin,
      dest: dest,
      route: route.geometry,
      distanceM: route.distanceM,
      durationS: route.durationS,
      departAt: departAt ?? now,
      role: role,
      maxDropoffM: limit, // Driver only
    );
    final res = await ref.read(tripRepositoryProvider).createTrip(draft);
    final failure = res.failureOrNull;
    if (failure != null) {
      if (failure.code == 'GWM_NOT_A_DRIVER') {
        unawaited(ref.read(roleControllerProvider.notifier).refresh());
        state = const QuickHomeState(needsRegister: true);
      } else {
        state = QuickHomeState(failure: failure, hasActiveTrip: failure.code == 'GWM_ACTIVE_TRIP_LIMIT');
      }
      return false;
    }
    _draftId = null;
    _draftKey = null;
    ref.invalidate(activeTripProvider);
    await ref.read(presetsProvider.notifier).rememberChoices(
          departMinutes: departAt == null ? null : departAt.hour * 60 + departAt.minute,
          maxDropoffM: limit,
        );
    return true;
  }
}

final quickHomeProvider = NotifierProvider<QuickHomeController, QuickHomeState>(QuickHomeController.new);
