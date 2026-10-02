import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/error/app_failure.dart';
import '../core/error/result.dart';
import '../core/platform/external_actions.dart';
import '../features/chat/domain/chat_models.dart';
import '../features/chat/domain/chat_repository.dart';
import '../features/geo/domain/location_service.dart';
import '../features/matching/domain/match_models.dart' show MatchStatus;
import '../features/privacy/domain/consent_repository.dart';
import '../features/safety/domain/safety_models.dart';
import '../features/safety/domain/safety_repository.dart';
import '../features/sharing/domain/trip_share.dart';
import '../features/trip/domain/live_location.dart';
import 'demo_data.dart';
import 'demo_fakes.dart';

const _latency = Duration(milliseconds: 250);
Future<void> _wait() => Future<void>.delayed(_latency);

/// One-line message shown by the demo shell when the app would leave itself
/// (phone dialer, share sheet). Web has no dialer/share sheet to show.
final ValueNotifier<String?> demoToast = ValueNotifier<String?>(null);

class DemoExternalActions implements ExternalActions {
  @override
  Future<bool> call(String number) async {
    demoToast.value = 'เดโม: เครื่องจริงจะเปิดหน้าโทรออกไปที่ $number';
    return true;
  }

  @override
  Future<bool> sms(String number, String body) async {
    demoToast.value = 'เดโม: เปิด SMS ถึง $number\n$body';
    return true;
  }

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    demoToast.value = 'เดโม: เปิดหน้าแชร์ของระบบพร้อมข้อความ\n$text';
    return true;
  }

  @override
  Future<bool> openUrl(Uri url) async {
    // Only the target coordinates are in a navigation URL (US-24); shown here instead of leaving the page.
    demoToast.value = 'เดโม: เปิดแอปแผนที่นำทางไปที่\n$url';
    return true;
  }
}

/// In-memory chat. A canned partner reply arrives ~2 s after you send.
class DemoChatRepository implements ChatRepository {
  DemoChatRepository(this._trips, [this._matches]) {
    reset();
  }

  final DemoTripRepository _trips;
  final DemoMatchRepository? _matches;
  final _messages = <ChatMessage>[];
  final _incoming = StreamController<ChatMessage>.broadcast();
  ChatState? _forced;
  int _n = 0;
  int _replies = 0;

  static const _partnerId = 'demo-user-$demoAcceptedCandidateId';
  static const _replyTexts = ['ได้เลยครับ', 'โอเค เจอกันตามนัด', 'ขอบคุณครับ ใกล้ถึงแล้วนะ'];

  void reset() {
    final t = DateTime.now();
    _forced = null;
    _messages
      ..clear()
      ..addAll([
        _msg('สวัสดีครับ ไปทางเดียวกันเลย', _partnerId, t.subtract(const Duration(minutes: 9))),
        _msg('ค่ะ ออกจากสยามประมาณ 18:30', demoUserId, t.subtract(const Duration(minutes: 8))),
        _msg('โอเค เจอกันหน้าสถานีนะครับ', _partnerId, t.subtract(const Duration(minutes: 6))),
      ]);
  }

  ChatMessage _msg(String body, String sender, DateTime at, {String? clientId}) => ChatMessage(
        id: 'demo-msg-${_n++}',
        matchId: 'demo-match-accepted',
        body: body,
        createdAt: at,
        senderId: sender,
        clientMsgId: clientId,
      );

  /// Hub: a partner message that also flips the unread dot.
  void partnerSays(String text) => _emit(_msg(text, _partnerId, DateTime.now()));

  /// Hub: force a chat state and tell the open room (via a system message).
  void forceState(ChatState? s) {
    _forced = s;
    final key = switch (s) {
      ChatState.tripEnded => 'system.trip_cancelled',
      ChatState.matchClosed => 'system.trip_expired',
      _ => 'system.info',
    };
    _emit(ChatMessage(
      id: 'demo-sys-${_n++}',
      matchId: 'demo-match-accepted',
      body: key,
      createdAt: DateTime.now(),
      isSystem: true,
    ));
  }

  /// Called by the demo safety repository: a block closes the chat both ways.
  void onBlocked() => forceState(ChatState.blocked);

  void _emit(ChatMessage m) {
    _messages.add(m);
    _incoming.add(m);
  }

