import '../../../core/error/result.dart';
import 'trip.dart';
import 'trip_state_machine.dart';

abstract class TripRepository {
  /// The caller's scheduled/in-progress trip (max 1), or null.
  Future<Result<Trip?>> activeTrip();

  /// Idempotent: retries with the same [TripDraft.id] never create two trips.
  Future<Result<Trip>> createTrip(TripDraft draft);

  /// Own trips. `history: false` = scheduled/in-progress, `true` = finished
  /// (completed/cancelled/expired), newest first, never unbounded.
  Future<Result<List<Trip>>> myTrips({required bool history, int limit = 20});

  Future<Result<Trip?>> tripById(String id);

  /// start / complete / cancel with a status guard. A retry that finds the
  /// trip already in the target state returns it as success.
  Future<Result<Trip>> transition(String id, TripAction action);

  /// Driver trips: change the drop-off limit (metres). Server: GWM_TRIP_HAS_MATCHES when a request is
  /// pending or a match accepted, GWM_TRIP_STARTED, GWM_DROPOFF_INVALID.
  Future<Result<Trip>> updateMaxDropoff(String id, int metres);

  /// US-50 (round 7): driver trips only, change the route detour tolerance (metres). Server:
  /// GWM_TRIP_HAS_MATCHES when a request is pending or a match accepted, GWM_TRIP_STARTED,
  /// GWM_DETOUR_INVALID, GWM_DETOUR_NOT_ALLOWED.
  Future<Result<Trip>> updateDetourTolerance(String id, int metres);

  /// US-44: replace this trip's vibe tags (<= 3, allow-list) and mood text (<= 35 chars,
  /// Q6 guard). Server: GWM_VIBE_TAG_INVALID, GWM_MOOD_INVALID.
  Future<Result<Trip>> updateVibeMood(String id, {required List<String> vibeTags, required String? moodText});

  /// US-45: toggle Women-Only for this trip. Server: GWM_GENDER_REQUIRED when
  /// the caller's gender isn't currently 'female' (checked live, Q8).
  Future<Result<Trip>> updateWomenOnly(String id, bool value);

  /// Soft delete; only allowed for finished trips (server: GWM_CANCEL_BEFORE_DELETE).
  Future<Result<void>> deleteTrip(String id);
}
