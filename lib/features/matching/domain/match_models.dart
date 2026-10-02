import 'package:latlong2/latlong.dart';

import '../../../core/l10n/strings_r5.dart';
import '../../trip/domain/travel_mode.dart';
import '../../trip/domain/trip.dart' show TripRole, TripStatus;
export '../../trip/domain/dropoff.dart';

enum MatchStatus {
  pending('pending'),
  accepted('accepted'),
  declined('declined'),
  cancelled('cancelled');

  const MatchStatus(this.db);
  final String db;

  static MatchStatus? fromDb(Object? v) {
    for (final s in values) {
      if (s.db == v) return s;
    }
    return null;
  }
}

/// One verification badge as returned by `user_badges()`:
/// `{kind: email|organization|phone, is_mock, org_name}`.
class VerificationBadge {
  const VerificationBadge({required this.kind, this.isMock = false, this.orgName});
  final String kind;
  final bool isMock;
  final String? orgName;

  String get label => switch (kind) {
        'email' => 'ยืนยันอีเมลแล้ว',
        'organization' => (orgName == null || orgName!.isEmpty) ? 'ยืนยันองค์กรแล้ว' : 'องค์กร: $orgName',
        'phone' => isMock ? 'เบอร์โทร (โหมดจำลอง)' : 'ยืนยันเบอร์โทรแล้ว',
        _ => 'ยืนยันแล้ว',
      };
}

List<VerificationBadge> parseBadges(Object? v) {
  if (v is! List) return const [];
  return [
    for (final b in v)
      if (b is Map && b['kind'] is String)
        VerificationBadge(
          kind: b['kind'] as String,
          isMock: b['is_mock'] == true,
          orgName: b['org_name'] as String?,
        ),
  ];
}

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');

LatLng? _ll(Object? lat, Object? lng) {
  final la = _num(lat);
  final ln = _num(lng);
  if (la == null || ln == null) return null;
  return LatLng(la, ln);
}

/// (avg, count) only when both are usable; anything else (null, NaN, out of 0..5, count < 1) -> (null, null).
(double?, int?) _rating(Object? avg, Object? count) {
  final a = _num(avg);
  final n = _num(count)?.round();
  if (a == null || n == null || a.isNaN || a < 0 || a > 5 || n < 1) return (null, null);
  return (a, n);
}

/// A person from `find_matches`. By construction this type has NO exact
/// coordinates: origin/destination are the server-blurred cell centres and the
/// distance is bucketed to 500 m (design-security).
class MatchCandidate {
  const MatchCandidate({
    required this.tripId,
    required this.displayName,
    required this.badges,
    required this.mode,
    required this.departAt,
    required this.timeDiffMin,
    required this.overlapPct,
    required this.approxDistanceM,
    required this.score,
    required this.approxOrigin,
    required this.approxDest,
    required this.requestStatus,
    this.role,
    this.maxDropoffM,
    this.ratingAvg,
    this.ratingCount,
    this.vibeTags = const [],
    this.moodText,
  });

  final String tripId;
  final String displayName;
  final List<VerificationBadge> badges;
  final TravelMode mode;
  final DateTime departAt;
  final int timeDiffMin;
  final int overlapPct;
  final int approxDistanceM;
  final double score;
  final LatLng approxOrigin;
  /// Null when the candidate is a car Rider (driver searching): the server never reveals a Rider's destination.
  final LatLng? approxDest;

  /// Status of an existing request between the two trips, null if none.
  final MatchStatus? requestStatus;

  /// Driver/Rider of the candidate's trip (car mode only). Never any vehicle data.
  final TripRole? role;

  /// Car Driver candidate only (rider searching): the Driver's effective drop-off limit in metres
  /// (`find_matches.max_dropoff_m`). Null otherwise.
  final int? maxDropoffM;

  /// Anonymous rating aggregate for the role of this trip (`find_matches.rating_avg` / `rating_count`, migration 0010).
  /// Both null unless the server decided it may be shown (>= 3 revealed reviews); also null on an older server.
  final double? ratingAvg;
  final int? ratingCount;

  /// US-44 (round 7): the candidate trip's own vibe tags/mood, if the server
  /// exposes them on this row (older servers omit the columns -> defaults).
  /// Never a source of safety info: never hides badge/role/distance.
  final List<String> vibeTags;
  final String? moodText;

  /// True only when BOTH parts are present (and sane): the only case where anything is drawn.
  bool get hasRating => ratingAvg != null && ratingCount != null && ratingCount! > 0;

