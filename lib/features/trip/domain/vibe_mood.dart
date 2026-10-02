import 'trip.dart';

/// US-44 (round 7, design-roles §14 / design-spec-round7 G.3): vibe tags +
/// daily mood, bound to a TRIP (not the profile — Q5), cleared automatically
/// on trip end or 24h. Allow-lists mirror `docs/requirements-round7-ba.md`
/// US-44 AC1 exactly; the server re-validates (GWM_VIBE_TAG_INVALID) so this
/// is UX-only, never the source of truth.
abstract final class VibeTagCatalog {
  static const driverTags = <String>[
    '#เปิดแอร์เย็น',
    '#เปิดเพลงฟังเพลิน',
    '#ขับนิ่มไม่ซิ่ง',
    '#ไม่สูบบุหรี่',
    '#มีที่เก็บกระเป๋า',
  ];

  static const riderTags = <String>[
    '#คุยเก่ง',
    '#ขอพักสายตาเงียบๆ',
    '#ฟังเพลงสากล',
    '#สายประหยัด',
    '#พร้อมแชร์เรื่องเล่า',
  ];

  static const maxTags = 3;

  /// Driver sees the Driver allow-list; everyone else (Rider/Peer/Foot) sees the Rider one.
  static List<String> forRole(TripRole? role) => role == TripRole.driver ? driverTags : riderTags;
}

enum VibeTagIssue { notInAllowList, maxReached }

/// Client-side mirror of the server allow-list check (fast UX only).
VibeTagIssue? validateVibeTagSelection({
  required List<String> current,
  required String candidate,
  required TripRole? role,
}) {
  if (!VibeTagCatalog.forRole(role).contains(candidate)) return VibeTagIssue.notInAllowList;
  if (current.length >= VibeTagCatalog.maxTags && !current.contains(candidate)) {
    return VibeTagIssue.maxReached;
  }
  return null;
}

const moodMaxLength = 35;

/// Q6 (PM decision): reject long digit runs (phone-number-shaped) and a
/// small blocklist of crude words. Not full moderation — the residual risk
/// (any other inappropriate content) is accepted per the requirements doc.
enum MoodIssue { overLimit, blockedPattern }

abstract final class MoodBlocklist {
  /// Small, fixed set (cheap guard only, Q6) — not a full profanity filter.
  static const words = <String>['เย็ด', 'สัส', 'ควย', 'เหี้ย'];
}

final _digitRun8 = RegExp(r'\d{8,}');

class VibeMoodValidator {
  const VibeMoodValidator._();

  /// Returns null when [text] is valid (or empty — mood is optional).
  static MoodIssue? validateMood(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    if (t.length > moodMaxLength) return MoodIssue.overLimit;
    if (_digitRun8.hasMatch(t)) return MoodIssue.blockedPattern;
    final lower = t.toLowerCase();
    for (final w in MoodBlocklist.words) {
      if (lower.contains(w)) return MoodIssue.blockedPattern;
    }
    return null;
  }
}

/// Trip's vibe/mood clears automatically on trip end (handled server-side)
/// or after 24h since [moodSetAt] — mirrored here only to decide whether to
/// show `mood.autocleared_notice` right after a refresh (best-effort UX hint,
/// the server is authoritative about whether the columns are actually null).
bool vibeMoodExpired(DateTime? setAt, {DateTime? now}) {
  if (setAt == null) return false;
  final n = now ?? DateTime.now();
  return n.difference(setAt) >= const Duration(hours: 24);
}
