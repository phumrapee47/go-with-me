import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../../core/l10n/strings_p4.dart';

/// DB enum `report_reason`.
enum ReportReason {
  harassment('harassment', P.reasonHarassment),
  fakeProfile('fake_profile', P.reasonFake),
  unsafeBehavior('unsafe_behavior', P.reasonUnsafe),
  spam('spam', P.reasonSpam),
  other('other', P.reasonOther);

  const ReportReason(this.db, this.label);
  final String db;
  final String label;
}

class BlockedUser {
  const BlockedUser({required this.userId, required this.blockedAt, this.displayName});
  final String userId;
  final DateTime blockedAt;

  /// Null when the profile is no longer readable (blocked users are hidden).
  final String? displayName;
}

class EmergencyContact {
  const EmergencyContact({required this.id, required this.name, required this.phone});
  final String id;
  final String name;
  final String phone;

  static EmergencyContact? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final name = j['name'];
    final phone = j['phone'];
    if (id is! String || name is! String || phone is! String) return null;
    return EmergencyContact(id: id, name: name, phone: phone);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone};

  /// Masked for list screens that other people might see over the shoulder.
  String get maskedPhone {
    if (phone.length <= 4) return phone;
    return '${phone.substring(0, phone.length - 4).replaceAll(RegExp(r'[0-9]'), 'x')}${phone.substring(phone.length - 4)}';
  }
}

/// Pure rules for emergency contacts (PM P-3, P-6; DB check constraints).
abstract final class ContactRules {
  static const maxContacts = 3;
  static final _phoneRe = RegExp(r'^\+?[0-9]{8,15}$');

  /// Strips spaces, dashes and brackets the way people type numbers.
  static String normalizePhone(String raw) => raw.replaceAll(RegExp(r'[\s\-().]'), '');

  static bool isValidPhone(String raw) => _phoneRe.hasMatch(normalizePhone(raw));

  static bool isValidName(String raw) {
    final t = raw.trim();
    return t.isNotEmpty && t.length <= 60;
  }

  static bool canAdd(int currentCount) => currentCount < maxContacts;

  /// Deleting the last contact is allowed but needs an explicit warning (P-6).
  static bool deleteNeedsLastWarning(int currentCount) => currentCount <= 1;

  static bool isDuplicate(Iterable<EmergencyContact> existing, String phone, {String? exceptId}) {
    final n = normalizePhone(phone);
    return existing.any((c) => c.id != exceptId && normalizePhone(c.phone) == n);
  }
}

enum SosSource {
  trip('trip'),
  chat('chat');

  const SosSource(this.db);
  final String db;
  static SosSource fromDb(Object? v) => v == 'chat' ? chat : trip;
}

/// One SOS incident. [id] is generated on the client before anything is sent
/// and is the primary key of the row, so retries can never duplicate it.
class SosEvent {
  const SosEvent({
    required this.id,
    required this.clientCreatedAt,
    this.tripId,
    this.location,
    this.source = SosSource.trip,
    this.note,
  });

  final String id;
  final String? tripId;
  final LatLng? location;
  final SosSource source;
  final String? note;
  final DateTime clientCreatedAt;

  SosEvent copyWith({LatLng? location, bool clearTrip = false}) => SosEvent(
        id: id,
        clientCreatedAt: clientCreatedAt,
        tripId: clearTrip ? null : tripId,
        location: location ?? this.location,
        source: source,
        note: note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trip_id': tripId,
        'lat': location?.latitude,
        'lng': location?.longitude,
        'source': source.db,
        'note': note,
        'at': clientCreatedAt.toUtc().toIso8601String(),
      };

  static SosEvent? fromJson(Object? o) {
    if (o is! Map) return null;
    final id = o['id'];
    final at = DateTime.tryParse('${o['at']}');
    if (id is! String || at == null) return null;
    final lat = o['lat'];
    final lng = o['lng'];
    return SosEvent(
      id: id,
      tripId: o['trip_id'] as String?,
      location: (lat is num && lng is num) ? LatLng(lat.toDouble(), lng.toDouble()) : null,
      source: SosSource.fromDb(o['source']),
      note: o['note'] as String?,
      clientCreatedAt: at,
    );
  }
}

String encodeSosEvents(List<SosEvent> l) => jsonEncode([for (final e in l) e.toJson()]);

List<SosEvent> decodeSosEvents(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final d = jsonDecode(raw);
    if (d is! List) return const [];
    return [for (final x in d) ?SosEvent.fromJson(x)];
  } catch (_) {
    return const [];
  }
}

/// Message text handed to the share sheet / SMS. Includes an OSM link only
/// when a position is known.
String buildSosMessage({
  required String name,
  required DateTime at,
  LatLng? location,
  List<String> extraLines = const [],
}) {
  final hh = at.hour.toString().padLeft(2, '0');
  final mm = at.minute.toString().padLeft(2, '0');
  final time = '$hh:$mm';
  final base = location == null
      ? 'ฉันต้องการความช่วยเหลือ (ระบุตำแหน่งไม่ได้) (เวลา $time) จาก $name'
      : 'ฉันต้องการความช่วยเหลือ ตอนนี้อยู่ที่ ${osmLink(location)} (เวลา $time) จาก $name';
  // Car match: driver name and (only when allowed) plate, see share_companion.dart.
  return extraLines.isEmpty ? base : [base, ...extraLines].join('\n');
}

String osmLink(LatLng p) {
  final lat = p.latitude.toStringAsFixed(5);
  final lng = p.longitude.toStringAsFixed(5);
  return 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng';
}
