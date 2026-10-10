import 'dart:async';

import 'package:gowithme/core/error/app_failure.dart';
import 'package:gowithme/core/error/result.dart';
import 'package:gowithme/core/platform/external_actions.dart';
import 'package:gowithme/features/chat/domain/chat_models.dart';
import 'package:gowithme/features/chat/domain/chat_repository.dart';
import 'package:gowithme/features/geo/domain/location_service.dart';
import 'package:gowithme/features/privacy/domain/consent_repository.dart';
import 'package:gowithme/features/safety/domain/safety_models.dart';
import 'package:gowithme/features/safety/domain/safety_repository.dart';
import 'package:gowithme/features/sharing/domain/trip_share.dart';
import 'package:gowithme/features/trip/domain/live_location.dart';

class FakeChatRepository implements ChatRepository {
  ChatState chatState = ChatState.open;
  AppFailure? sendFailure;
  final messages = <ChatMessage>[];
  final sent = <(String, String, String)>[]; // match, body, clientMsgId
  final sentKinds = <String>[]; // chat_messages.kind per send, parallel to [sent]
  int sendCalls = 0;
  final _incoming = StreamController<ChatMessage>.broadcast();

  void push(ChatMessage m) {
    messages.add(m);
    _incoming.add(m);
  }

  @override
  Future<Result<ChatState>> state(String matchId) async => Ok(chatState);

  @override
  Future<Result<ChatPage>> history(String matchId, {DateTime? before, int limit = 30}) async {
    final l = messages.where((m) => m.matchId == matchId && (before == null || m.createdAt.isBefore(before))).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final page = l.length > limit ? l.sublist(l.length - limit) : l;
    return Ok(ChatPage(items: page, hasMore: l.length > limit));
  }

  @override
  Future<Result<List<ChatMessage>>> since(String matchId, DateTime after) async =>
      Ok([for (final m in messages) if (m.matchId == matchId && m.createdAt.isAfter(after)) m]);

  @override
  Future<Result<ChatMessage?>> latest(String matchId) async {
    final l = messages.where((m) => m.matchId == matchId).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return Ok(l.isEmpty ? null : l.last);
  }

  @override
  Future<Result<ChatMessage>> send(String matchId, String body, String clientMsgId, {String kind = 'user'}) async {
    sendCalls++;
    sent.add((matchId, body, clientMsgId));
    sentKinds.add(kind);
    if (sendFailure != null) return Err(sendFailure!);
    // Idempotent on client id, like the DB unique index.
    final existing = messages.where((m) => m.clientMsgId == clientMsgId).firstOrNull;
    if (existing != null) return Ok(existing);
    final m = ChatMessage(
      id: 'srv-${messages.length}',
      matchId: matchId,
      body: body,
      createdAt: DateTime.now(),
      senderId: 'u1',
      clientMsgId: clientMsgId,
    );
    messages.add(m);
    return Ok(m);
  }

  @override
  Stream<ChatMessage> incoming() => _incoming.stream;
}

class FakeSafetyRepository implements SafetyRepository {
  final blockedIds = <String>[];
  final reports = <(String, ReportReason, String?)>[];
  AppFailure? failure;

  @override
  Future<Result<void>> block(String userId) async {
    if (failure != null) return Err(failure!);
    if (!blockedIds.contains(userId)) blockedIds.add(userId);
    return const Ok(null);
  }

  @override
  Future<Result<void>> unblock(String userId) async {
    blockedIds.remove(userId);
    return const Ok(null);
  }

  @override
  Future<Result<List<BlockedUser>>> blocked() async =>
      Ok([for (final id in blockedIds) BlockedUser(userId: id, blockedAt: DateTime.now(), displayName: 'คนที่บล็อก')]);

  @override
  Future<Result<void>> report({
    required String userId,
    String? matchId,
    required ReportReason reason,
    String? details,
  }) async {
    if (failure != null) return Err(failure!);
    reports.add((userId, reason, details));
    return const Ok(null);
  }
}

