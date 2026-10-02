import 'dart:async';

import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/features/geo/domain/geo_services.dart';
import 'package:gowithme/features/geo/domain/location_service.dart';
import 'package:gowithme/features/matching/domain/match_models.dart';
import 'package:gowithme/features/matching/domain/match_repository.dart';
import 'package:gowithme/features/privacy/domain/consent_repository.dart';
import 'package:gowithme/features/profile/domain/gender.dart';
import 'package:gowithme/features/profile/domain/profile_repository.dart';
import 'package:gowithme/features/trip/domain/travel_mode.dart';
import 'package:gowithme/features/trip/domain/trip.dart';
import 'package:gowithme/features/trip/domain/trip_repository.dart';
import 'package:gowithme/features/trip/domain/trip_state_machine.dart';
import 'package:gowithme/features/vehicle/domain/vehicle.dart';
import 'package:latlong2/latlong.dart';

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({String name = 'มิ้นท์'}) : _name = name;
  String _name;
  AppFailure? updateFailure;
  int updates = 0;
  List<VerificationBadge> badges = const [VerificationBadge(kind: 'email')];

  @override
  Future<Result<List<VerificationBadge>>> myBadges() async => Ok(badges);

  @override
  Future<Result<Profile?>> getMe() async => Ok(Profile(id: 'u1', displayName: _name));

  @override
  Future<Result<Profile>> updateDisplayName(String name) async {
    updates++;
    if (updateFailure != null) return Err(updateFailure!);
    _name = name.trim();
    return Ok(Profile(id: 'u1', displayName: _name));
  }

  Gender? gender;
  AppFailure? genderFailure;

  @override
  Future<Result<Gender?>> getMyGender() async => genderFailure != null ? Err(genderFailure!) : Ok(gender);

  @override
  Future<Result<void>> setMyGender(Gender g) async {
    if (genderFailure != null) return Err(genderFailure!);
    gender = g;
    return const Ok(null);
  }

  @override
  Future<Result<void>> clearMyGender() async {
    if (genderFailure != null) return Err(genderFailure!);
    gender = null;
    return const Ok(null);
  }
}

class FakeTripRepository implements TripRepository {
  Trip? active;
  AppFailure? createFailure;
  final created = <TripDraft>[];

  @override
  Future<Result<Trip?>> activeTrip() async => Ok(active);

  @override
  Future<Result<Trip>> createTrip(TripDraft d) async {
    if (createFailure != null) return Err(createFailure!);
    created.add(d);
    active = Trip(
      id: d.id,
      mode: d.mode,
      role: d.role,
      status: TripStatus.scheduled,
      origin: d.origin.point,
      dest: d.dest.point,
      originLabel: d.origin.label,
      destLabel: d.dest.label,
      route: d.route,
      distanceM: d.distanceM,
      durationS: d.durationS,
      departAt: d.departAt,
      maxDropoffM: d.role == TripRole.driver ? d.maxDropoffM : null,
      vibeTags: d.vibeTags,
      moodText: d.moodText,
      womenOnly: d.womenOnly,
    );
    return Ok(active!);
  }

  AppFailure? vibeMoodFailure;
  final vibeMoodUpdates = <(String, List<String>, String?)>[];

  @override
  Future<Result<Trip>> updateVibeMood(String id, {required List<String> vibeTags, required String? moodText}) async {
    vibeMoodUpdates.add((id, vibeTags, moodText));
    if (vibeMoodFailure != null) return Err(vibeMoodFailure!);
    active = active!.copyWith(vibeTags: vibeTags, moodText: () => moodText, moodSetAt: () => DateTime.now());
    return Ok(active!);
  }

  AppFailure? womenOnlyFailure;
  final womenOnlyUpdates = <(String, bool)>[];

  @override
  Future<Result<Trip>> updateWomenOnly(String id, bool value) async {
    womenOnlyUpdates.add((id, value));
    if (womenOnlyFailure != null) return Err(womenOnlyFailure!);
    active = active!.copyWith(womenOnly: value);
    return Ok(active!);
  }

  AppFailure? dropoffFailure;
  final dropoffUpdates = <(String, int)>[];

