import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/error/result.dart';
import '../../chat/domain/chat_models.dart';
import '../../chat/presentation/chat_providers.dart';
import '../../geo/domain/location_service.dart';
import '../../geo/presentation/geo_providers.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../../privacy/presentation/consent_providers.dart';
import '../../sharing/presentation/sharing_providers.dart';
import '../data/supabase_live_location_repository.dart';
import '../domain/live_location.dart';
import '../domain/trip.dart';
import '../domain/trip_state_machine.dart';
import 'trip_providers.dart';

final liveLocationRepositoryProvider = Provider<LiveLocationRepository>(
  (ref) => SupabaseLiveLocationRepository(Supabase.instance.client),
);

/// false while the app is not visible: live sharing is while-in-use only.
final appForegroundProvider = StateProvider<bool>((ref) => true);

/// design-api 8: partner position is polled every 15 s (the sender pushes every 15 s), foreground only.
final partnerPollIntervalProvider = Provider<Duration>((ref) => const Duration(seconds: 15));

/// How often the "who may see my position" list is re-checked (block etc.).
final sharingRecheckIntervalProvider = Provider<Duration>((ref) => const Duration(seconds: 60));

/// Own trips: `history=false` current, `true` finished.
final myTripsProvider = FutureProvider.autoDispose.family<List<Trip>, bool>((ref, history) async {
  final res = await ref.watch(tripRepositoryProvider).myTrips(history: history);
  return res.when(ok: (l) => l, err: (f) => throw f);
});

final tripByIdProvider = FutureProvider.autoDispose.family<Trip?, String>((ref, id) async {
  final res = await ref.watch(tripRepositoryProvider).tripById(id);
  return res.when(ok: (t) => t, err: (f) => throw f);
});

/// Accepted partners of [tripId] (max 3).
List<MatchSummary> acceptedPartnersOf(List<MatchSummary> all, String tripId) =>
    [for (final m in all) if (m.status == MatchStatus.accepted && m.myTripId == tripId) m];

/// start / complete / cancel and the cache invalidation that follows.
class TripActions {
  TripActions(this._ref);
  final Ref _ref;

  Future<Result<Trip>> run(String tripId, TripAction action) async {
    // Ending my own trip closes matches server-side: that is not a "partner ended it" alert.
    if (action != TripAction.start) _ref.read(matchAlertProvider.notifier).quiet();
    final res = await _ref.read(tripRepositoryProvider).transition(tripId, action);
    _refresh(tripId);
    return res;
  }

  Future<Result<void>> delete(String tripId) async {
    final res = await _ref.read(tripRepositoryProvider).deleteTrip(tripId);
    _refresh(tripId);
    return res;
  }

  void _refresh(String tripId) {
    _ref
      ..invalidate(activeTripProvider)
      ..invalidate(myTripsProvider(false))
      ..invalidate(myTripsProvider(true))
      ..invalidate(tripByIdProvider(tripId))
      ..invalidate(inboxProvider); // server closes pending matches / notifies partners
  }
}

final tripActionsProvider = Provider<TripActions>(TripActions.new);

