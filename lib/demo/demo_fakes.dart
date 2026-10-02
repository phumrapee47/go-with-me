import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:latlong2/latlong.dart';

import '../core/error/app_failure.dart';
import '../core/error/result.dart';
import '../core/geo/geo.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/geo/domain/geo_services.dart';
import '../features/geo/domain/location_service.dart';
import '../features/matching/domain/match_models.dart';
import '../features/matching/domain/match_repository.dart';
import '../features/privacy/domain/consent_repository.dart';
import '../features/profile/domain/gender.dart';
import '../features/profile/domain/profile_repository.dart';
import '../features/trip/domain/detour.dart';
import '../features/trip/domain/travel_mode.dart';
import '../features/trip/domain/trip.dart';
import '../features/trip/domain/trip_repository.dart';
import '../features/trip/domain/trip_state_machine.dart';
import '../features/vehicle/domain/vehicle.dart';
import 'demo_data.dart';

const _latency = Duration(milliseconds: 250);
Future<void> _wait() => Future<void>.delayed(_latency);

/// Always signed in at start; sign-in/sign-up accept anything.
class DemoAuthRepository implements AuthRepository {
  AuthUser? _user = const AuthUser(
    id: demoUserId,
    email: demoUserEmail,
    displayName: demoUserName,
    emailConfirmed: true,
  );
  final _controller = StreamController<AuthUser?>.broadcast();

  void _emit(AuthUser? u) {
    _user = u;
    _controller.add(u);
  }

  @override
  Stream<AuthUser?> authChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  Future<Result<SignUpOutcome>> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _emit(AuthUser(id: demoUserId, email: email, displayName: displayName, emailConfirmed: true));
    return const Ok(SignUpOutcome(needsEmailVerification: false));
  }

  @override
  Future<Result<void>> signIn({required String email, required String password}) async {
    _emit(AuthUser(id: demoUserId, email: email, displayName: demoUserName, emailConfirmed: true));
    return const Ok(null);
  }

  @override
  Future<Result<void>> signOut() async {
    _emit(null);
    return const Ok(null);
  }

  @override
  Future<Result<void>> resendVerification(String email) async => const Ok(null);
}

class DemoProfileRepository implements ProfileRepository {
  String _name = demoUserName;
  Gender? _gender;

  @override
  Future<Result<List<VerificationBadge>>> myBadges() async => const Ok([VerificationBadge(kind: 'email')]);

  @override
  Future<Result<Profile?>> getMe() async => Ok(Profile(id: demoUserId, displayName: _name));

  @override
  Future<Result<Profile>> updateDisplayName(String name) async {
    _name = name.trim();
    return Ok(Profile(id: demoUserId, displayName: _name));
  }

  @override
  Future<Result<Gender?>> getMyGender() async => Ok(_gender);

  @override
  Future<Result<void>> setMyGender(Gender g) async {
    _gender = g;
    return const Ok(null);
  }

  @override
  Future<Result<void>> clearMyGender() async {
    _gender = null;
    return const Ok(null);
  }
}

class DemoTripRepository implements TripRepository {
  Trip? _active = demoTrip();
  List<Trip> _finished = demoHistoryTrips();

  /// Set by the wiring: true when [tripId] (a Driver trip) has a Rider who boarded.
  bool Function(String tripId)? hasBoardedRider;

  /// Set by the wiring: true when [tripId] has a pending request or an accepted match (locks the drop-off limit).
  bool Function(String tripId)? hasOpenMatch;

  /// Demo hub: removes the trip so the create-trip flow becomes reachable.
  void clear() => _active = null;
  void reset([DemoScenario scenario = DemoScenario.peer]) {
    final role = scenario.role;
    _active = role == null ? demoTrip() : demoCarTrip(role);
    _finished = demoHistoryTrips();
  }

  Trip? get active => _active;

  @override
  Future<Result<Trip?>> activeTrip() async {
    await _wait();
    return Ok(_active);
  }

