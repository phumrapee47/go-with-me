import '../../../core/l10n/strings_p4.dart';
import '../../../core/l10n/strings_roles.dart';
import '../../../core/net/throttle.dart';

/// Result of the `chat_state(match_id)` RPC (migration 0002-F). It lets the
/// client tell "chat is closed" apart from an RLS denial on insert.
enum ChatState {
  open,
  blocked,
  tripEnded,
  matchClosed,
  notFound;

  /// Unknown/missing values map to [matchClosed]: the safe direction is
  /// read-only, never "pretend the chat is open".
  static ChatState fromDb(Object? v) => switch (v) {
        'open' => ChatState.open,
        'blocked' => ChatState.blocked,
        'trip_ended' => ChatState.tripEnded,
        'match_closed' => ChatState.matchClosed,
        'not_found' => ChatState.notFound,
        _ => ChatState.matchClosed,
      };

  bool get canSend => this == ChatState.open;

  String get readOnlyBanner => switch (this) {
        ChatState.open => '',
        ChatState.blocked => P.chatReadOnlyBlocked,
        ChatState.tripEnded => P.chatReadOnlyTripEnded,
        ChatState.matchClosed || ChatState.notFound => P.chatReadOnlyClosed,
      };
}

enum SendStatus { sending, sent, failed }

const chatMaxLength = 1000;

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.matchId,
    required this.body,
    required this.createdAt,
    this.senderId,
    this.isSystem = false,
    this.clientMsgId,
    this.status = SendStatus.sent,
  });

  final String id;
  final String matchId;
  final String? senderId;
  final bool isSystem;
  final String body;
  final String? clientMsgId;
  final DateTime createdAt;
  final SendStatus status;

  ChatMessage copyWith({SendStatus? status}) => ChatMessage(
        id: id,
        matchId: matchId,
        body: body,
        createdAt: createdAt,
        senderId: senderId,
        isSystem: isSystem,
        clientMsgId: clientMsgId,
        status: status ?? this.status,
      );

  /// Text to render: system rows carry i18n keys, not display text.
  String get displayText => isSystem ? systemMessageText(body) : body;

  static ChatMessage? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final matchId = j['match_id'];
    final created = DateTime.tryParse('${j['created_at']}');
    final body = j['body'];
    if (id is! String || matchId is! String || created == null || body is! String) return null;
    return ChatMessage(
      id: id,
      matchId: matchId,
      body: body,
      createdAt: created.toLocal(),
      senderId: j['sender_id'] as String?,
      isSystem: j['kind'] == 'system',
      clientMsgId: j['client_msg_id'] as String?,
    );
  }
}

String systemMessageText(String key) => switch (key) {
      'system.trip_completed' => P.sysTripCompleted,
      'system.trip_cancelled' => P.sysTripCancelled,
      'system.trip_expired' => P.sysTripExpired,
      // Car matches: neutral wording only (no reason, no who; US-18 AC9).
      'system.match_cancelled' || 'system.match_cancelled_in_trip' => R.sysMatchCancelled,
      'system.boarded' => R.sysBoarded,
      // The message never carries the new values (design-spec R.6).
      'system.vehicle_updated' => R.vehicleUpdatedSystem,
      _ => P.sysGeneric,
    };

/// Merges [incoming] into [existing]: dedupes by `client_msg_id` (optimistic
/// row vs. the row echoed by Realtime/REST) then by id, keeps chronological
/// order. Server rows win over local optimistic ones.
List<ChatMessage> mergeMessages(List<ChatMessage> existing, Iterable<ChatMessage> incoming) {
  final out = [...existing];
  for (final m in incoming) {
    final i = out.indexWhere((x) =>
        x.id == m.id || (m.clientMsgId != null && x.clientMsgId == m.clientMsgId));
    if (i >= 0) {
      out[i] = m;
    } else {
      out.add(m);
    }
  }
  out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return out;
}

/// Client-side send budget. The DB trigger allows 10 messages / 10 s per
/// (match, sender); we stop a little earlier so a normal burst never reaches
/// the server rejection (`GWM_RATE_LIMITED`).
class SendThrottle {
  SendThrottle({this.maxPerWindow = 8, this.window = const Duration(seconds: 10), Clock? clock})
      : _clock = clock ?? DateTime.now;

  final int maxPerWindow;
  final Duration window;
  final Clock _clock;
  final _sent = <DateTime>[];

  void _prune() {
    final now = _clock();
    _sent.removeWhere((t) => now.difference(t) >= window);
  }

  /// Records a send when allowed. False = caller must keep the text and wait.
  bool tryAcquire() {
    _prune();
    if (_sent.length >= maxPerWindow) return false;
    _sent.add(_clock());
    return true;
  }

  Duration retryAfter() {
    _prune();
    if (_sent.length < maxPerWindow) return Duration.zero;
    return window - _clock().difference(_sent.first);
  }
}

String? validateChatBody(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  if (t.length > chatMaxLength) return P.chatLimit;
  return null;
}
