/// US-42 push notifications: opaque, data-only payload contract (design-roles
/// section 14, design-spec-round7 G.1). The server never sends rendered text;
/// the client always renders Thai copy from [PushKind] alone (single source
/// of truth: `strings_roles.dart`).
///
/// Wire values match the DB `push_kind` enum exactly as defined in
/// `supabase/migrations/0011_push_pindrop.sql` (`create type public.push_kind
/// as enum ('match_requested','match_accepted','chat_message',
/// 'driver_arrived','match_cancelled')`) — NOT the informal
/// `new_request`/`new_message` labels used in `docs/design-spec-round7.md`'s
/// G.1.4 table, which is UX documentation, not the DB contract. The SQL
/// migration is a draft (unapplied) but is still the authoritative source
/// for the actual enum values per design-roles.md §14.
enum PushKind {
  newRequest('match_requested'),
  matchAccepted('match_accepted'),
  driverArrived('driver_arrived'),
  matchCancelled('match_cancelled'),
  newMessage('chat_message');

  const PushKind(this.wire);
  final String wire;

  static PushKind? fromWire(Object? v) {
    for (final k in values) {
      if (k.wire == v) return k;
    }
    return null;
  }
}

/// Wire values match the DB `device_platform` enum (design-roles 14.4).
enum DevicePlatform {
  android('android'),
  ios('ios'),
  web('web');

  const DevicePlatform(this.wire);
  final String wire;
}

/// A parsed, opaque push payload. Only `kind` + one id ever travel over the
/// wire (no rendered text, no PII — design-roles 14.4/14.7).
class PushMessage {
  const PushMessage({required this.kind, this.matchId, this.tripId});

  final PushKind kind;
  final String? matchId;
  final String? tripId;

  /// Parses `RemoteMessage.data` (or any `String`-keyed map, e.g. a demo
  /// fake). Returns null when `kind` is missing/unknown (fail-open: drop the
  /// notification silently rather than crash or show a broken message).
  static PushMessage? fromData(Map<String, dynamic> data) {
    final kind = PushKind.fromWire(data['kind']);
    if (kind == null) return null;
    return PushMessage(
      kind: kind,
      matchId: data['match_id'] as String?,
      tripId: data['trip_id'] as String?,
    );
  }
}