  @override
  Future<Result<Trip>> createTrip(TripDraft d) async {
    await _wait();
    return Ok(
      _active = Trip(
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
        maxDropoffM: d.role == TripRole.driver ? (d.maxDropoffM ?? dropoffDefaultM) : null,
        detourToleranceM: d.role == TripRole.driver ? (d.detourToleranceM ?? detourDefaultM) : null,
        vibeTags: d.vibeTags,
        moodText: (d.moodText ?? '').trim().isEmpty ? null : d.moodText!.trim(),
        moodSetAt: (d.moodText ?? '').trim().isEmpty && d.vibeTags.isEmpty ? null : DateTime.now(),
        womenOnly: d.womenOnly,
      ),
    );
  }

  @override
  Future<Result<Trip>> updateVibeMood(String id, {required List<String> vibeTags, required String? moodText}) async {
    await _wait();
    final t = _active;
    if (t == null || t.id != id) return const Err(AppFailure('GWM_TRIP_NOT_FOUND'));
    final mood = (moodText ?? '').trim().isEmpty ? null : moodText!.trim();
    return Ok(_active = t.copyWith(vibeTags: vibeTags, moodText: () => mood, moodSetAt: () => DateTime.now()));
  }

  @override
  Future<Result<Trip>> updateWomenOnly(String id, bool value) async {
    await _wait();
    final t = _active;
    if (t == null || t.id != id) return const Err(AppFailure('GWM_TRIP_NOT_FOUND'));
    return Ok(_active = t.copyWith(womenOnly: value));
  }

  @override
  Future<Result<Trip>> updateMaxDropoff(String id, int metres) async {
    await _wait();
    final t = _active;
    if (t == null || t.id != id) return const Err(AppFailure('GWM_TRIP_NOT_FOUND'));
    if (t.role != TripRole.driver) return const Err(AppFailure('GWM_DROPOFF_NOT_ALLOWED'));
    if (t.status != TripStatus.scheduled) return const Err(AppFailure('GWM_TRIP_STARTED'));
    if (hasOpenMatch?.call(id) ?? false) return const Err(AppFailure('GWM_TRIP_HAS_MATCHES'));
    if (metres < dropoffMinM || metres > dropoffMaxM || metres % dropoffStepM != 0) {
      return const Err(AppFailure('GWM_DROPOFF_INVALID'));
    }
    return Ok(_active = t.copyWith(maxDropoffM: metres));
  }

  @override
  Future<Result<Trip>> updateDetourTolerance(String id, int metres) async {
    await _wait();
    final t = _active;
    if (t == null || t.id != id) return const Err(AppFailure('GWM_TRIP_NOT_FOUND'));
    if (t.role != TripRole.driver) return const Err(AppFailure('GWM_DETOUR_NOT_ALLOWED'));
    if (t.status != TripStatus.scheduled) return const Err(AppFailure('GWM_TRIP_STARTED'));
    if (hasOpenMatch?.call(id) ?? false) return const Err(AppFailure('GWM_TRIP_HAS_MATCHES'));
    if (metres < detourMinM || metres > detourMaxM || metres % detourStepM != 0) {
      return const Err(AppFailure('GWM_DETOUR_INVALID'));
    }
    return Ok(_active = t.copyWith(detourToleranceM: metres));
  }