  @override
  Future<Result<Trip>> updateMaxDropoff(String id, int metres) async {
    dropoffUpdates.add((id, metres));
    if (dropoffFailure != null) return Err(dropoffFailure!);
    active = active!.copyWith(maxDropoffM: metres);
    return Ok(active!);
  }

  AppFailure? detourFailure;
  final detourUpdates = <(String, int)>[];

  @override
  Future<Result<Trip>> updateDetourTolerance(String id, int metres) async {
    detourUpdates.add((id, metres));
    if (detourFailure != null) return Err(detourFailure!);
    active = active!.copyWith(detourToleranceM: metres);
    return Ok(active!);
  }

  /// Finished trips (completed/cancelled/expired), newest first.
  final finished = <Trip>[];
  AppFailure? transitionFailure;
  final transitions = <(String, TripAction)>[];
  final deleted = <String>[];

  Trip? _find(String id) {
    if (active?.id == id) return active;
    for (final t in finished) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<Result<List<Trip>>> myTrips({required bool history, int limit = 20}) async =>
      Ok(history ? List.of(finished) : [?active]);

  @override
  Future<Result<Trip?>> tripById(String id) async => Ok(_find(id));

  @override
  Future<Result<Trip>> transition(String id, TripAction action) async {
    transitions.add((id, action));
    if (transitionFailure != null) return Err(transitionFailure!);
    final t = _find(id);
    if (t == null) return const Err(AppFailure('GWM_TRIP_NOT_FOUND'));
    final next = TripStateMachine.apply(t.status, action);
    if (next == null) {
      return TripStateMachine.isAlreadyDone(t.status, action)
          ? Ok(t)
          : const Err(AppFailure('GWM_INVALID_TRIP_TRANSITION'));
    }
    final updated = t.copyWith(
      status: next,
      startedAt: next == TripStatus.inProgress ? DateTime.now() : null,
      endedAt: next.isTerminal ? DateTime.now() : null,
    );
    if (next.isTerminal) {
      active = null;
      finished.insert(0, updated);
    } else {
      active = updated;
    }
    return Ok(updated);
  }

  @override
  Future<Result<void>> deleteTrip(String id) async {
    deleted.add(id);
    finished.removeWhere((t) => t.id == id);
    return const Ok(null);
  }
}

Trip sampleTrip({
  String id = 'trip-1',
  TravelMode mode = TravelMode.transit,
  TripRole? role,
  TripStatus status = TripStatus.scheduled,
  int? maxDropoffM,
  int? detourToleranceM,
}) =>
    Trip(
      id: id,
      maxDropoffM: maxDropoffM,
      detourToleranceM: detourToleranceM,
      mode: mode,
      role: role,
      status: status,
      origin: const LatLng(13.7455, 100.5345),
      dest: const LatLng(13.9, 100.6),
      originLabel: 'สยาม',
      destLabel: 'รังสิต',
      route: const [LatLng(13.7455, 100.5345), LatLng(13.9, 100.6)],
      distanceM: 20000,
      durationS: 1800,
      departAt: DateTime.now().add(const Duration(minutes: 10)),
    );

MatchCandidate sampleCandidate({
  String tripId = 'cand-1',
  String name = 'นุ่น',
  MatchStatus? status,
  double score = 80,
  TravelMode mode = TravelMode.transit,
  TripRole? role,
  int? maxDropoffM,
  double? ratingAvg,
  int? ratingCount,
}) =>
    MatchCandidate(
      tripId: tripId,
      displayName: name,
      role: role,
      badges: const [VerificationBadge(kind: 'email')],
      mode: mode,
      departAt: DateTime.now().add(const Duration(minutes: 15)),
      timeDiffMin: 5,
      overlapPct: 72,
      approxDistanceM: 1500,
      score: score,
      approxOrigin: const LatLng(13.7455, 100.5345),
      approxDest: const LatLng(13.9, 100.6),
      requestStatus: status,
      maxDropoffM: maxDropoffM,
      ratingAvg: ratingAvg,
      ratingCount: ratingCount,
    );

class FakeMatchFinderRepository implements MatchFinderRepository {
  List<MatchCandidate> result = [];
  AppFailure? failure;
  int calls = 0;
  MatchHint? hint = MatchHint.noneFound;
  AppFailure? hintFailure;
  int hintCalls = 0;

