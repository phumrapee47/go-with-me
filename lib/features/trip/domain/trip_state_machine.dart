import 'trip.dart';

enum TripAction { start, complete, cancel }

/// Client mirror of the `trips_guard` trigger (0001): the server is the
/// authority, this exists so the UI only offers legal actions and so the
/// repository can send a guarded PATCH.
///
///   scheduled   -> in_progress | cancelled | expired (system only)
///   in_progress -> completed | cancelled
///   completed / cancelled / expired are terminal.
abstract final class TripStateMachine {
  /// Status reached by [action] from [from], or null when illegal.
  static TripStatus? apply(TripStatus from, TripAction action) => switch ((from, action)) {
        (TripStatus.scheduled, TripAction.start) => TripStatus.inProgress,
        (TripStatus.scheduled, TripAction.cancel) => TripStatus.cancelled,
        (TripStatus.inProgress, TripAction.complete) => TripStatus.completed,
        (TripStatus.inProgress, TripAction.cancel) => TripStatus.cancelled,
        _ => null,
      };

  static bool canApply(TripStatus from, TripAction action) => apply(from, action) != null;

  static Set<TripAction> actionsFor(TripStatus from) =>
      {for (final a in TripAction.values) if (canApply(from, a)) a};

  /// Statuses a PATCH may start from (used as `status=in.(...)` guard so a
  /// stale client can never overwrite a newer state).
  static List<TripStatus> sourcesFor(TripAction action) =>
      [for (final s in TripStatus.values) if (canApply(s, action)) s];

  static TripStatus targetOf(TripAction action) => switch (action) {
        TripAction.start => TripStatus.inProgress,
        TripAction.complete => TripStatus.completed,
        TripAction.cancel => TripStatus.cancelled,
      };

  /// Raw transition check, including the system-only `expired` edge.
  static bool canTransition(TripStatus from, TripStatus to, {bool system = false}) {
    if (from == TripStatus.scheduled && to == TripStatus.expired) return system;
    for (final a in TripAction.values) {
      if (apply(from, a) == to) return true;
    }
    return false;
  }

  /// A retried action that finds the trip already in the target state is a
  /// success (design-api 7.3), anything else is a stale/illegal request.
  static bool isAlreadyDone(TripStatus current, TripAction action) => current == targetOf(action);
}