class FakeContactRepository implements EmergencyContactRepository {
  final items = <EmergencyContact>[];
  int _n = 0;

  @override
  Future<Result<List<EmergencyContact>>> list() async => Ok(List.of(items));

  @override
  Future<Result<EmergencyContact>> add({required String name, required String phone}) async {
    if (items.length >= ContactRules.maxContacts) return const Err(AppFailure('GWM_EMERGENCY_CONTACT_LIMIT'));
    final c = EmergencyContact(id: 'c${_n++}', name: name.trim(), phone: ContactRules.normalizePhone(phone));
    items.add(c);
    return Ok(c);
  }

  @override
  Future<Result<EmergencyContact>> update(String id, {required String name, required String phone}) async {
    final i = items.indexWhere((c) => c.id == id);
    items[i] = EmergencyContact(id: id, name: name.trim(), phone: ContactRules.normalizePhone(phone));
    return Ok(items[i]);
  }

  @override
  Future<Result<void>> delete(String id) async {
    items.removeWhere((c) => c.id == id);
    return const Ok(null);
  }
}

/// Stores rows by id with ignore-duplicates semantics like the real insert.
class FakeSosRepository implements SosRepository {
  final rows = <String, SosEvent>{};
  int submitCalls = 0;
  AppFailure? failure;
  Completer<void>? hang;

  @override
  Future<Result<void>> submit(SosEvent event) async {
    submitCalls++;
    if (hang != null) await hang!.future;
    if (failure != null) return Err(failure!);
    rows.putIfAbsent(event.id, () => event);
    return const Ok(null);
  }
}

class FakeLiveLocationRepository implements LiveLocationRepository {
  final pushes = <(String, LocationFix)>[];
  AppFailure? pushFailure;
  PartnerLocation? partner;

  @override
  Future<Result<void>> push(String tripId, LocationFix fix) async {
    pushes.add((tripId, fix));
    return pushFailure == null ? const Ok(null) : Err(pushFailure!);
  }

  @override
  Future<Result<PartnerLocation?>> partnerLocation(String matchId) async => Ok(partner);
}

class FakeTripShareRepository implements TripShareRepository {
  final shares = <ActiveShare>[];
  final revoked = <String>[];
  int created = 0;

  @override
  Future<Result<ShareLink>> create(String tripId, {int? ttlMin}) async {
    created++;
    final id = 'share-$created';
    shares.add(ActiveShare(id: id, tripId: tripId, expiresAt: DateTime.now().add(const Duration(hours: 2))));
    return Ok(ShareLink(id: id, expiresAt: shares.last.expiresAt, token: 'tok$created'));
  }

  @override
  Future<Result<void>> revoke(String shareId) async {
    revoked.add(shareId);
    shares.removeWhere((s) => s.id == shareId);
    return const Ok(null);
  }

  @override
  Future<Result<List<ActiveShare>>> active() async => Ok(List.of(shares));
}

class FakeAccountRepository implements AccountRepository {
  int deletions = 0;
  int exports = 0;

  @override
  Future<Result<String>> exportMyData() async {
    exports++;
    return const Ok('{"profile":{}}');
  }

  @override
  Future<Result<void>> requestAccountDeletion() async {
    deletions++;
    return const Ok(null);
  }
}

class FakeExternalActions implements ExternalActions {
  final calls = <String>[];
  final smsSent = <(String, String)>[];
  final shared = <String>[];
  bool callOk = true;
  bool shareOk = true;

  @override
  Future<bool> call(String number) async {
    calls.add(number);
    return callOk;
  }

  @override
  Future<bool> sms(String number, String body) async {
    smsSent.add((number, body));
    return true;
  }

  @override
  Future<bool> shareText(String text, {String? subject}) async {
    shared.add(text);
    return shareOk;
  }

  final opened = <Uri>[];
  bool openOk = true;

  @override
  Future<bool> openUrl(Uri url) async {
    opened.add(url);
    return openOk;
  }
}