  @override
  Future<Result<MatchHint?>> matchHint(String tripId) async {
    hintCalls++;
    if (hintFailure != null) return Err(hintFailure!);
    return Ok(hint);
  }

  @override
  Future<Result<List<MatchCandidate>>> findMatches(String tripId, {int limit = 20}) async {
    calls++;
    if (failure != null) return Err(failure!);
    return Ok(List.of(result));
  }
}

class FakeMatchRepository implements MatchRepository {
  List<MatchSummary> matches = [];
  AppFailure? requestFailure;
  AppFailure? responseFailure;
  MatchStatus requestStatus = MatchStatus.pending;
  final requests = <(String, String)>[];
  /// US-50 (round 7 Stage D): the `clientDetourM` each `request()` call was made with (null = omitted).
  final requestDetourM = <double?>[];
  final responses = <(String, bool)>[];
  int inboxCalls = 0;
  final _changes = StreamController<void>.broadcast();

  void emitChange() => _changes.add(null);

  @override
  Future<Result<MatchRequestOutcome>> request({
    required String myTripId,
    required String targetTripId,
    double? clientDetourM,
  }) async {
    requests.add((myTripId, targetTripId));
    requestDetourM.add(clientDetourM);
    if (requestFailure != null) return Err(requestFailure!);
    // A real request leaves a row in the inbox (the deck's undo re-reads it).
    if (!matches.any((m) => m.id == 'm-new')) {
      matches = [
        ...matches,
        sampleMatch(id: 'm-new', status: requestStatus, iAmRequester: true, myTripId: myTripId),
      ];
    }
    return Ok(MatchRequestOutcome(matchId: 'm-new', status: requestStatus, iAmRequester: true));
  }

  @override
  Future<Result<List<MatchSummary>>> inbox() async {
    inboxCalls++;
    return Ok(List.of(frozenInbox ?? matches));
  }

  @override
  Future<Result<MatchStatus>> respond(String matchId, {required bool accept}) async {
    responses.add((matchId, accept));
    if (responseFailure != null) return Err(responseFailure!);
    final s = accept ? MatchStatus.accepted : MatchStatus.declined;
    matches = [for (final m in matches) m.id == matchId ? _copy(m, status: s) : m];
    return Ok(s);
  }

  @override
  Future<Result<void>> cancel(String matchId) async {
    if (cancelFailure != null) return Err(cancelFailure!);
    matches = [for (final m in matches) m.id == matchId ? _copy(m, status: MatchStatus.cancelled) : m];
    return const Ok(null);
  }

  /// Mirrors 0010 cancel_pending_match. [cancelPendingCalls] proves the deck no longer uses cancel().
  final cancelPendingCalls = <String>[];
  AppFailure? cancelPendingFailure;
  /// When true, inbox() keeps returning the snapshot taken at freeze time (simulates the accept racing the pre-read).
  List<MatchSummary>? frozenInbox;

  @override
  Future<Result<bool>> cancelPending(String matchId) async {
    cancelPendingCalls.add(matchId);
    if (cancelPendingFailure != null) return Err(cancelPendingFailure!);
    final m = matches.where((x) => x.id == matchId).firstOrNull;
    if (m == null) return const Err(AppFailure('GWM_MATCH_NOT_FOUND'));
    if (m.status == MatchStatus.cancelled) return const Ok(false);
    if (m.status != MatchStatus.pending) return const Err(AppFailure('GWM_MATCH_NOT_PENDING'));
    matches = [for (final x in matches) x.id == matchId ? _copy(x, status: MatchStatus.cancelled) : x];
    return const Ok(true);
  }

  /// Tests set this to make the next proposal report "beyond the deviation limit".
  bool proposeBeyondLimit = false;
  AppFailure? cancelFailure;
  AppFailure? proposeFailure;
  AppFailure? boardFailure;
  AppFailure? noShowFailure;
  final boarded = <String>[];
  final noShows = <String>[];
  final proposals = <(String, LatLng)>[];

