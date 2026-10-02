import 'package:flutter/material.dart' show IconData, Icons;
import 'package:latlong2/latlong.dart';

import '../../../core/geo/geo.dart';

import 'travel_mode.dart';

/// DB enum `trip_status`. Legal transitions live in `TripStateMachine`.
enum TripStatus {
  scheduled('scheduled'),
  inProgress('in_progress'),
  completed('completed'),
  cancelled('cancelled'),
  expired('expired');

  const TripStatus(this.db);
  final String db;

  bool get isActive => this == scheduled || this == inProgress;
  bool get isTerminal => !isActive;

  static TripStatus? fromDb(Object? v) {
    for (final s in values) {
      if (s.db == v) return s;
    }
    return null;
  }
}

/// DB enum `trip_role` (US-16). Only meaningful for `mode == car`; the server
/// rejects a role on any other mode and a car trip without a role. Fixed at
/// creation (never editable). A Driver always takes exactly 1 companion
/// ([carSeats]); there is no seat input anywhere in the app.
enum TripRole {
  driver('driver', 'คนขับ', Icons.drive_eta),
  rider('rider', 'คนนั่ง', Icons.event_seat);

  const TripRole(this.db, this.label, this.icon);
  final String db;
  final String label;
  final IconData icon;

  TripRole get opposite => this == driver ? rider : driver;

  static TripRole? fromDb(Object? v) {
    for (final r in values) {
      if (r.db == v) return r;
    }
    return null;
  }
}

/// Constant capacity of a Driver trip (mirrors SQL `car_seats()`); not configurable.
const carSeats = 1;

/// Client-side mirror of the server compatibility rule. The backend is the
/// authority; this only filters defensively and drives UX.
bool tripsCompatible({
  required TravelMode myMode,
  TripRole? myRole,
  required TravelMode otherMode,
  TripRole? otherRole,
}) {
  if (myMode == TravelMode.car || otherMode == TravelMode.car) {
    return myMode == TravelMode.car &&
        otherMode == TravelMode.car &&
        myRole != null &&
        otherRole != null &&
        myRole != otherRole;
  }
  return true;
}

/// A place chosen by the user (search result, pin or current location).
class Place {
  const Place({required this.point, required this.label});
  final LatLng point;
  final String label;
}

/// The owner's own trip (real coordinates are only ever readable by the owner).
class Trip {
  const Trip({
    required this.id,
    required this.mode,
    required this.status,
    required this.origin,
    required this.dest,
    required this.originLabel,
    required this.destLabel,
    required this.route,
    required this.distanceM,
    required this.durationS,
    required this.departAt,
    this.startedAt,
    this.endedAt,
    this.role,
    this.maxDropoffM,
    this.detourToleranceM,
    this.vibeTags = const [],
    this.moodText,
    this.moodSetAt,
    this.womenOnly = false,
  });

  final String id;
  final TravelMode mode;
  final TripStatus status;
  final LatLng origin;
  final LatLng dest;
  final String originLabel;
  final String destLabel;
  final List<LatLng> route;
  final int distanceM;
  final int durationS;
  final DateTime departAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Driver/Rider for car trips; null for other modes (and legacy car trips).
  final TripRole? role;

  bool get isCar => mode == TravelMode.car;

  /// Old car trip without a role: never matched (F-R3.7).
  /// Driver trips only (`trips.max_dropoff_m`, metres 500..5000 step 100). Null for every other trip.
  final int? maxDropoffM;

  /// US-50 (round 7): driver trips only (`trips.detour_tolerance_m`, metres 200..2000 step 100).
  /// A SECOND, independent matching path OR'd with [maxDropoffM] server-side — measures the extra
  /// round-trip ROAD distance the driver accepts to detour to a rider's destination, not a radius.
  /// Null for every other trip.
  final int? detourToleranceM;

  /// US-44 (round 7): up to 3 tags from a role-specific allow-list, server-validated.
  /// Bound to this trip only (Q5) — auto-cleared on trip end or 24h.
  final List<String> vibeTags;

  /// US-44: free text <= 35 chars, guarded client+server (Q6). Null/empty = not set.
  final String? moodText;

  /// When `moodText` was last written (server `trips.mood_set_at`) — used only for
  /// a best-effort "just cleared" UX hint (`mood.autocleared_notice`); the server owns clearing.
  final DateTime? moodSetAt;

  /// US-45: this trip only wants Women-Only matches (server enforces gender=female
  /// live on both sides — never trust this flag alone for anything security-sensitive).
  final bool womenOnly;

