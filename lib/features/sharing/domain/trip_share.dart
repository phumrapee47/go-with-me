import 'package:latlong2/latlong.dart';

import '../../../core/error/result.dart';
import '../../safety/domain/safety_models.dart' show osmLink;
import '../../trip/domain/trip.dart';
import 'share_companion.dart';

/// A backend share token. The raw [token] is only known right after creation
/// and must never be persisted or logged.
class ShareLink {
  const ShareLink({required this.id, required this.expiresAt, required this.token});
  final String id;
  final DateTime expiresAt;
  final String token;
}

/// An active share as listed later (no token: only the hash is stored).
class ActiveShare {
  const ActiveShare({required this.id, required this.tripId, required this.expiresAt});
  final String id;
  final String tripId;
  final DateTime expiresAt;
}

abstract class TripShareRepository {
  Future<Result<ShareLink>> create(String tripId, {int? ttlMin});
  Future<Result<void>> revoke(String shareId);
  Future<Result<List<ActiveShare>>> active();
}

/// `https://<host>/t#<token>` (design-security F-12: fragment keeps the token
/// out of server logs and Referer). Null when no web page is configured, so
/// the UI never shows a link that goes nowhere.
Uri? shareUrl(String baseUrl, String token) {
  final b = baseUrl.trim();
  if (b.isEmpty || !b.startsWith('https://')) return null;
  final base = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  return Uri.parse('$base/t#$token');
}

String _statusText(TripStatus s) => switch (s) {
      TripStatus.scheduled => 'รอออกเดินทาง',
      TripStatus.inProgress => 'กำลังเดินทาง',
      TripStatus.completed => 'เดินทางถึงแล้ว',
      TripStatus.cancelled => 'ยกเลิกแล้ว',
      TripStatus.expired => 'หมดอายุ',
    };

String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// P0 share = plain-text snapshot (PM P-5). It contains only name, status,
/// approximate destination (the label the user chose), ETA, last position
/// link and, when a backend token exists, the revocable link. Never email,
/// phone or chat.
String buildTripShareText({
  required String name,
  required Trip trip,
  required DateTime now,
  LatLng? lastPosition,
  Uri? link,
  ShareCompanion companion = const ShareCompanion.none(),
}) {
  final eta = (trip.startedAt ?? (trip.departAt.isAfter(now) ? trip.departAt : now))
      .add(Duration(seconds: trip.durationS));
  final b = StringBuffer()
    ..writeln('$name แชร์ทริปให้คุณ')
    ..writeln('สถานะ: ${_statusText(trip.status)}')
    ..writeln('ปลายทางโดยประมาณ: ${trip.destLabel.isEmpty ? 'ไม่ระบุ' : trip.destLabel}');
  if (trip.durationS > 0) b.writeln('คาดว่าจะถึงประมาณ ${_hhmm(eta)}');
  for (final line in companionLines(companion)) {
    b.writeln(line);
  }
  if (lastPosition != null) {
    b.writeln('ตำแหน่งล่าสุด (ณ ${_hhmm(now)}): ${osmLink(lastPosition)}');
  }
  if (link != null) b.writeln('ติดตามต่อ: $link');
  b.write('ถ้าติดต่อฉันไม่ได้ โปรดโทรหาฉันหรือแจ้งความช่วยเหลือ');
  return b.toString();
}