  @override
  Future<Result<bool>> proposeMeetingPoint(String matchId, LatLng point, String label) async {
    if (proposeFailure != null) return Err(proposeFailure!);
    proposals.add((matchId, point));
    matches = [
      for (final m in matches) m.id == matchId ? _copy(m, proposed: point, label: label, byMe: true) : m,
    ];
    return Ok(proposeBeyondLimit);
  }

  @override
  Future<Result<DateTime>> markBoarded(String matchId) async {
    boarded.add(matchId);
    if (boardFailure != null) return Err(boardFailure!);
    final at = DateTime.now();
    matches = [for (final m in matches) m.id == matchId ? _copy(m, boardedAt: at) : m];
    return Ok(at);
  }

  @override
  Future<Result<void>> reportRiderNoShow(String matchId) async {
    noShows.add(matchId);
    if (noShowFailure != null) return Err(noShowFailure!);
    matches = [for (final m in matches) m.id == matchId ? _copy(m, status: MatchStatus.cancelled) : m];
    return const Ok(null);
  }

  /// US-49: mirrors `cancel_match_no_fault`. Tests set [noFaultOverdue] to simulate the server's own
  /// re-check; false (default) simulates `GWM_NOT_OVERDUE`.
  bool noFaultOverdue = false;
  AppFailure? noFaultFailure;
  final noFaultCalls = <String>[];

  @override
  Future<Result<String>> cancelNoFault(String matchId) async {
    noFaultCalls.add(matchId);
    if (noFaultFailure != null) return Err(noFaultFailure!);
    final m = matches.where((x) => x.id == matchId).firstOrNull;
    if (m == null) return const Err(AppFailure('GWM_MATCH_NOT_FOUND'));
    if (m.status == MatchStatus.cancelled) return const Ok('already_cancelled');
    if (!noFaultOverdue) return const Err(AppFailure('GWM_NOT_OVERDUE'));
    matches = [for (final x in matches) x.id == matchId ? _copy(x, status: MatchStatus.cancelled) : x];
    return const Ok('cancelled');
  }

  @override
  Future<Result<void>> confirmMeetingPoint(String matchId) async {
    matches = [
      for (final m in matches)
        m.id == matchId ? _copy(m, meeting: m.proposedPoint, meetingLabel: m.proposedLabel, clearProposal: true) : m,
    ];
    return const Ok(null);
  }

  @override
  Stream<void> changes() => _changes.stream;

  MatchSummary _copy(
    MatchSummary m, {
    MatchStatus? status,
    LatLng? proposed,
    String? label,
    bool? byMe,
    LatLng? meeting,
    String? meetingLabel,
    bool clearProposal = false,
    DateTime? boardedAt,
  }) =>
      m.copyWith(
        status: status,
        proposedPoint: proposed,
        proposedLabel: label,
        proposedByMe: byMe,
        meetingPoint: meeting,
        meetingLabel: meetingLabel,
        clearProposal: clearProposal,
        boardedAt: boardedAt,
      );
}

MatchSummary sampleMatch({
  String id = 'm1',
  MatchStatus status = MatchStatus.pending,
  bool iAmRequester = false,
  String name = 'นุ่น',
  LatLng? proposed,
  bool proposedByMe = false,
  TripRole? myRole,
  DateTime? boardedAt,
  TripStatus? partnerTripStatus,
  bool autoClosed = false,
  String myTripId = 'trip-1',
}) =>
    MatchSummary(
      id: id,
      status: status,
      iAmRequester: iAmRequester,
      myTripId: myTripId,
      partnerTripId: 'cand-1',
      partnerName: name,
      myRole: myRole,
      partnerRole: myRole?.opposite,
      boardedAt: boardedAt,
      partnerTripStatus: partnerTripStatus,
      autoClosed: autoClosed,
      badges: const [VerificationBadge(kind: 'email')],
      mode: myRole == null ? TravelMode.transit : TravelMode.car,
      departAt: DateTime.now().add(const Duration(minutes: 20)),
      overlapPct: 70,
      approxOrigin: const LatLng(13.7455, 100.5345),
      approxDest: const LatLng(13.9, 100.6),
      meetingPoint: null,
      meetingLabel: null,
      proposedPoint: proposed,
      proposedLabel: proposed == null ? null : 'หน้าสถานี',
      proposedByMe: proposedByMe,
      createdAt: DateTime.now(),
      partnerId: 'partner-1',
    );

class FakeGeocoding implements GeocodingService {
  List<PlaceSuggestion> results = const [
    PlaceSuggestion(label: 'สยามพารากอน', point: LatLng(13.8027, 100.5537)),
  ];
  AppFailure? failure;
  final queries = <String>[];

