import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../../../core/net/retry.dart';
import '../domain/chat_models.dart';
import '../domain/chat_repository.dart';

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this._client, {this.sleep});

  final sb.SupabaseClient _client;
  final Future<void> Function(Duration)? sleep;

  static const _cols = 'id,match_id,sender_id,kind,body,client_msg_id,created_at';

  @override
  Future<Result<ChatState>> state(String matchId) async {
    try {
      final res = await retryTransient(
        () => _client.rpc('chat_state', params: {'p_match_id': matchId}),
        sleep: sleep,
      );
      return Ok(ChatState.fromDb(res));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  List<ChatMessage> _parse(List<dynamic> rows) => [
        for (final r in rows)
          if (r is Map<String, dynamic>) ?ChatMessage.fromJson(r),
      ];

  @override
  Future<Result<ChatPage>> history(String matchId, {DateTime? before, int limit = 30}) async {
    try {
      final rows = await retryTransient(() {
        var q = _client.from('chat_messages').select(_cols).eq('match_id', matchId);
        if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
        // Fetch one extra row to know whether older history exists.
        return q.order('created_at', ascending: false).order('id', ascending: false).limit(limit + 1);
      }, sleep: sleep);
      final hasMore = rows.length > limit;
      final page = _parse(hasMore ? rows.take(limit).toList() : rows).reversed.toList();
      return Ok(ChatPage(items: page, hasMore: hasMore));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<List<ChatMessage>>> since(String matchId, DateTime after) async {
    try {
      final rows = await retryTransient(
        () => _client
            .from('chat_messages')
            .select(_cols)
            .eq('match_id', matchId)
            .gt('created_at', after.toUtc().toIso8601String())
            .order('created_at', ascending: true)
            .limit(100),
        sleep: sleep,
      );
      return Ok(_parse(rows));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<ChatMessage?>> latest(String matchId) async {
    try {
      final rows = await retryTransient(
        () => _client
            .from('chat_messages')
            .select(_cols)
            .eq('match_id', matchId)
            .order('created_at', ascending: false)
            .limit(1),
        sleep: sleep,
      );
      final l = _parse(rows);
      return Ok(l.isEmpty ? null : l.first);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  Future<ChatMessage?> _byClientId(String clientMsgId) async {
    final row = await _client
        .from('chat_messages')
        .select(_cols)
        .eq('client_msg_id', clientMsgId)
        .maybeSingle();
    return row == null ? null : ChatMessage.fromJson(row);
  }

  @override
  Future<Result<ChatMessage>> send(String matchId, String body, String clientMsgId, {String kind = 'user'}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    try {
      // Safe to retry: (sender_id, client_msg_id) is unique.
      await retryTransient(
        () => _client.from('chat_messages').insert({
          'match_id': matchId,
          'sender_id': uid,
          'body': body,
          'client_msg_id': clientMsgId,
          if (kind != 'user') 'kind': kind,
        }),
        sleep: sleep,
      );
    } catch (e) {
      final f = mapError(e);
      // 23505 on the client id = an earlier attempt already stored it: success.
      if (f.code != FailureCode.duplicate) return Err(f);
    }
    try {
      final m = await _byClientId(clientMsgId);
      if (m == null) return const Err(AppFailure(FailureCode.unknown));
      return Ok(m);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Stream<ChatMessage> incoming() {
    late final StreamController<ChatMessage> ctrl;
    sb.RealtimeChannel? channel;
    ctrl = StreamController<ChatMessage>.broadcast(
      onListen: () {
        channel = _client
            .channel('chat:inbox:${_client.auth.currentUser?.id}')
            .onPostgresChanges(
              event: sb.PostgresChangeEvent.insert,
              schema: 'public',
              table: 'chat_messages',
              callback: (payload) {
                final m = ChatMessage.fromJson(payload.newRecord);
                if (m != null) ctrl.add(m);
              },
            )
          ..subscribe();
      },
      onCancel: () async {
        final ch = channel;
        if (ch != null) await _client.removeChannel(ch);
      },
    );
    return ctrl.stream;
  }
}
