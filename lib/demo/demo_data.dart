import 'package:latlong2/latlong.dart';

import '../features/geo/domain/geo_services.dart';
import '../features/matching/domain/match_models.dart';
import '../features/trip/domain/detour.dart';
import '../features/trip/domain/travel_mode.dart';
import '../features/trip/domain/trip.dart';
import '../features/vehicle/domain/vehicle.dart';

/// Realistic Bangkok sample data. Everything here is fictional.
const demoUserId = 'demo-user';
const demoUserName = 'มิ้นท์';
const demoUserEmail = 'demo@gowithme.example';

const demoPlaces = <PlaceSuggestion>[
  PlaceSuggestion(label: 'สยามพารากอน, ปทุมวัน', point: LatLng(13.7461, 100.5347)),
  PlaceSuggestion(label: 'เซ็นทรัลเวิลด์, ปทุมวัน', point: LatLng(13.7466, 100.5393)),
  PlaceSuggestion(label: 'สถานีหมอชิต, จตุจักร', point: LatLng(13.8022, 100.5536)),
  PlaceSuggestion(label: 'ตลาดนัดจตุจักร', point: LatLng(13.7999, 100.5502)),
  PlaceSuggestion(label: 'อนุสาวรีย์ชัยสมรภูมิ', point: LatLng(13.7649, 100.5383)),
  PlaceSuggestion(label: 'สถานีอารีย์, พญาไท', point: LatLng(13.7797, 100.5449)),
  PlaceSuggestion(label: 'ทองหล่อ, วัฒนา', point: LatLng(13.7311, 100.5836)),
  PlaceSuggestion(label: 'สถานีอโศก, วัฒนา', point: LatLng(13.7371, 100.5605)),
  PlaceSuggestion(label: 'จุฬาลงกรณ์มหาวิทยาลัย', point: LatLng(13.7379, 100.5322)),
  PlaceSuggestion(label: 'ศาลาแดง, บางรัก', point: LatLng(13.7290, 100.5343)),
  PlaceSuggestion(label: 'มหาวิทยาลัยเกษตรศาสตร์, บางเขน', point: LatLng(13.8476, 100.5696)),
  PlaceSuggestion(label: 'ท่าพระจันทร์, พระนคร', point: LatLng(13.7565, 100.4892)),
  PlaceSuggestion(label: 'สนามบินดอนเมือง', point: LatLng(13.9126, 100.6068)),
];

/// The map only ever gets a ~1 km cell centre of another user's trip.
LatLng blurTo1km(LatLng p) => LatLng(
      (p.latitude / 0.01).floor() * 0.01 + 0.005,
      (p.longitude / 0.01).floor() * 0.01 + 0.005,
    );

Trip demoTrip({DateTime? now}) {
  final t = now ?? DateTime.now();
  return Trip(
    id: 'demo-trip-me',
    mode: TravelMode.transit,
    status: TripStatus.scheduled,
    origin: demoPlaces[0].point,
    dest: demoPlaces[2].point,
    originLabel: 'สยามพารากอน',
    destLabel: 'สถานีหมอชิต',
    route: demoRoute(demoPlaces[0].point, demoPlaces[2].point),
    distanceM: 7600,
    durationS: 1500,
    departAt: t.add(const Duration(minutes: 20)),
  );
}

/// Straight line with one bent waypoint and interpolated points. DEMO ONLY:
/// this is not a real road route.
List<LatLng> demoRoute(LatLng from, LatLng to, {int segments = 12}) {
  final dLat = to.latitude - from.latitude;
  final dLng = to.longitude - from.longitude;
  // Bend the middle sideways so it does not look like a ruler line.
  final bend = LatLng(-dLng * 0.12, dLat * 0.12);
  return [
    for (var i = 0; i <= segments; i++)
      () {
        final f = i / segments;
        final k = 4 * f * (1 - f); // 0 at the ends, 1 in the middle
        return LatLng(
          from.latitude + dLat * f + bend.latitude * k,
          from.longitude + dLng * f + bend.longitude * k,
        );
      }(),
  ];
}

class _Person {
  const _Person(this.tripId, this.name, this.badges, this.mode, this.min, this.overlap, this.distM,
      this.score, this.origin, this.dest);
  final String tripId;
  final String name;
  final List<VerificationBadge> badges;
  final TravelMode mode;
  final int min;
  final int overlap;
  final int distM;
  final double score;
  final LatLng origin;
  final LatLng dest;
}

