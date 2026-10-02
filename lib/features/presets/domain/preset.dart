import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../trip/domain/trip.dart' show Place;

/// Which saved place (US-38).
enum PresetKind {
  home('home'),
  start('start');

  const PresetKind(this.db);
  final String db;

  static PresetKind? fromDb(Object? v) {
    for (final k in values) {
      if (k.db == v) return k;
    }
    return null;
  }
}

/// Kind of the regular starting point (P-3 chips).
enum StartType {
  work('work'),
  campus('campus'),
  other('other');

  const StartType(this.db);
  final String db;

  static StartType? fromDb(Object? v) {
    for (final k in values) {
      if (k.db == v) return k;
    }
    return null;
  }
}

const presetNameMaxLen = 20;

/// A saved place. DEVICE-LOCAL ONLY: never serialised anywhere except the local secure storage.
class PlacePreset {
  const PlacePreset({required this.name, required this.label, required this.point, this.startType});

  /// The name the user gave ("บ้าน", "ที่ทำงาน"): the only text shown on the home card.
  final String name;

  /// Place label (search result / reverse geocode); used as the trip label like the wizard does.
  final String label;
  final LatLng point;
  final StartType? startType;

  Place toPlace() => Place(point: point, label: label);

  Map<String, Object?> toJson() => {
        'name': name,
        'label': label,
        'lat': point.latitude,
        'lng': point.longitude,
        if (startType != null) 'type': startType!.db,
      };

  static PlacePreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    final name = raw['name'];
    if (lat is! num || lng is! num || name is! String || name.trim().isEmpty) return null;
    return PlacePreset(
      name: name,
      label: (raw['label'] as String?) ?? name,
      point: LatLng(lat.toDouble(), lng.toDouble()),
      startType: StartType.fromDb(raw['type']),
    );
  }
}

/// Everything kept for one user on this device (US-38 + last one-tap choices, US-39).
class PresetData {
  const PresetData({this.home, this.start, this.noticeSeen = false, this.lastDepartMinutes, this.lastMaxDropoffM});

  final PlacePreset? home;
  final PlacePreset? start;

  /// The privacy notice was shown before the first save.
  final bool noticeSeen;

  /// Last chosen fixed departure as minutes since midnight (null = "now").
  final int? lastDepartMinutes;

  /// Last Driver drop-off limit used by the one-tap card (metres).
  final int? lastMaxDropoffM;

  static const empty = PresetData();

  bool get isComplete => home != null && start != null;
  bool get isEmpty => home == null && start == null;

  PresetData copyWith({
    Object? home = _keep,
    Object? start = _keep,
    bool? noticeSeen,
    Object? lastDepartMinutes = _keep,
    Object? lastMaxDropoffM = _keep,
  }) =>
      PresetData(
        home: identical(home, _keep) ? this.home : home as PlacePreset?,
        start: identical(start, _keep) ? this.start : start as PlacePreset?,
        noticeSeen: noticeSeen ?? this.noticeSeen,
        lastDepartMinutes: identical(lastDepartMinutes, _keep) ? this.lastDepartMinutes : lastDepartMinutes as int?,
        lastMaxDropoffM: identical(lastMaxDropoffM, _keep) ? this.lastMaxDropoffM : lastMaxDropoffM as int?,
      );

  String encode() => jsonEncode({
        'v': 1,
        if (home != null) 'home': home!.toJson(),
        if (start != null) 'start': start!.toJson(),
        'notice': noticeSeen,
        if (lastDepartMinutes != null) 'depart': lastDepartMinutes,
        if (lastMaxDropoffM != null) 'dropoff': lastMaxDropoffM,
      });

  /// Tolerant: anything unreadable becomes [empty] (never crashes the home screen).
  static PresetData decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return empty;
      return PresetData(
        home: PlacePreset.fromJson(j['home']),
        start: PlacePreset.fromJson(j['start']),
        noticeSeen: j['notice'] == true,
        lastDepartMinutes: j['depart'] is int ? j['depart'] as int : null,
        lastMaxDropoffM: j['dropoff'] is int ? j['dropoff'] as int : null,
      );
    } catch (_) {
      return empty;
    }
  }
}

const Object _keep = Object();