  Trip? _find(String id) {
    if (_active?.id == id) return _active;
    for (final t in _finished) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<Result<List<Trip>>> myTrips({required bool history, int limit = 20}) async {
    await _wait();
    return Ok(history ? List.of(_finished) : [?_active]);
  }

  @override
  Future<Result<Trip?>> tripById(String id) async {
    await _wait();
    return Ok(_find(id));
  }

  @override
  Future<Result<Trip>> transition(String id, TripAction action) async {
    await _wait();
    final t = _find(id);
    if (t == null) return const Err(AppFailure('GWM_TRIP_NOT_FOUND'));
    final next = TripStateMachine.apply(t.status, action);
    if (next == null) {
      return TripStateMachine.isAlreadyDone(t.status, action)
          ? Ok(t)
          : const Err(AppFailure('GWM_INVALID_TRIP_TRANSITION'));
    }
    // Q-1: a Driver cannot cancel once the Rider boarded (finishing is always allowed).
    if (action == TripAction.cancel && t.role == TripRole.driver && (hasBoardedRider?.call(t.id) ?? false)) {
      return const Err(AppFailure('GWM_ALREADY_BOARDED'));
    }
    final now = DateTime.now();
    final updated = t.copyWith(
      status: next,
      startedAt: next == TripStatus.inProgress ? now : null,
      endedAt: next.isTerminal ? now : null,
    );
    if (next.isTerminal) {
      _active = null;
      _finished = [updated, ..._finished];
    } else {
      _active = updated;
    }
    return Ok(updated);
  }

  @override
  Future<Result<void>> deleteTrip(String id) async {
    await _wait();
    _finished = [for (final t in _finished) if (t.id != id) t];
    return const Ok(null);
  }
}

/// Shares one match list with the finder so a sent request shows up on the
/// candidate row. In the car scenarios it also enforces the role rules the real
/// backend enforces (one accepted match, no cancel after boarding, boarding
/// needs both trips started, Driver opens the pickup proposal), so widget tests
/// and the hub see the same errors.
class DemoMatchRepository implements MatchRepository, MatchFinderRepository {
  DemoMatchRepository([this._trips]);

  final DemoTripRepository? _trips;
  DemoScenario _scenario = DemoScenario.peer;
  List<MatchSummary> _matches = demoMatches();
  final _changes = StreamController<void>.broadcast();

  DemoScenario get scenario => _scenario;
  TripRole? get _myRole => _scenario.role;

  List<MatchSummary> get matches => List.unmodifiable(_matches);
  MatchSummary? get acceptedCar =>
      _matches.where((m) => m.isCar && m.status == MatchStatus.accepted).firstOrNull;

  void reset([DemoScenario? scenario]) {
    _scenario = scenario ?? _scenario;
    _matches = _myRole == null ? demoMatches() : demoCarMatches(_myRole!);
    _changes.add(null);
  }

  // Hub simulations: the OTHER person acts. --------------------------------

  /// The partner's trip starts (Rider needs this before "ขึ้นรถแล้ว").
  void partnerStartsTrip() {
    _matches = [
      for (final m in _matches)
        m.status == MatchStatus.accepted ? m.copyWith(partnerTripStatus: TripStatus.inProgress) : m,
    ];
    _changes.add(null);
  }

  /// The partner ends the match. False when the rules forbid it (after boarding).
  bool partnerEndsMatch() {
    final m = acceptedCar;
    if (m == null || m.boarded) return false;
    _update(m.id, status: MatchStatus.cancelled);
    return true;
  }

  /// Driver scenario: the Rider says they boarded.
  bool partnerBoards() {
    final m = acceptedCar;
    if (m == null) return false;
    _update(m.id, boardedAt: DateTime.now());
    return true;
  }

  /// The partner proposes (or re-proposes) a pickup point near the demo route.
  bool partnerProposesPickup() {
    final m = acceptedCar;
    if (m == null || m.boarded) return false;
    _update(m.id,
        proposed: const LatLng(13.7453, 100.5340), proposedLabel: 'หน้าสยามพารากอน ประตู 1', proposedByMe: false);
    return true;
  }

  /// Hub: the next `request_match` fails as "too many requests" (send throttle) once.
  bool throttleNextRequest = false;

  /// Hub: the OTHER person accepts my oldest pending request (Match Moment). False when there is none.
  bool partnerAcceptsPending() {
    final m = _matches.where((x) => x.iAmRequester && x.status == MatchStatus.pending).firstOrNull;
    if (m == null) return false;
    _update(m.id, status: MatchStatus.accepted);
    return true;
  }

  /// Demo hub can cycle the category shown under an empty search.
  MatchHint hintForDemo = MatchHint.farDestination;

  /// US-50 (round 7 Stage D) hub toggle: adds `demoDetourOnlyCandidate` to the
  /// rider-view candidate list — see its doc comment (demo_data.dart).
  bool showDetourOnlyCandidate = false;

  @override
  Future<Result<MatchHint?>> matchHint(String tripId) async {
    await _wait();
    return Ok(hintForDemo);
  }