const _email = VerificationBadge(kind: 'email');
const _org = VerificationBadge(kind: 'organization', orgName: 'จุฬาลงกรณ์มหาวิทยาลัย');

const _people = <_Person>[
  _Person('demo-cand-1', 'นุ่น', [_email, _org], TravelMode.transit, 5, 84, 600, 92,
      LatLng(13.7500, 100.5330), LatLng(13.7990, 100.5500)),
  _Person('demo-cand-2', 'ต้นไม้', [_email], TravelMode.transit, 10, 76, 1100, 85,
      LatLng(13.7440, 100.5410), LatLng(13.8060, 100.5560)),
  _Person('demo-cand-3', 'พลอย', [_email], TravelMode.taxi, 3, 68, 1400, 78,
      LatLng(13.7420, 100.5290), LatLng(13.7800, 100.5440)),
  _Person('demo-cand-4', 'ภูมิ', [_email], TravelMode.transit, 15, 55, 1800, 64,
      LatLng(13.7560, 100.5380), LatLng(13.7650, 100.5390)),
  _Person('demo-cand-5', 'แพร', [_email], TravelMode.transit, 25, 41, 2300, 49,
      LatLng(13.7290, 100.5350), LatLng(13.8020, 100.5540)),
];

/// Candidate the demo user already received a pending request from.
const demoIncomingCandidateId = 'demo-cand-3';

/// Candidate the demo user already matched with.
const demoAcceptedCandidateId = 'demo-cand-2';

/// Only some demo people have enough reviews (the rest show nothing, like the real server).
const _demoRatings = <String, (double, int)>{'demo-cand-1': (4.8, 7), 'demo-cand-3': (4.2, 3), 'demo-cand-5': (4.6, 5)};

List<MatchCandidate> demoCandidates({DateTime? now}) {
  final t = now ?? DateTime.now();
  return [
    for (final p in _people)
      MatchCandidate(
        tripId: p.tripId,
        displayName: p.name,
        badges: p.badges,
        mode: p.mode,
        departAt: t.add(Duration(minutes: 20 + p.min)),
        timeDiffMin: p.min,
        overlapPct: p.overlap,
        approxDistanceM: p.distM,
        score: p.score,
        approxOrigin: blurTo1km(p.origin),
        approxDest: blurTo1km(p.dest),
        requestStatus: null,
        ratingAvg: _demoRatings[p.tripId]?.$1,
        ratingCount: _demoRatings[p.tripId]?.$2,
      ),
  ];
}

MatchSummary _summary(String candidateId, String id, MatchStatus status, bool iAmRequester,
    DateTime t, {LatLng? proposed, String? proposedLabel}) {
  final c = demoCandidates(now: t).firstWhere((x) => x.tripId == candidateId);
  return MatchSummary(
    id: id,
    status: status,
    iAmRequester: iAmRequester,
    myTripId: 'demo-trip-me',
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
    proposedPoint: proposed,
    proposedLabel: proposedLabel,
    proposedByMe: false,
    createdAt: t.subtract(const Duration(minutes: 12)),
    partnerId: 'demo-user-$candidateId',
  );
}

List<MatchSummary> demoMatches({DateTime? now}) {
  final t = now ?? DateTime.now();
  return [
    _summary(demoIncomingCandidateId, 'demo-match-pending', MatchStatus.pending, false, t),
    _summary(demoAcceptedCandidateId, 'demo-match-accepted', MatchStatus.accepted, true, t,
        proposed: const LatLng(13.7453, 100.5340), proposedLabel: 'หน้าสยามพารากอน ประตู 1'),
  ];
}

/// Finished trips for the "history" tab (completed, cancelled, expired).
List<Trip> demoHistoryTrips({DateTime? now}) {
  final t = now ?? DateTime.now();
  Trip make(String id, TripStatus status, int a, int b, String from, String to, Duration ago,
      {bool ran = false}) {
    final depart = t.subtract(ago);
    return Trip(
      id: id,
      mode: TravelMode.transit,
      status: status,
      origin: demoPlaces[a].point,
      dest: demoPlaces[b].point,
      originLabel: from,
      destLabel: to,
      route: demoRoute(demoPlaces[a].point, demoPlaces[b].point),
      distanceM: 6200,
      durationS: 1500,
      departAt: depart,
      startedAt: ran ? depart : null,
      endedAt: depart.add(const Duration(minutes: 27)),
    );
  }

  return [
    make('demo-trip-h1', TripStatus.completed, 8, 5, 'จุฬาลงกรณ์มหาวิทยาลัย', 'สถานีอารีย์',
        const Duration(days: 1, hours: 3), ran: true),
    make('demo-trip-h2', TripStatus.cancelled, 0, 6, 'สยามพารากอน', 'ทองหล่อ', const Duration(days: 2)),
    make('demo-trip-h3', TripStatus.expired, 9, 2, 'ศาลาแดง', 'สถานีหมอชิต', const Duration(days: 3)),
  ];
}

