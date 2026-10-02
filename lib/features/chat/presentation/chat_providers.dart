import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uuid/uuid.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/error/result.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../matching/domain/match_models.dart';
import '../../matching/presentation/matching_providers.dart';
import '../data/supabase_chat_repository.dart';
import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';
import 'quick_voice_providers.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => SupabaseChatRepository(Supabase.instance.client),
);

/// Realtime has no replay: the room re-reads anything newer than the last row
/// on this interval as a cheap safety net (also covers a dropped socket).
final chatBackfillIntervalProvider = Provider<Duration>((ref) => const Duration(seconds: 30));

const _uuid = Uuid();

/// Per-match "last seen" timestamps (local only) for the unread dots.
class ChatLastSeen extends Notifier<Map<String, DateTime>> {
  static const _key = 'chat_last_seen_v1';

  @override
  Map<String, DateTime> build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return const {};
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in d.entries) e.key: ?DateTime.tryParse('${e.value}'),
      };
    } catch (_) {
      return const {};
    }
  }

  void markSeen(String matchId, DateTime at) {
    final cur = state[matchId];
    if (cur != null && !at.isAfter(cur)) return;
    state = {...state, matchId: at};
    unawaited(ref.read(sharedPrefsProvider).setString(
          _key,
          jsonEncode({for (final e in state.entries) e.key: e.value.toUtc().toIso8601String()}),
        ));
  }
}

final chatLastSeenProvider = NotifierProvider<ChatLastSeen, Map<String, DateTime>>(ChatLastSeen.new);

class ChatRoomState {
  const ChatRoomState({
    this.messages = const [],
    this.chatState = ChatState.open,
    this.loading = true,
    this.hasMore = false,
    this.loadingMore = false,
    this.loadError,
  });

  final List<ChatMessage> messages;
  final ChatState chatState;
  final bool loading;
  final bool hasMore;
  final bool loadingMore;
  final AppFailure? loadError;

  ChatRoomState copyWith({
    List<ChatMessage>? messages,
    ChatState? chatState,
    bool? loading,
    bool? hasMore,
    bool? loadingMore,
    Object? loadError = _keep,
  }) =>
      ChatRoomState(
        messages: messages ?? this.messages,
        chatState: chatState ?? this.chatState,
        loading: loading ?? this.loading,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        loadError: identical(loadError, _keep) ? this.loadError : loadError as AppFailure?,
      );
}

const Object _keep = Object();

enum SendResult { queued, empty, tooLong, throttled, closed }

class ChatRoomController extends AutoDisposeFamilyNotifier<ChatRoomState, String> {
  late SendThrottle _throttle;
  Timer? _backfill;
  bool _disposed = false;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  String? get _uid => ref.read(authUserProvider).valueOrNull?.id;

  @override
  ChatRoomState build(String matchId) {
    _disposed = false; // the same notifier instance is reused on invalidate
    _throttle = SendThrottle(clock: ref.read(refreshClockProvider));
    final repo = ref.watch(chatRepositoryProvider);
    final sub = repo.incoming().listen(_onIncoming);
    _backfill = Timer.periodic(ref.read(chatBackfillIntervalProvider), (_) => unawaited(_backfillNow()));
    ref.onDispose(() {
      _disposed = true;
      _backfill?.cancel();
      unawaited(sub.cancel());
    });
    Future.microtask(load);
    return const ChatRoomState();
  }

  void _set(ChatRoomState s) {
    if (!_disposed) state = s;
  }

  Future<void> load() async {
    _set(state.copyWith(loading: true, loadError: null));
    final (stRes, histRes) = await (_repo.state(arg), _repo.history(arg)).wait;
    if (_disposed) return;
    AppFailure? err;
    var chatState = state.chatState;
    var page = const ChatPage(items: [], hasMore: false);
    if (stRes case Ok(:final value)) chatState = value;
    switch (histRes) {
      case Ok(:final value):
        page = value;
      case Err(:final failure):
        err = failure;
    }
    _set(state.copyWith(
      loading: false,
      loadError: err,
      chatState: chatState,
      messages: mergeMessages(state.messages, page.items),
      hasMore: page.hasMore,
    ));
    _markSeen();
  }

  Future<void> loadOlder() async {
    if (state.loadingMore || !state.hasMore) return;
    final first = state.messages.where((m) => m.status == SendStatus.sent).firstOrNull;
    if (first == null) return;
    _set(state.copyWith(loadingMore: true));
    final res = await _repo.history(arg, before: first.createdAt);
    res.when(
      ok: (p) => _set(state.copyWith(
        loadingMore: false,
        messages: mergeMessages(state.messages, p.items),
        hasMore: p.hasMore,
      )),
      err: (_) => _set(state.copyWith(loadingMore: false)),
    );
  }

  /// Re-reads `chat_state` (after a system message, a block, or a rejected send).
  Future<void> refreshState() async {
    final res = await _repo.state(arg);
    res.when(ok: (s) => _set(state.copyWith(chatState: s)), err: (_) {});
  }

  void _onIncoming(ChatMessage m) {
    if (m.matchId != arg) return;
    _set(state.copyWith(messages: mergeMessages(state.messages, [m])));
    if (m.isSystem) unawaited(refreshState());
    _markSeen();
    // US-48(B): read a recognised quick-voice preset aloud on THIS device only
    // (never for messages this device itself sent — checked inside).
    unawaited(maybeSpeakQuickVoice(ref, m, selfUserId: _uid));
  }