  @override
  Future<Result<List<MatchCandidate>>> findMatches(String tripId, {int limit = 20}) async {
    await _wait();
    final role = _myRole;
    if (role != null && (_trips?.active?.id == tripId)) {
      // Car: someone with an accepted match disappears from search (both roles).
      if (acceptedCar != null) return const Ok([]);
      return Ok([
        for (final c in demoCarCandidates(role,
            driverLimitM: _driverLimitM(role), driverDetourM: _driverDetourM(role), includeDetourOnly: showDetourOnlyCandidate))
          // A manually cancelled/declined pair is hidden (no re-request); an
          // auto-closed one shows again.
          if (_statusFor(c.tripId) != MatchStatus.cancelled && _statusFor(c.tripId) != MatchStatus.declined)
            switch (_statusFor(c.tripId)) {
              final s? => c.withRequestStatus(s),
              null => c,
            },
      ]);
    }
    return Ok([
      for (final c in demoCandidates())
        switch (_statusFor(c.tripId)) {
          final s? => c.withRequestStatus(s),
          null => c,
        },
    ]);
  }

  /// The Driver's own limit (I drive) applied to rider candidates; null when I ride (each driver row carries its own).
  int? _driverLimitM(TripRole mine) =>
      mine == TripRole.driver ? (_trips?.active?.maxDropoffM ?? dropoffDefaultM) : null;

  /// US-50: the Driver's own route-detour tolerance (I drive); null when I ride.
  int? _driverDetourM(TripRole mine) =>
      mine == TripRole.driver ? (_trips?.active?.detourToleranceM ?? detourDefaultM) : null;

  MatchStatus? _statusFor(String candidateId) {
    for (final m in _matches) {
      if (m.partnerTripId != candidateId) continue;
      if (m.status == MatchStatus.cancelled && m.autoClosed) continue; // may be re-sent
      if (m.status != MatchStatus.cancelled || _myRole != null) return m.status;
    }
    return null;
  }

  @override
  Future<Result<MatchRequestOutcome>> request({
    required String myTripId,
    required String targetTripId,
    double? clientDetourM,
  }) async {
    await _wait();
    if (throttleNextRequest) {
      throttleNextRequest = false;
      return const Err(AppFailure('GWM_RATE_LIMITED', retryable: true));
    }
    final role = _myRole;
    final pool = role == null
        ? demoCandidates()
        : demoCarCandidates(role, includeDetourOnly: showDetourOnlyCandidate);
    final c = pool.where((x) => x.tripId == targetTripId).firstOrNull;
    if (c == null) return const Err(AppFailure('GWM_TRIP_NOT_FOUND'));
    if (role != null && acceptedCar != null) return const Err(AppFailure('GWM_NOT_ELIGIBLE'));
    final pendingSent = _matches.where((m) => m.iAmRequester && m.status == MatchStatus.pending).length;
    if (pendingSent >= 5) return const Err(AppFailure('GWM_PENDING_LIMIT'));
    final id = 'demo-match-${_matches.length + 1}';
    _matches = [
      for (final m in _matches)
        if (!(m.partnerTripId == targetTripId && m.autoClosed)) m,
      MatchSummary(
        id: id,
        status: MatchStatus.pending,
        iAmRequester: true,
        myTripId: myTripId,
        partnerTripId: c.tripId,
        partnerName: c.displayName,
        badges: c.badges,
        mode: c.mode,
        departAt: c.departAt,
        overlapPct: c.overlapPct,
        approxOrigin: c.approxOrigin,
        approxDest: c.approxDest,
        meetingPoint: null,
        meetingLabel: null,
        proposedPoint: null,
        proposedLabel: null,
        proposedByMe: false,
        createdAt: DateTime.now(),
        partnerId: 'demo-user-${c.tripId}',
        myRole: role,
        partnerRole: role?.opposite,
        partnerTripStatus: TripStatus.scheduled,
      ),
    ];
    _changes.add(null);
    return Ok(MatchRequestOutcome(matchId: id, status: MatchStatus.pending, iAmRequester: true));
  }