  @override
  Future<Result<ChatState>> state(String matchId) async {
    await _wait();
    if (_forced != null) return Ok(_forced!);
    // Car scenarios: a match that ended is read-only for both sides.
    final m = _matches?.matches.where((x) => x.id == matchId).firstOrNull;
    if (m != null && m.isCar && m.status == MatchStatus.cancelled) return const Ok(ChatState.matchClosed);
    return Ok(_trips.active == null ? ChatState.tripEnded : ChatState.open);
  }

  @override
  Future<Result<ChatPage>> history(String matchId, {DateTime? before, int limit = 30}) async {
    await _wait();
    final l = [for (final m in _messages) if (before == null || m.createdAt.isBefore(before)) m]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return Ok(ChatPage(items: l.length > limit ? l.sublist(l.length - limit) : l, hasMore: l.length > limit));
  }

  @override
  Future<Result<List<ChatMessage>>> since(String matchId, DateTime after) async =>
      Ok([for (final m in _messages) if (m.createdAt.isAfter(after)) m]);

  @override
  Future<Result<ChatMessage?>> latest(String matchId) async {
    final l = [..._messages]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return Ok(matchId == 'demo-match-accepted' && l.isNotEmpty ? l.last : null);
  }

  @override
  Future<Result<ChatMessage>> send(String matchId, String body, String clientMsgId) async {
    await _wait();
    final existing = _messages.where((m) => m.clientMsgId == clientMsgId).firstOrNull;
    if (existing != null) return Ok(existing);
    final m = _msg(body, demoUserId, DateTime.now(), clientId: clientMsgId);
    _messages.add(m);
    Timer(const Duration(seconds: 2), () => partnerSays(_replyTexts[_replies++ % _replyTexts.length]));
    return Ok(m);
  }

  @override
  Stream<ChatMessage> incoming() => _incoming.stream;
}

class DemoSafetyRepository implements SafetyRepository {
  DemoSafetyRepository(this._chat);
  final DemoChatRepository _chat;
  final _blocked = <String>[];

  void reset() => _blocked.clear();

  String _nameOf(String userId) {
    for (final c in demoCandidates()) {
      if (userId == 'demo-user-${c.tripId}') return c.displayName;
    }
    return 'ผู้ใช้';
  }

  @override
  Future<Result<void>> block(String userId) async {
    await _wait();
    if (!_blocked.contains(userId)) _blocked.add(userId);
    if (userId == 'demo-user-$demoAcceptedCandidateId') _chat.onBlocked();
    return const Ok(null);
  }

  @override
  Future<Result<void>> unblock(String userId) async {
    await _wait();
    _blocked.remove(userId);
    if (userId == 'demo-user-$demoAcceptedCandidateId') _chat.forceState(null);
    return const Ok(null);
  }

  @override
  Future<Result<List<BlockedUser>>> blocked() async {
    await _wait();
    return Ok([
      for (final id in _blocked) BlockedUser(userId: id, blockedAt: DateTime.now(), displayName: _nameOf(id)),
    ]);
  }

  @override
  Future<Result<void>> report({
    required String userId,
    String? matchId,
    required ReportReason reason,
    String? details,
  }) async {
    await _wait();
    return const Ok(null);
  }
}

class DemoContactRepository implements EmergencyContactRepository {
  List<EmergencyContact> _items = _seed();
  int _n = 10;

  static List<EmergencyContact> _seed() => const [EmergencyContact(id: 'demo-c1', name: 'แม่', phone: '0812345678')];

  void reset() => _items = _seed();

  @override
  Future<Result<List<EmergencyContact>>> list() async {
    await _wait();
    return Ok(List.of(_items));
  }

  @override
  Future<Result<EmergencyContact>> add({required String name, required String phone}) async {
    await _wait();
    if (_items.length >= ContactRules.maxContacts) return const Err(AppFailure('GWM_EMERGENCY_CONTACT_LIMIT'));
    final c = EmergencyContact(id: 'demo-c${_n++}', name: name.trim(), phone: ContactRules.normalizePhone(phone));
    _items = [..._items, c];
    return Ok(c);
  }

  @override
  Future<Result<EmergencyContact>> update(String id, {required String name, required String phone}) async {
    await _wait();
    final c = EmergencyContact(id: id, name: name.trim(), phone: ContactRules.normalizePhone(phone));
    _items = [for (final x in _items) x.id == id ? c : x];
    return Ok(c);
  }