  /// Null when the row is unusable (unknown mode, missing blurred point...);
  /// the caller drops such rows instead of crashing the list.
  static MatchCandidate? fromJson(Map<String, dynamic> j) {
    final mode = TravelMode.fromDb(j['mode']);
    final origin = _ll(j['approx_origin_lat'], j['approx_origin_lng']);
    final dest = _ll(j['approx_dest_lat'], j['approx_dest_lng']);
    final depart = DateTime.tryParse('${j['depart_at']}');
    final id = j['trip_id'];
    if (mode == null || origin == null || depart == null || id is! String) return null;
    return MatchCandidate(
      tripId: id,
      displayName: ((j['display_name'] as String?) ?? '').trim().isEmpty
          ? 'ผู้ใช้'
          : (j['display_name'] as String).trim(),
      badges: parseBadges(j['badges']),
      mode: mode,
      departAt: depart.toLocal(),
      timeDiffMin: _num(j['time_diff_min'])?.round() ?? 0,
      overlapPct: (_num(j['overlap_pct'])?.round() ?? 0).clamp(0, 100),
      approxDistanceM: _num(j['approx_distance_m'])?.round() ?? 0,
      score: _num(j['score']) ?? 0,
      approxOrigin: origin,
      approxDest: dest,
      requestStatus: MatchStatus.fromDb(j['request_status']),
      role: mode == TravelMode.car ? TripRole.fromDb(j['role']) : null,
      maxDropoffM: mode == TravelMode.car ? _num(j['max_dropoff_m'])?.round() : null,
      ratingAvg: _rating(j['rating_avg'], j['rating_count']).$1,
      ratingCount: _rating(j['rating_avg'], j['rating_count']).$2,
      vibeTags: (j['vibe_tags'] as List?)?.whereType<String>().toList() ?? const [],
      moodText: (j['mood_text'] as String?)?.trim().isEmpty ?? true ? null : (j['mood_text'] as String).trim(),
    );
  }

  /// After a request was cancelled (undo): the person is a candidate again.
  MatchCandidate withoutRequest() => MatchCandidate(
        tripId: tripId,
        displayName: displayName,
        badges: badges,
        mode: mode,
        departAt: departAt,
        timeDiffMin: timeDiffMin,
        overlapPct: overlapPct,
        approxDistanceM: approxDistanceM,
        score: score,
        approxOrigin: approxOrigin,
        approxDest: approxDest,
        requestStatus: null,
        role: role,
        maxDropoffM: maxDropoffM,
        ratingAvg: ratingAvg,
        ratingCount: ratingCount,
        vibeTags: vibeTags,
        moodText: moodText,
      );

  MatchCandidate withRequestStatus(MatchStatus s) => MatchCandidate(
        tripId: tripId,
        displayName: displayName,
        badges: badges,
        mode: mode,
        departAt: departAt,
        timeDiffMin: timeDiffMin,
        overlapPct: overlapPct,
        approxDistanceM: approxDistanceM,
        score: score,
        approxOrigin: approxOrigin,
        approxDest: approxDest,
        requestStatus: s,
        role: role,
        maxDropoffM: maxDropoffM,
        ratingAvg: ratingAvg,
        ratingCount: ratingCount,
        vibeTags: vibeTags,
        moodText: moodText,
      );
}

/// Result of `request_match` after idempotent-retry resolution.
class MatchRequestOutcome {
  const MatchRequestOutcome({required this.matchId, required this.status, required this.iAmRequester});
  final String matchId;
  final MatchStatus status;

  /// False when the other side had asked first and the request auto-accepted.
  final bool iAmRequester;
}

/// A row of `matches` for the caller, joined with the partner's blurred card
/// (available only while pending/accepted). Real meeting coordinates are
/// intentionally allowed here: they are chosen by both people after matching.
class MatchSummary {
  const MatchSummary({
    required this.id,
    required this.status,
    required this.iAmRequester,
    required this.myTripId,
    required this.partnerTripId,
    required this.partnerName,
    required this.badges,
    required this.mode,
    required this.departAt,
    required this.overlapPct,
    required this.approxOrigin,
    required this.approxDest,
    required this.meetingPoint,
    required this.meetingLabel,
    required this.proposedPoint,
    required this.proposedLabel,
    required this.proposedByMe,
    required this.createdAt,
    this.partnerId,
    this.myRole,
    this.partnerRole,
    this.boardedAt,
    this.autoClosed = false,
    this.partnerTripStatus,
  });

  final String id;
  final MatchStatus status;
  final bool iAmRequester;