  @override
  Future<Result<List<MatchSummary>>> inbox() async => Ok(List.of(_matches));

  @override
  Future<Result<MatchStatus>> respond(String matchId, {required bool accept}) async {
    await _wait();
    final s = accept ? MatchStatus.accepted : MatchStatus.declined;
    if (accept && _myRole != null) {
      if (acceptedCar != null) return const Err(AppFailure('GWM_MATCH_LIMIT'));
      // Accepting closes every other pending request, neutrally (auto_closed).
      _matches = [
        for (final m in _matches)
          if (m.id != matchId && m.status == MatchStatus.pending)
            m.copyWith(status: MatchStatus.cancelled, autoClosed: true)
          else
            m,
      ];
    }
    _update(matchId, status: s);
    return Ok(s);
  }

  @override
  Future<Result<void>> cancel(String matchId) async {
    await _wait();
    final m = _matches.where((x) => x.id == matchId).firstOrNull;
    if (m != null && m.isCar && m.boarded) return const Err(AppFailure('GWM_ALREADY_BOARDED'));
    _update(matchId, status: MatchStatus.cancelled);
    return const Ok(null);
  }

  @override
  Future<Result<bool>> cancelPending(String matchId) async {
    await _wait();
    final m = _matches.where((x) => x.id == matchId).firstOrNull;
    if (m == null) return const Err(AppFailure('GWM_MATCH_NOT_FOUND'));
    if (m.status == MatchStatus.cancelled) return const Ok(false);
    if (m.status != MatchStatus.pending) return const Err(AppFailure('GWM_MATCH_NOT_PENDING'));
    _update(matchId, status: MatchStatus.cancelled);
    return const Ok(true);
  }

  @override
  Future<Result<bool>> proposeMeetingPoint(String matchId, LatLng point, String label) async {
    await _wait();
    final m = _matches.where((x) => x.id == matchId).firstOrNull;
    if (m != null && m.isCar) {
      if (m.boarded) return const Err(AppFailure('GWM_ALREADY_BOARDED'));
      if (m.iAmRider && m.proposedPoint == null && m.meetingPoint == null) {
        return const Err(AppFailure('GWM_PICKUP_DRIVER_FIRST'));
      }
    }
    _update(matchId, proposed: point, proposedLabel: label, proposedByMe: true);
    // Boolean only (never the distance): same contract as the server.
    final route = _trips?.active?.route ?? demoRoute(demoPlaces[0].point, demoPlaces[2].point);
    return Ok(m != null && m.isCar && distanceToRouteM(point, route) > 500);
  }

  @override
  Future<Result<DateTime>> markBoarded(String matchId) async {
    await _wait();
    final m = _matches.where((x) => x.id == matchId && x.status == MatchStatus.accepted).firstOrNull;
    if (m == null) return const Err(AppFailure('GWM_MATCH_NOT_FOUND'));
    if (!m.iAmRider) return const Err(AppFailure('GWM_NOT_RIDER'));
    if (m.boardedAt != null) return Ok(m.boardedAt!);
    final mine = _trips?.active;
    if (mine?.status != TripStatus.inProgress || m.partnerTripStatus != TripStatus.inProgress) {
      return const Err(AppFailure('GWM_TRIP_NOT_STARTED'));
    }
    final at = DateTime.now();
    _update(matchId, boardedAt: at);
    return Ok(at);
  }

  @override
  Future<Result<void>> reportRiderNoShow(String matchId) async {
    await _wait();
    final m = _matches.where((x) => x.id == matchId && x.status == MatchStatus.accepted).firstOrNull;
    if (m == null) return const Err(AppFailure('GWM_MATCH_NOT_FOUND'));
    if (!m.iAmDriver) return const Err(AppFailure('GWM_NO_SHOW_NOT_ALLOWED'));
    if (m.boarded) return const Err(AppFailure('GWM_ALREADY_BOARDED'));
    if (_trips?.active?.status != TripStatus.inProgress) return const Err(AppFailure('GWM_NO_SHOW_NOT_ALLOWED'));
    _update(matchId, status: MatchStatus.cancelled);
    return const Ok(null);
  }