/// Accepted partners this trip's live location may be shown to: the match is
/// open (chat_state == open, i.e. not blocked/closed). Re-checked on a timer
/// so a block by the other side also stops sharing.
final sharingPartnersProvider = FutureProvider<List<String>>((ref) async {
  final trip = ref.watch(activeTripProvider).valueOrNull;
  if (trip == null || trip.status != TripStatus.inProgress) return const [];
  final all = ref.watch(inboxProvider).valueOrNull ?? const <MatchSummary>[];
  final timer = Timer(ref.read(sharingRecheckIntervalProvider), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final repo = ref.read(chatRepositoryProvider);
  final ids = <String>[];
  for (final m in acceptedPartnersOf(all, trip.id)) {
    final st = await repo.state(m.id);
    if (st case Ok(:final value) when value == ChatState.open) ids.add(m.id);
  }
  return ids;
});

/// Open accepted partners I actually PUSH my position for. A Rider who has
/// boarded stops sending to the Driver (US-18, T6.16): they are in the same car
/// and the server would not return it anyway (data minimisation). The Rider
/// keeps seeing the Driver, which uses [sharingPartnersProvider].
final livePushPartnersProvider = Provider<List<String>>((ref) {
  final open = ref.watch(sharingPartnersProvider).valueOrNull ?? const <String>[];
  final inbox = ref.watch(inboxProvider).valueOrNull ?? const <MatchSummary>[];
  final boardedRider = {
    for (final m in inbox)
      if (m.iAmRider && m.boarded) m.id,
  };
  return [
    for (final id in open)
      if (!boardedRider.contains(id)) id,
  ];
});

enum TrackStatus { idle, searching, tracking, denied }

class TrackingState {
  const TrackingState({this.status = TrackStatus.idle, this.fix, this.sharing = false});
  final TrackStatus status;
  final LocationFix? fix;

  /// True when positions are being sent to at least one accepted partner.
  final bool sharing;

  TrackingState copyWith({TrackStatus? status, LocationFix? fix}) =>
      TrackingState(status: status ?? this.status, fix: fix ?? this.fix, sharing: sharing);
}

/// Runs while a trip is in progress and the app is in the foreground:
/// watches GPS (for the map and arrival prompt) and pushes fixes to the
/// server only when an open accepted match exists. Everything stops when the
/// trip ends, consent is withdrawn, the app is backgrounded or a partner block
/// closes the match. Rebuilds (and re-subscribes) when any input changes.
class TripTrackingController extends Notifier<TrackingState> {
  @override
  TrackingState build() {
    final trip = ref.watch(activeTripProvider).valueOrNull;
    final foreground = ref.watch(appForegroundProvider);
    final consent = ref.watch(locationConsentProvider).valueOrNull;
    final partners = ref.watch(livePushPartnersProvider);
    final openPartners = ref.watch(sharingPartnersProvider).valueOrNull ?? const <String>[];
    // A boarded Rider still feeds their OWN share link / contacts (design-roles 2):
    // the server hides the position from the Driver, the link keeps working.
    final linkOnly = trip != null &&
        partners.isEmpty &&
        openPartners.isNotEmpty &&
        ref.watch(activeSharesProvider.select((a) => a.valueOrNull?.any((s) => s.tripId == trip.id) ?? false));

    final lastFixNotifier = ref.read(lastFixProvider.notifier);
    if (trip == null || trip.status != TripStatus.inProgress) {
      if (lastFixNotifier.state != null) Future.microtask(() => lastFixNotifier.state = null);
      return const TrackingState();
    }
    final sharing = partners.isNotEmpty;
    final last = ref.read(lastFixProvider);
    if (consent == false) return TrackingState(status: TrackStatus.denied, fix: last, sharing: false);
    if (!foreground || consent == null) {
      return TrackingState(status: last == null ? TrackStatus.searching : TrackStatus.tracking, fix: last);
    }

    var alive = true;
    final sharer = LiveLocationSharer(
      repo: ref.read(liveLocationRepositoryProvider),
      clock: ref.read(refreshClockProvider),
    );
    final push = sharing || linkOnly;
    if (push) sharer.start(trip.id);
    final loc = ref.read(locationServiceProvider);
    StreamSubscription<LocationFix>? sub;

    void deny() {
      if (alive) state = TrackingState(status: TrackStatus.denied, fix: state.fix, sharing: false);
    }

    unawaited(() async {
      final p = await loc.permission();
      if (!alive) return;
      if (p != LocationPermissionState.granted) deny();
    }());

    sub = loc.watch().listen(
      (fix) {
        if (!alive) return;
        ref.read(lastFixProvider.notifier).state = fix;
        state = TrackingState(status: TrackStatus.tracking, fix: fix, sharing: sharing);
        if (push) unawaited(sharer.onFix(fix));
      },
      onError: (_) => deny(),
    );
    ref.onDispose(() {
      alive = false;
      sharer.stop();
      unawaited(sub?.cancel());
    });
    return TrackingState(
      status: last == null ? TrackStatus.searching : TrackStatus.tracking,
      fix: last,
      sharing: sharing,
    );
  }
}

final tripTrackingProvider = NotifierProvider<TripTrackingController, TrackingState>(TripTrackingController.new);

class PartnerView {
  const PartnerView({this.point, this.at, this.loaded = false});
  final LatLng? point;
  final DateTime? at;
  final bool loaded;
}

/// Polls the partner's live position for one match (foreground only).
class PartnerLocationController extends AutoDisposeFamilyNotifier<PartnerView, String> {
  bool _disposed = false;

  @override
  PartnerView build(String matchId) {
    _disposed = false; // the same notifier instance is reused on invalidate
    final timer = Timer.periodic(ref.read(partnerPollIntervalProvider), (_) => unawaited(_poll()));
    ref.onDispose(() {
      _disposed = true;
      timer.cancel();
    });
    Future.microtask(_poll);
    return const PartnerView();
  }

  Future<void> _poll() async {
    if (_disposed || !ref.read(appForegroundProvider)) return;
    final res = await ref.read(liveLocationRepositoryProvider).partnerLocation(arg);
    if (_disposed) return;
    switch (res) {
      case Ok(:final value):
        state = PartnerView(point: value?.point, at: value?.recordedAt, loaded: true);
      case Err():
        state = PartnerView(point: state.point, at: state.at, loaded: true); // keep last, retry quietly
    }
  }
}

final partnerLocationProvider =
    NotifierProvider.autoDispose.family<PartnerLocationController, PartnerView, String>(PartnerLocationController.new);