  Future<void> _backfillNow() async {
    final last = state.messages.where((m) => m.status == SendStatus.sent).lastOrNull;
    if (last == null || state.loading) return;
    final res = await _repo.since(arg, last.createdAt);
    res.when(
      ok: (l) {
        if (l.isNotEmpty) {
          _set(state.copyWith(messages: mergeMessages(state.messages, l)));
          if (l.any((m) => m.isSystem)) unawaited(refreshState());
          _markSeen();
        }
      },
      err: (_) {},
    );
  }

  void _markSeen() {
    final last = state.messages.where((m) => m.status == SendStatus.sent).lastOrNull;
    if (last != null) ref.read(chatLastSeenProvider.notifier).markSeen(arg, last.createdAt);
  }

  /// Seconds the user should wait when [SendResult.throttled] is returned.
  Duration get throttleWait => _throttle.retryAfter();

  SendResult send(String raw) {
    if (!state.chatState.canSend) return SendResult.closed;
    final body = raw.trim();
    final v = validateChatBody(raw);
    if (v == '') return SendResult.empty;
    if (v != null) return SendResult.tooLong;
    if (!_throttle.tryAcquire()) return SendResult.throttled;
    final clientId = _uuid.v4();
    final msg = ChatMessage(
      id: 'local-$clientId',
      matchId: arg,
      body: body,
      createdAt: DateTime.now(),
      senderId: _uid,
      clientMsgId: clientId,
      status: SendStatus.sending,
    );
    _set(state.copyWith(messages: mergeMessages(state.messages, [msg])));
    unawaited(_deliver(msg));
    return SendResult.queued;
  }

  /// Tap on a failed bubble: same `client_msg_id`, so it can never double-post.
  SendResult retry(String clientMsgId) {
    final m = state.messages.where((x) => x.clientMsgId == clientMsgId && x.status == SendStatus.failed).firstOrNull;
    if (m == null) return SendResult.empty;
    if (!state.chatState.canSend) return SendResult.closed;
    if (!_throttle.tryAcquire()) return SendResult.throttled;
    _replace(m.copyWith(status: SendStatus.sending));
    unawaited(_deliver(m));
    return SendResult.queued;
  }

  void _replace(ChatMessage m) =>
      _set(state.copyWith(messages: [for (final x in state.messages) x.clientMsgId == m.clientMsgId ? m : x]));

  Future<void> _deliver(ChatMessage msg) async {
    final res = await _repo.send(arg, msg.body, msg.clientMsgId!);
    if (_disposed) return;
    res.when(
      ok: (row) {
        _set(state.copyWith(messages: mergeMessages(state.messages, [row])));
        _markSeen();
      },
      err: (f) {
        _replace(msg.copyWith(status: SendStatus.failed));
        // RLS denial on insert: the chat closed under us; show read-only.
        if (f.code == FailureCode.forbiddenRls || f.code == 'GWM_FORBIDDEN') unawaited(refreshState());
      },
    );
  }
}

final chatRoomProvider =
    NotifierProvider.autoDispose.family<ChatRoomController, ChatRoomState, String>(ChatRoomController.new);

/// Latest message per accepted match, for the list preview and unread dots.
class ChatInboxController extends AsyncNotifier<Map<String, ChatMessage>> {
  @override
  Future<Map<String, ChatMessage>> build() async {
    final uid = ref.watch(authUserProvider.select((a) => a.valueOrNull?.id));
    if (uid == null) return const {};
    final joined = ref.watch(inboxProvider.select((a) => [
          for (final m in a.valueOrNull ?? const <MatchSummary>[])
            if (m.status == MatchStatus.accepted) m.id,
        ].join(',')));
    final ids = joined.isEmpty ? const <String>[] : joined.split(',');
    final repo = ref.watch(chatRepositoryProvider);
    final sub = repo.incoming().listen((m) {
      final cur = state.valueOrNull ?? const <String, ChatMessage>{};
      if (!cur.containsKey(m.matchId) && !ids.contains(m.matchId)) return;
      state = AsyncData({...cur, m.matchId: m});
    });
    ref.onDispose(sub.cancel);
    final out = <String, ChatMessage>{};
    for (final id in ids) {
      final r = await repo.latest(id);
      r.when(ok: (m) {
        if (m != null) out[id] = m;
      }, err: (_) {});
    }
    return out;
  }
}

final chatInboxProvider =
    AsyncNotifierProvider<ChatInboxController, Map<String, ChatMessage>>(ChatInboxController.new);

/// Match ids whose latest message is from the partner (or the system) and
/// newer than what this device last showed in the room.
final unreadMatchIdsProvider = Provider<Set<String>>((ref) {
  final uid = ref.watch(authUserProvider.select((a) => a.valueOrNull?.id));
  final latest = ref.watch(chatInboxProvider).valueOrNull ?? const <String, ChatMessage>{};
  final seen = ref.watch(chatLastSeenProvider);
  return {
    for (final e in latest.entries)
      if ((e.value.isSystem || e.value.senderId != uid) &&
          (seen[e.key] == null || e.value.createdAt.isAfter(seen[e.key]!)))
        e.key,
  };
});