  /// US-49 demo hub toggle: mirrors the server's own re-check — the client's lateness card is only
  /// ever a HINT (`_match_overdue`, migration 0014). Default false: shows `GWM_NOT_OVERDUE` so the
  /// "handle the rejection gracefully" path can be demoed even when the timing looks off client-side.
  bool demoServerConfirmsOverdue = false;

  @override
  Future<Result<String>> cancelNoFault(String matchId) async {
    await _wait();
    final m = _matches.where((x) => x.id == matchId).firstOrNull;
    if (m == null) return const Err(AppFailure('GWM_MATCH_NOT_FOUND'));
    if (!m.isCar) return const Err(AppFailure('GWM_NOT_ELIGIBLE'));
    if (m.status == MatchStatus.cancelled) return const Ok('already_cancelled');
    if (m.status != MatchStatus.accepted || m.boarded) return const Err(AppFailure('GWM_MATCH_NOT_FOUND'));
    if (!demoServerConfirmsOverdue) return const Err(AppFailure('GWM_NOT_OVERDUE'));
    _update(matchId, status: MatchStatus.cancelled);
    return const Ok('cancelled');
  }

  @override
  Future<Result<void>> confirmMeetingPoint(String matchId) async {
    await _wait();
    _matches = [
      for (final m in _matches)
        if (m.id == matchId)
          m.copyWith(meetingPoint: m.proposedPoint, meetingLabel: m.proposedLabel, clearProposal: true)
        else
          m,
    ];
    _changes.add(null);
    return const Ok(null);
  }

  @override
  Stream<void> changes() => _changes.stream;

  void _update(String id,
      {MatchStatus? status,
      LatLng? proposed,
      String? proposedLabel,
      bool? proposedByMe,
      DateTime? boardedAt}) {
    _matches = [
      for (final m in _matches)
        if (m.id == id)
          m.copyWith(
            status: status,
            proposedPoint: proposed,
            proposedLabel: proposedLabel,
            proposedByMe: proposedByMe,
            boardedAt: boardedAt,
          )
        else
          m,
    ];
    _changes.add(null);
  }
}

/// In-memory vehicle store. The Driver scenario starts with a vehicle; the
/// Rider sees a fixed partner vehicle for matches that are accepted (or that
/// ended after boarding, PM Q-2). [partnerShareAllowed] is the hub switch.
class DemoVehicleRepository implements VehicleRepository {
  DemoVehicleRepository(this._matches, this._trips);
  final DemoMatchRepository _matches;
  final DemoTripRepository _trips;

  Vehicle? _mine = demoVehicle;
  final partnerShareAllowed = ValueNotifier<bool>(false);

  /// Wired to the demo role repository: a registered driver's vehicle cannot be deleted (GWM_DRIVER_REGISTERED).
  bool Function()? isRegistered;

  bool get hasVehicle => _mine != null;

  void reset(DemoScenario scenario) {
    _mine = scenario == DemoScenario.rider ? null : demoVehicle;
    partnerShareAllowed.value = false;
  }

  void clear() => _mine = null;

  @override
  Future<Result<Vehicle?>> mine() async {
    await _wait();
    return Ok(_mine);
  }

  @override
  Future<Result<void>> save(VehicleInput input) async {
    await _wait();
    _mine = Vehicle(
      plate: input.plate,
      model: input.model,
      color: input.color,
      shareConsent: _mine?.shareConsent ?? false,
    );
    return const Ok(null);
  }

  @override
  Future<Result<void>> setShareConsent(bool on) async {
    await _wait();
    if (_mine == null) return const Err(AppFailure('GWM_VEHICLE_REQUIRED'));
    _mine = _mine!.copyWith(shareConsent: on);
    return const Ok(null);
  }

  @override
  Future<Result<void>> deleteMine() async {
    await _wait();
    final driving = _matches.acceptedCar?.iAmDriver ?? false;
    final activeDriverTrip = _trips.active?.role == TripRole.driver && (_trips.active?.status.isActive ?? false);
    if (driving || activeDriverTrip) return const Err(AppFailure('GWM_VEHICLE_IN_USE'));
    if (isRegistered?.call() ?? false) return const Err(AppFailure('GWM_DRIVER_REGISTERED'));
    _mine = null;
    return const Ok(null);
  }

