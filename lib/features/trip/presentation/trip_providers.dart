import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uuid/uuid.dart';

import '../../auth/presentation/auth_providers.dart';
import '../../geo/domain/geo_services.dart';
import '../../geo/presentation/geo_providers.dart';
import '../data/supabase_trip_repository.dart';
import '../domain/detour.dart';
import '../domain/dropoff.dart';
import '../domain/travel_mode.dart';
import '../domain/trip.dart';
import '../domain/trip_repository.dart';

final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => SupabaseTripRepository(Supabase.instance.client),
);

/// The caller's active trip (null = none). Errors surface as AsyncError with
/// an AppFailure so screens can show a retry state.
final activeTripProvider = FutureProvider<Trip?>((ref) async {
  final uid = ref.watch(authUserProvider.select((a) => a.value?.id));
  if (uid == null) return null;
  final res = await ref.watch(tripRepositoryProvider).activeTrip();
  return res.when(ok: (t) => t, err: (f) => throw f);
});

const _uuid = Uuid();

class TripFormState {
  const TripFormState({
    required this.draftId,
    this.origin,
    this.dest,
    this.scheduledAt,
    this.mode,
    this.role,
    this.roleTouched = false,
    this.maxDropoffM = dropoffDefaultM,
    this.detourToleranceM = detourDefaultM,
    this.vibeTags = const [],
    this.moodText = '',
    this.womenOnly = false,
  });

  /// Client-generated UUID = idempotency key for the insert. Regenerated on
  /// every edit so a changed form can never collide with an earlier attempt.
  final String draftId;
  final Place? origin;
  final Place? dest;

  /// null = depart "now" (resolved at submit time).
  final DateTime? scheduledAt;
  final TravelMode? mode;

  /// Only kept while [mode] is car; cleared whenever another mode is picked.
  final TripRole? role;

  /// The user picked the role themselves: the active-role default must never overwrite it (US-20).
  final bool roleTouched;

  /// Driver only (metres); default 2000. Not part of the payload for other roles.
  final int maxDropoffM;

  /// US-50 (round 7): driver only (metres); default 500. Not part of the payload for other roles.
  final int detourToleranceM;

  /// US-44: up to 3 tags from the role allow-list (`VibeTagCatalog`).
  final List<String> vibeTags;

  /// US-44: free text <= 35 chars (Q6 guard applied client+server).
  final String moodText;

  /// US-45: opt in to Women-Only for this trip (only takes effect server-side when gender='female').
  final bool womenOnly;

  bool get isNow => scheduledAt == null;
  DateTime departAt(DateTime now) => scheduledAt ?? now;

  TripFormState copyWith({
    Place? origin,
    Place? dest,
    TravelMode? mode,
    TripRole? role,
    bool clearRole = false,
    bool? roleTouched,
    int? maxDropoffM,
    int? detourToleranceM,
    Object? scheduledAt = _keep,
    bool clearOrigin = false,
    bool clearDest = false,
    List<String>? vibeTags,
    String? moodText,
    bool? womenOnly,
  }) {
    final nextMode = mode ?? this.mode;
    return TripFormState(
        draftId: _uuid.v4(),
        origin: clearOrigin ? null : (origin ?? this.origin),
        dest: clearDest ? null : (dest ?? this.dest),
        mode: nextMode,
        role: nextMode != TravelMode.car || clearRole ? null : (role ?? this.role),
        roleTouched: nextMode != TravelMode.car || clearRole ? false : (roleTouched ?? this.roleTouched),
        maxDropoffM: maxDropoffM ?? this.maxDropoffM,
        detourToleranceM: detourToleranceM ?? this.detourToleranceM,
        scheduledAt: identical(scheduledAt, _keep) ? this.scheduledAt : scheduledAt as DateTime?,
        vibeTags: vibeTags ?? this.vibeTags,
        moodText: moodText ?? this.moodText,
        womenOnly: womenOnly ?? this.womenOnly,
      );
  }
}

const Object _keep = Object();

class TripFormController extends Notifier<TripFormState> {
  @override
  TripFormState build() => TripFormState(draftId: _uuid.v4());

  void reset() => state = TripFormState(draftId: _uuid.v4());
  void setOrigin(Place p) => state = state.copyWith(origin: p);
  void clearOrigin() => state = state.copyWith(clearOrigin: true);
  void setDest(Place p) => state = state.copyWith(dest: p);
  void clearDest() => state = state.copyWith(clearDest: true);
  void setMode(TravelMode m) => state = state.copyWith(mode: m, clearRole: m != state.mode);
  /// The user tapped a role.
  void setRole(TripRole r) => state = state.copyWith(role: r, roleTouched: true);

  /// Default from the active role (never marks the role as touched).
  void setDefaultRole(TripRole r) => state = state.copyWith(role: r, roleTouched: false);
  void setMaxDropoff(int m) => state = state.copyWith(maxDropoffM: clampDropoff(m));
  void setDetourTolerance(int m) => state = state.copyWith(detourToleranceM: clampDetour(m));
  void departNow() => state = state.copyWith(scheduledAt: null);
  void departAt(DateTime t) => state = state.copyWith(scheduledAt: t);

  /// US-44: toggles [tag] in the current selection (caller already checked the allow-list/max-3 via
  /// `validateVibeTagSelection`; this never enforces the rule itself so the UI decides how to react).
  void toggleVibeTag(String tag) {
    final cur = state.vibeTags;
    state = state.copyWith(vibeTags: cur.contains(tag) ? [for (final t in cur) if (t != tag) t] : [...cur, tag]);
  }

  void setMood(String text) => state = state.copyWith(moodText: text);
  void setWomenOnly(bool v) => state = state.copyWith(womenOnly: v);
}

/// Kept alive across the 3 steps (screens are separate routes).
final tripFormProvider = NotifierProvider<TripFormController, TripFormState>(TripFormController.new);

/// Route preview for the confirm step; recomputed when origin/dest/mode change.
final routePreviewProvider = FutureProvider.autoDispose<RouteResult>((ref) {
  final f = ref.watch(tripFormProvider.select((s) => (s.origin, s.dest, s.mode)));
  final (origin, dest, mode) = f;
  if (origin == null || dest == null || mode == null) {
    throw StateError('form incomplete');
  }
  return ref.watch(routingServiceProvider).route(mode: mode, from: origin.point, to: dest.point);
});
