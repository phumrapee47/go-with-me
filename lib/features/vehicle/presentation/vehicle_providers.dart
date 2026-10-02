import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/error/app_failure.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../trip/domain/trip.dart';
import '../../trip/presentation/trip_providers.dart';
import '../data/supabase_vehicle_repository.dart';
import '../domain/vehicle.dart';

final vehicleRepositoryProvider = Provider<VehicleRepository>(
  (ref) => SupabaseVehicleRepository(Supabase.instance.client),
);

/// Outcome of "save vehicle (+ optional consent choice made before the vehicle existed)".
class VehicleSaveOutcome {
  const VehicleSaveOutcome({this.failure, this.consentFailed = false});
  final AppFailure? failure;

  /// The vehicle was saved but applying the share switch failed (F-R2.4).
  final bool consentFailed;
  bool get ok => failure == null && !consentFailed;
}

/// The caller's own vehicle (null = none yet).
class MyVehicleController extends AsyncNotifier<Vehicle?> {
  @override
  Future<Vehicle?> build() async {
    final uid = ref.watch(authUserProvider.select((a) => a.valueOrNull?.id));
    if (uid == null) return null;
    final res = await ref.watch(vehicleRepositoryProvider).mine();
    return res.when(ok: (v) => v, err: (f) => throw f);
  }

  Future<void> reload() async {
    final res = await ref.read(vehicleRepositoryProvider).mine();
    res.when(ok: (v) => state = AsyncData(v), err: (f) => state = state.hasValue ? state : AsyncError(f, StackTrace.current));
  }

  /// Saves the form. [wantConsent] (only meaningful when the user flipped the
  /// switch before any vehicle existed) is applied after a successful save.
  Future<VehicleSaveOutcome> save(VehicleInput input, {bool? wantConsent}) async {
    final repo = ref.read(vehicleRepositoryProvider);
    final res = await repo.save(input);
    if (res.failureOrNull case final f?) return VehicleSaveOutcome(failure: f);
    var consentFailed = false;
    if (wantConsent != null && wantConsent != (state.valueOrNull?.shareConsent ?? false)) {
      final c = await repo.setShareConsent(wantConsent);
      consentFailed = c.failureOrNull != null;
    }
    await reload();
    return VehicleSaveOutcome(consentFailed: consentFailed);
  }

  /// Optimistic-free: the switch shows "saving" in the UI and only changes
  /// after the server confirmed. Returns the failure or null.
  Future<AppFailure?> setShareConsent(bool on) async {
    final res = await ref.read(vehicleRepositoryProvider).setShareConsent(on);
    final f = res.failureOrNull;
    if (f == null) {
      final cur = state.valueOrNull;
      if (cur != null) state = AsyncData(cur.copyWith(shareConsent: on));
    }
    return f;
  }

  Future<AppFailure?> delete() async {
    final res = await ref.read(vehicleRepositoryProvider).deleteMine();
    final f = res.failureOrNull;
    if (f == null) state = const AsyncData(null);
    return f;
  }
}

final myVehicleProvider = AsyncNotifierProvider<MyVehicleController, Vehicle?>(MyVehicleController.new);

/// What a matched Rider may see for one match (null = not allowed / none).
final matchVehicleProvider = FutureProvider.autoDispose.family<VehicleView?, String>((ref, matchId) async {
  final res = await ref.watch(vehicleRepositoryProvider).forMatch(matchId);
  return res.when(ok: (v) => v, err: (f) => throw f);
});

/// Q-6: the vehicle cannot be deleted while a Driver trip is active or an
/// accepted match has me as the Driver. (Server: GWM_VEHICLE_IN_USE.)
final vehicleDeleteLockedProvider = Provider<bool>((ref) {
  final trip = ref.watch(activeTripProvider).valueOrNull;
  if (trip != null && trip.role == TripRole.driver && trip.status.isActive) return true;
  final inbox = ref.watch(inboxProvider).valueOrNull ?? const <MatchSummary>[];
  return inbox.any((m) => m.status == MatchStatus.accepted && m.iAmDriver);
});