  @override
  Future<Result<VehicleView?>> forMatch(String matchId) async {
    await _wait();
    final m = _matches.matches.where((x) => x.id == matchId).firstOrNull;
    if (m == null || !m.iAmRider) return const Ok(null);
    final visible = m.status == MatchStatus.accepted || (m.boarded && m.status == MatchStatus.cancelled);
    if (!visible) return const Ok(null);
    return Ok(demoPartnerVehicle(shareAllowed: partnerShareAllowed.value));
  }
}

class DemoGeocoding implements GeocodingService {
  @override
  Future<List<PlaceSuggestion>> search(String query) async {
    await _wait();
    final q = query.trim().toLowerCase();
    return [
      for (final p in demoPlaces)
        if (p.label.toLowerCase().contains(q)) p,
    ];
  }

  @override
  Future<String> reverse(LatLng p) async {
    PlaceSuggestion? best;
    var bestD = double.infinity;
    for (final c in demoPlaces) {
      final d = haversineM(c.point, p);
      if (d < bestD) {
        best = c;
        bestD = d;
      }
    }
    if (best != null && bestD < 800) return best.label;
    return 'ตำแหน่งที่เลือก (เดโม)';
  }
}

/// DEMO ONLY: not real road routing. Straight line with a bent waypoint.
class DemoRouting implements RoutingService {
  /// US-50 (round 7 Stage D): the hub's "จำลอง: บริการ OSRM ล้มเหลว" toggle —
  /// the NEXT `route()` call throws (simulating a timeout/network failure
  /// mid `computePreciseDetourM`), then resets to false so only one demo
  /// candidate's precise-detour attempt is affected.
  bool failNextRoute = false;

  @override
  Future<RouteResult> route({
    required TravelMode mode,
    required LatLng from,
    required LatLng to,
  }) async {
    await _wait();
    if (failNextRoute) {
      failNextRoute = false;
      throw const AppFailure(FailureCode.networkTimeout, retryable: true);
    }
    final meters = (haversineM(from, to) * 1.3).round();
    final seconds = (meters / 1000 / mode.avgKmh * 3600).round();
    return RouteResult(geometry: demoRoute(from, to), distanceM: meters, durationS: seconds);
  }
}

/// Permission always granted. [watch] walks the user along their trip route
/// (one fix per 2 s, arriving after ~60 s) so the map, remaining distance and
/// the "near destination" prompt can all be seen. DEMO ONLY.
class DemoLocationService implements LocationService {
  DemoLocationService(this._trips);
  final DemoTripRepository _trips;

  @override
  Future<LocationPermissionState> permission() async => LocationPermissionState.granted;

  @override
  Future<LocationPermissionState> request() async => LocationPermissionState.granted;

  @override
  Future<Result<LatLng>> currentPosition() async => Ok(demoPlaces[0].point);

  @override
  Stream<LocationFix> watch() {
    final route = (_trips.active?.route.length ?? 0) >= 2 ? _trips.active!.route : demoTrip().route;
    return Stream.periodic(const Duration(seconds: 2), (i) => i).map((i) {
      final f = ((i + 1) / 30).clamp(0.0, 1.0);
      final pos = f * (route.length - 1);
      final k = pos.floor().clamp(0, route.length - 2);
      final r = pos - k;
      final a = route[k];
      final b = route[k + 1];
      return LocationFix(
        point: LatLng(a.latitude + (b.latitude - a.latitude) * r, a.longitude + (b.longitude - a.longitude) * r),
        at: DateTime.now(),
        accuracyM: 12,
      );
    });
  }
}

class DemoConsentRepository implements ConsentRepository {
  bool _location = true;

  @override
  Future<Result<bool>> locationConsentGranted() async => Ok(_location);

  @override
  Future<Result<void>> recordLocationConsent({
    required bool granted,
    required String policyVersion,
  }) async {
    _location = granted;
    return const Ok(null);
  }
}