  @override
  Future<List<PlaceSuggestion>> search(String query) async {
    queries.add(query);
    if (failure != null) throw failure!;
    return results;
  }

  @override
  Future<String> reverse(LatLng p) async => 'ที่อยู่ทดสอบ';
}

class FakeRouting implements RoutingService {
  AppFailure? failure;
  int calls = 0;

  @override
  Future<RouteResult> route({
    required TravelMode mode,
    required LatLng from,
    required LatLng to,
  }) async {
    calls++;
    if (failure != null) throw failure!;
    return RouteResult(geometry: [from, to], distanceM: 8400, durationS: 1500);
  }
}

class FakeLocationService implements LocationService {
  LocationPermissionState state = LocationPermissionState.denied;
  LocationPermissionState afterRequest = LocationPermissionState.granted;
  int requests = 0;

  @override
  Future<LocationPermissionState> permission() async => state;

  @override
  Future<LocationPermissionState> request() async {
    requests++;
    state = afterRequest;
    return state;
  }

  @override
  Future<Result<LatLng>> currentPosition() async => const Ok(LatLng(13.7455, 100.5345));

  final fixes = StreamController<LocationFix>.broadcast();

  @override
  Stream<LocationFix> watch() => fixes.stream;
}

class FakeConsentRepository implements ConsentRepository {
  int recorded = 0;
  bool locationGranted = true;
  final log = <bool>[];

  @override
  Future<Result<bool>> locationConsentGranted() async => Ok(locationGranted);

  @override
  Future<Result<void>> recordLocationConsent({required bool granted, required String policyVersion}) async {
    recorded++;
    log.add(granted);
    locationGranted = granted;
    return const Ok(null);
  }
}


class FakeVehicleRepository implements VehicleRepository {
  Vehicle? vehicle;
  AppFailure? saveFailure;
  AppFailure? consentFailure;
  AppFailure? deleteFailure;
  AppFailure? viewFailure;

  /// What a matched Rider would get from `get_match_vehicle` (null = no rows).
  VehicleView? view;
  final saved = <VehicleInput>[];
  final consentCalls = <bool>[];
  final forMatchCalls = <String>[];

  @override
  Future<Result<Vehicle?>> mine() async => Ok(vehicle);

  @override
  Future<Result<void>> save(VehicleInput input) async {
    if (saveFailure != null) return Err(saveFailure!);
    saved.add(input);
    vehicle = Vehicle(
      plate: input.plate,
      model: input.model,
      color: input.color,
      shareConsent: vehicle?.shareConsent ?? false,
    );
    return const Ok(null);
  }

  @override
  Future<Result<void>> setShareConsent(bool on) async {
    consentCalls.add(on);
    if (consentFailure != null) return Err(consentFailure!);
    if (vehicle == null) return const Err(AppFailure('GWM_VEHICLE_REQUIRED'));
    vehicle = vehicle!.copyWith(shareConsent: on);
    return const Ok(null);
  }

  @override
  Future<Result<void>> deleteMine() async {
    if (deleteFailure != null) return Err(deleteFailure!);
    vehicle = null;
    return const Ok(null);
  }

  @override
  Future<Result<VehicleView?>> forMatch(String matchId) async {
    forMatchCalls.add(matchId);
    if (viewFailure != null) return Err(viewFailure!);
    return Ok(view);
  }
}