  bool get isLegacyCarWithoutRole => isCar && role == null;

  Trip copyWith({
    TripStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    int? maxDropoffM,
    int? detourToleranceM,
    List<String>? vibeTags,
    String? Function()? moodText,
    DateTime? Function()? moodSetAt,
    bool? womenOnly,
  }) =>
      Trip(
        id: id,
        mode: mode,
        status: status ?? this.status,
        origin: origin,
        dest: dest,
        originLabel: originLabel,
        destLabel: destLabel,
        route: route,
        distanceM: distanceM,
        durationS: durationS,
        departAt: departAt,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        role: role,
        maxDropoffM: maxDropoffM ?? this.maxDropoffM,
        detourToleranceM: detourToleranceM ?? this.detourToleranceM,
        vibeTags: vibeTags ?? this.vibeTags,
        moodText: moodText != null ? moodText() : this.moodText,
        moodSetAt: moodSetAt != null ? moodSetAt() : this.moodSetAt,
        womenOnly: womenOnly ?? this.womenOnly,
      );

  /// Tolerant mapping of a `trips` row; null when a required field is unusable.
  static Trip? fromJson(Map<String, dynamic> j) {
    final mode = TravelMode.fromDb(j['mode']);
    final status = TripStatus.fromDb(j['status']);
    final origin = parsePoint(j['origin']);
    final dest = parsePoint(j['dest']);
    final depart = DateTime.tryParse('${j['depart_at']}');
    final id = j['id'];
    if (mode == null || status == null || origin == null || dest == null || depart == null || id is! String) {
      return null;
    }
    return Trip(
      id: id,
      mode: mode,
      status: status,
      origin: origin,
      dest: dest,
      originLabel: (j['origin_label'] as String?) ?? '',
      destLabel: (j['dest_label'] as String?) ?? '',
      route: parseLine(j['route']) ?? const [],
      distanceM: (j['route_distance_m'] as num?)?.toInt() ?? 0,
      durationS: (j['route_duration_s'] as num?)?.toInt() ?? 0,
      departAt: depart.toLocal(),
      startedAt: DateTime.tryParse('${j['started_at']}')?.toLocal(),
      endedAt: DateTime.tryParse('${j['ended_at']}')?.toLocal(),
      role: mode == TravelMode.car ? TripRole.fromDb(j['role']) : null,
      maxDropoffM: (j['max_dropoff_m'] as num?)?.toInt(),
      detourToleranceM: (j['detour_tolerance_m'] as num?)?.toInt(),
      vibeTags: (j['vibe_tags'] as List?)?.whereType<String>().toList() ?? const [],
      moodText: (j['mood_text'] as String?)?.trim().isEmpty ?? true ? null : (j['mood_text'] as String).trim(),
      moodSetAt: DateTime.tryParse('${j['mood_set_at']}')?.toLocal(),
      womenOnly: (j['women_only'] as bool?) ?? false,
    );
  }
}

/// Everything needed to insert a trip. [id] is generated on the client once
/// per create attempt and reused on retries (idempotency key, design-api 7.3).
class TripDraft {
  const TripDraft({
    required this.id,
    required this.mode,
    required this.origin,
    required this.dest,
    required this.route,
    required this.distanceM,
    required this.durationS,
    required this.departAt,
    this.role,
    this.maxDropoffM,
    this.detourToleranceM,
    this.vibeTags = const [],
    this.moodText,
    this.womenOnly = false,
  });

  final String id;
  final TravelMode mode;

  /// Driver trips only: how far from MY destination I can drop a rider off (metres). Never sent for rider/peer.
  final int? maxDropoffM;

  /// US-50 (round 7): driver trips only, extra round-trip route distance accepted to detour to a
  /// rider's destination (metres, 200..2000 step 100). Never sent for rider/peer.
  final int? detourToleranceM;

  /// Required (by the form and the server) when [mode] is car, absent otherwise.
  final TripRole? role;
  final Place origin;
  final Place dest;
  final List<LatLng> route;
  final int distanceM;
  final int durationS;
  final DateTime departAt;

  /// US-44: up to 3 tags from the role allow-list (server re-validates). Optional.
  final List<String> vibeTags;

  /// US-44: free text <= 35 chars (server re-validates the Q6 guard). Optional.
  final String? moodText;

  /// US-45: opt in to Women-Only matching for this trip (server re-checks gender live). Ignored
  /// by the server unless the caller's `profiles.gender` is currently `female`.
  final bool womenOnly;
}