/// The accepted partner's real route (unblurred): they are matched, so the
/// live view may show their exact position. DEMO ONLY (straight-ish line).
List<LatLng> demoPartnerRoute() {
  final p = _people.firstWhere((x) => x.tripId == demoAcceptedCandidateId);
  return demoRoute(p.origin, p.dest);
}


/// Demo scenarios. `peer` is the original walk/transit demo (no roles);
/// `driver` / `rider` are car trips so every Driver/Rider flow can be walked
/// through without a backend (hub: "บทบาท").
enum DemoScenario {
  peer('เดิม (เดิน/รถสาธารณะ ไม่มีบทบาท)'),
  driver('คนขับ (รถส่วนตัว)'),
  rider('คนนั่ง (รถส่วนตัว)');

  const DemoScenario(this.label);
  final String label;

  TripRole? get role => switch (this) {
        peer => null,
        driver => TripRole.driver,
        rider => TripRole.rider,
      };
}

const demoVehicle = Vehicle(plate: '1กก 1234 กรุงเทพมหานคร', model: 'Toyota Yaris', color: 'ขาว');

/// The demo Driver a Rider gets matched with. [shareAllowed] is toggled from the hub.
VehicleView demoPartnerVehicle({bool shareAllowed = false}) => VehicleView(
      plate: 'ขข 5678 กรุงเทพมหานคร',
      model: 'Honda City',
      color: 'เทา/เงิน',
      shareAllowed: shareAllowed,
    );

Trip demoCarTrip(TripRole role, {DateTime? now}) {
  final t = now ?? DateTime.now();
  return Trip(
    id: 'demo-trip-me',
    mode: TravelMode.car,
    role: role,
    status: TripStatus.scheduled,
    origin: demoPlaces[0].point,
    dest: demoPlaces[2].point,
    originLabel: 'สยามพารากอน',
    destLabel: 'สถานีหมอชิต',
    route: demoRoute(demoPlaces[0].point, demoPlaces[2].point),
    distanceM: 7600,
    durationS: 1500,
    departAt: t.add(const Duration(minutes: 20)),
    maxDropoffM: role == TripRole.driver ? dropoffDefaultM : null,
    detourToleranceM: role == TripRole.driver ? detourDefaultM : null,
  );
}

/// Straight-line distance (m) between each demo car candidate's destination and the demo trip's
/// destination. Server-only knowledge in production; used here to apply the drop-off rule.
const demoCarDestGapM = [800, 1500, 1900, 2461];

/// Effective drop-off limit (m) of each demo Driver candidate (shown when I ride).
const demoCarDriverLimitM = [1000, 2000, 3000, 5000];

/// US-50 (round 7): approximate extra round-trip route distance (m) each demo candidate would add
/// if matched via the detour-tolerance path instead of `max_dropoff_m` (mirrors `_car_detour_approx_m`
/// server-side, but a fixed number here since there is no real OSRM/PostGIS in demo mode).
const demoCarDetourApproxM = [300, 700, 1200, 1800];

/// Each demo Driver candidate's own configured detour tolerance (m, shown when I ride).
const demoCarDriverDetourM = [300, 600, 900, 1200];

/// US-50 (round 7 Stage D): a distinct 5th car Driver candidate whose destination is far enough
/// from the demo Rider trip's own destination that the radial `max_dropoff_m` path ALONE would
/// fail — the detour-tolerance path is the only way it qualifies, so requesting it is the one demo
/// scenario that actually exercises the client-side PRECISE (OSRM) calculation
/// (`needsDetourPath` -> `computePreciseDetourM`) instead of it being short-circuited by the radial
/// path like every candidate above. Opt-in only (`demoCarCandidates(includeDetourOnly: true)`, hub
/// toggle "จำลอง: ผู้สมัครที่เข้าเกณฑ์ผ่านระยะเบี่ยงเท่านั้น") — off by default so every pre-existing
/// demo scenario/test is unaffected.
const demoDetourOnlyCandidateId = 'demo-cand-detour-only';
const demoDetourOnlyDropoffLimitM = 1000;