  /// Partner's user id (needed for block/report); null in old fixtures.
  final String? partnerId;
  final String myTripId;
  final String partnerTripId;
  final String? partnerName;
  final List<VerificationBadge> badges;
  final TravelMode? mode;
  final DateTime? departAt;
  final int? overlapPct;
  final LatLng? approxOrigin;
  final LatLng? approxDest;
  final LatLng? meetingPoint;
  final String? meetingLabel;
  final LatLng? proposedPoint;
  final String? proposedLabel;

  /// Only meaningful when [proposedPoint] != null.
  final bool proposedByMe;
  final DateTime createdAt;

  /// Car matches only: my role / the partner's role (null for peer matches).
  final TripRole? myRole;
  final TripRole? partnerRole;

  /// Set when the Rider pressed "ขึ้นรถแล้ว". After that the match can no
  /// longer be cancelled by either side and the Rider's position is not
  /// shown to the Driver.
  final DateTime? boardedAt;

  /// A pending request that was closed because one of the two trips got its
  /// one accepted match. Shown neutrally as "closed"; may be re-sent.
  final bool autoClosed;

  /// Status of the partner's trip (from `get_trip_card`; only while pending/accepted).
  final TripStatus? partnerTripStatus;

  bool get isCar => myRole != null;
  bool get iAmDriver => myRole == TripRole.driver;
  bool get iAmRider => myRole == TripRole.rider;
  bool get boarded => boardedAt != null;
  bool get isEnded => status == MatchStatus.cancelled && !autoClosed;

  MatchSummary copyWith({
    MatchStatus? status,
    DateTime? boardedAt,
    bool? autoClosed,
    TripStatus? partnerTripStatus,
    LatLng? meetingPoint,
    String? meetingLabel,
    LatLng? proposedPoint,
    String? proposedLabel,
    bool? proposedByMe,
    bool clearProposal = false,
  }) =>
      MatchSummary(
        id: id,
        status: status ?? this.status,
        iAmRequester: iAmRequester,
        myTripId: myTripId,
        partnerTripId: partnerTripId,
        partnerName: partnerName,
        badges: badges,
        mode: mode,
        departAt: departAt,
        overlapPct: overlapPct,
        approxOrigin: approxOrigin,
        approxDest: approxDest,
        meetingPoint: meetingPoint ?? this.meetingPoint,
        meetingLabel: meetingLabel ?? this.meetingLabel,
        proposedPoint: clearProposal ? null : (proposedPoint ?? this.proposedPoint),
        proposedLabel: clearProposal ? null : (proposedLabel ?? this.proposedLabel),
        proposedByMe: clearProposal ? false : (proposedByMe ?? this.proposedByMe),
        createdAt: createdAt,
        partnerId: partnerId,
        myRole: myRole,
        partnerRole: partnerRole,
        boardedAt: boardedAt ?? this.boardedAt,
        autoClosed: autoClosed ?? this.autoClosed,
        partnerTripStatus: partnerTripStatus ?? this.partnerTripStatus,
      );

  bool get isIncomingPending => status == MatchStatus.pending && !iAmRequester;
  bool get hasProposalFromPartner => proposedPoint != null && !proposedByMe;

  String get displayName => (partnerName == null || partnerName!.isEmpty) ? 'ผู้ใช้' : partnerName!;
}

/// `get_match_hint` result (P1): one coarse category, never numbers, times, places or people.
enum MatchHint {
  hasResults('has_results'),
  noneFound('none_found'),
  farDestination('far_destination'),
  farOrigin('far_origin');

  const MatchHint(this.db);
  final String db;

  /// Unknown values (newer server) map to null so the UI shows the generic text.
  static MatchHint? fromDb(Object? v) {
    for (final h in values) {
      if (h.db == v) return h;
    }
    return null;
  }
}

/// Copy for a hint category (round 5 section 6). One sentence, never numbers/times/places/people.
/// [role] is MY trip's role (null = peer mode). Null result = show nothing (results exist).
/// An unknown / unreadable category ([hint] null) gets the generic text.
String? matchHintMessage(MatchHint? hint, {required TripRole? role}) {
  switch (hint) {
    case MatchHint.hasResults:
      return null;
    case MatchHint.noneFound:
      return switch (role) {
        TripRole.driver => R5.noneNoRider, // I drive: nobody who wants a ride is waiting
        TripRole.rider => R5.noneNoDriver,
        null => R5.noneGeneric,
      };
    case MatchHint.farDestination:
      return role == null ? R5.nonePeerRoute : R5.noneFarDest;
    case MatchHint.farOrigin:
      return R5.noneFarOrigin;
    case null:
      return R5.noneGeneric;
  }
}