  @override
  Future<Result<void>> delete(String id) async {
    await _wait();
    _items = [for (final x in _items) if (x.id != id) x];
    return const Ok(null);
  }
}

/// SOS sink with an "offline" switch so the local queue and retry can be seen.
class DemoSosRepository implements SosRepository {
  final rows = <String, SosEvent>{};
  final offline = ValueNotifier<bool>(false);

  @override
  Future<Result<void>> submit(SosEvent event) async {
    await _wait();
    if (offline.value) return const Err(AppFailure(FailureCode.networkOffline, retryable: true));
    rows.putIfAbsent(event.id, () => event);
    return const Ok(null);
  }
}

/// The partner walks / drives along a demo route. Like the real client, a NEW position only appears every
/// 15 s (positions are quantised to 15 s steps), so the interpolation and the 45 s stale state are visible.
/// [frozen] simulates a lost signal (the last fix stops updating). Visibility follows the real rules:
/// only for an accepted match, and a Driver no longer gets the Rider once they boarded.
class DemoLiveLocationRepository implements LiveLocationRepository {
  DemoLiveLocationRepository([this._matches]);
  final DemoMatchRepository? _matches;
  final _started = DateTime.now();
  int pushes = 0;

  /// Hub switch: stop producing new fixes.
  final frozen = ValueNotifier<bool>(false);
  DateTime? _frozenAt;

  @override
  Future<Result<void>> push(String tripId, LocationFix fix) async {
    pushes++;
    return const Ok(null);
  }

  @override
  Future<Result<PartnerLocation?>> partnerLocation(String matchId) async {
    await _wait();
    final m = _matches?.matches.where((x) => x.id == matchId).firstOrNull;
    if (m == null) {
      if (matchId != 'demo-match-accepted') return const Ok(null);
    } else {
      if (m.status != MatchStatus.accepted) return const Ok(null);
      if (m.iAmDriver && m.boarded) return const Ok(null); // Rider boarded: the Driver stops seeing them
    }
    final now = DateTime.now();
    if (frozen.value) {
      _frozenAt ??= now;
    } else {
      _frozenAt = null;
    }
    final at = _frozenAt ?? now;
    final route = demoPartnerRoute();
    final steps = at.difference(_started).inSeconds ~/ 15; // one fix per 15 s
    final f = (0.15 + steps * 15 / 240).clamp(0.0, 0.9);
    final pos = f * (route.length - 1);
    final k = pos.floor().clamp(0, route.length - 2);
    final r = pos - k;
    final a = route[k];
    final b = route[k + 1];
    return Ok(PartnerLocation(
      point: LatLng(a.latitude + (b.latitude - a.latitude) * r, a.longitude + (b.longitude - a.longitude) * r),
      recordedAt: _started.add(Duration(seconds: steps * 15)),
    ));
  }
}

/// Simulates a backend that mints share tokens (the demo pretends a share
/// page exists so the "stop sharing" control can be reviewed).
class DemoTripShareRepository implements TripShareRepository {
  final _shares = <ActiveShare>[];
  int _n = 0;

  void reset() => _shares.clear();

  @override
  Future<Result<ShareLink>> create(String tripId, {int? ttlMin}) async {
    await _wait();
    final s = ActiveShare(
      id: 'demo-share-${++_n}',
      tripId: tripId,
      expiresAt: DateTime.now().add(const Duration(hours: 4)),
    );
    _shares.add(s);
    return Ok(ShareLink(id: s.id, expiresAt: s.expiresAt, token: 'demo-token-$_n'));
  }

  @override
  Future<Result<void>> revoke(String shareId) async {
    await _wait();
    _shares.removeWhere((s) => s.id == shareId);
    return const Ok(null);
  }

  @override
  Future<Result<List<ActiveShare>>> active() async {
    await _wait();
    return Ok(List.of(_shares));
  }
}

class DemoAccountRepository implements AccountRepository {
  @override
  Future<Result<String>> exportMyData() async {
    await _wait();
    return const Ok('{\n  "profile": {"display_name": "มิ้นท์"},\n  "note": "ข้อมูลตัวอย่างจากโหมดเดโม"\n}');
  }

  @override
  Future<Result<void>> requestAccountDeletion() async {
    await _wait();
    return const Ok(null);
  }
}