MatchCandidate demoDetourOnlyCandidate({DateTime? now}) {
  final t = now ?? DateTime.now();
  return MatchCandidate(
    tripId: demoDetourOnlyCandidateId,
    displayName: 'แนน',
    badges: const [VerificationBadge(kind: 'email')],
    mode: TravelMode.car,
    role: TripRole.driver,
    departAt: t.add(const Duration(minutes: 18)),
    timeDiffMin: 8,
    overlapPct: 65,
    approxDistanceM: 2000,
    score: 70,
    approxOrigin: blurTo1km(demoPlaces[4].point), // อนุสาวรีย์ชัยสมรภูมิ
    approxDest: blurTo1km(demoPlaces[12].point), // สนามบินดอนเมือง — ~13 km from the demo trip's own destination
    requestStatus: null,
    maxDropoffM: demoDetourOnlyDropoffLimitM,
    // US-44/BUG-R7-01 (0016): also doubles as the demo proof that vibe/mood chips reach the
    // candidate card/detail page now that find_matches returns them live.
    vibeTags: const ['เงียบ', 'ตรงเวลา'],
    moodText: 'วันนี้รีบหน่อยนะ ขอไปไวๆ',
  );
}

/// Car candidates: the opposite role of [mine]. Blurred like real results, no vehicle data.
/// A Rider candidate never carries a destination (privacy); a Driver candidate carries its limit.
/// [driverLimitM] (I drive): a rider passes when EITHER their destination gap is within my
/// `max_dropoff_m` limit OR within my [driverDetourM] route-detour tolerance (US-50: the two
/// mechanisms are OR'd, never AND'd — see `docs/design-roles.md` #15.5).
/// [includeDetourOnly] (I ride only): appends [demoDetourOnlyCandidate] — see its doc comment.
List<MatchCandidate> demoCarCandidates(
  TripRole mine, {
  DateTime? now,
  int? driverLimitM,
  int? driverDetourM,
  bool includeDetourOnly = false,
}) {
  final t = now ?? DateTime.now();
  return [
    for (final (i, c) in demoCandidates(now: t).take(4).indexed)
      if (mine == TripRole.rider
          ? (demoCarDestGapM[i] <= demoCarDriverLimitM[i] || demoCarDetourApproxM[i] <= demoCarDriverDetourM[i])
          : (driverLimitM == null
              ? true
              : demoCarDestGapM[i] <= driverLimitM || demoCarDetourApproxM[i] <= (driverDetourM ?? 0)))
      MatchCandidate(
        tripId: c.tripId,
        displayName: c.displayName,
        badges: c.badges,
        mode: TravelMode.car,
        role: mine.opposite,
        departAt: c.departAt,
        timeDiffMin: c.timeDiffMin,
        overlapPct: c.overlapPct,
        approxDistanceM: c.approxDistanceM,
        score: c.score,
        approxOrigin: c.approxOrigin,
        approxDest: mine == TripRole.driver ? null : c.approxDest,
        requestStatus: null,
        maxDropoffM: mine == TripRole.rider ? demoCarDriverLimitM[i] : null,
      ),
    if (includeDetourOnly && mine == TripRole.rider) demoDetourOnlyCandidate(now: t),
  ];
}

/// One incoming pending request from the opposite role (พลอย).
List<MatchSummary> demoCarMatches(TripRole mine, {DateTime? now}) {
  final t = now ?? DateTime.now();
  final c = demoCarCandidates(mine, now: t).firstWhere((x) => x.tripId == demoIncomingCandidateId);
  return [
    MatchSummary(
      id: 'demo-match-pending',
      status: MatchStatus.pending,
      iAmRequester: false,
      myTripId: 'demo-trip-me',
      partnerTripId: c.tripId,
      partnerName: c.displayName,
      badges: c.badges,
      mode: TravelMode.car,
      departAt: c.departAt,
      overlapPct: c.overlapPct,
      approxOrigin: c.approxOrigin,
      approxDest: c.approxDest,
      meetingPoint: null,
      meetingLabel: null,
      proposedPoint: null,
      proposedLabel: null,
      proposedByMe: false,
      createdAt: t.subtract(const Duration(minutes: 12)),
      partnerId: 'demo-user-${c.tripId}',
      myRole: mine,
      partnerRole: mine.opposite,
      partnerTripStatus: TripStatus.scheduled,
    ),
  ];
}
