import '../../../core/error/result.dart';
import 'chat_models.dart';

class ChatPage {
  const ChatPage({required this.items, required this.hasMore});

  /// Oldest first.
  final List<ChatMessage> items;
  final bool hasMore;
}

abstract class ChatRepository {
  Future<Result<ChatState>> state(String matchId);

  /// Newest [limit] messages older than [before] (keyset on `created_at`).
  Future<Result<ChatPage>> history(String matchId, {DateTime? before, int limit = 30});

  /// Messages newer than [after]; used to backfill after a Realtime gap.
  Future<Result<List<ChatMessage>>> since(String matchId, DateTime after);

  Future<Result<ChatMessage?>> latest(String matchId);

  /// Idempotent on [clientMsgId]: a retry never creates a second row and a
  /// duplicate is reported as success with the stored row (design-api 7.4).
  /// [kind] is the chat_messages.kind the sender may write ('user' or 'driver_arrived', RLS in 0011); the push trigger
  /// keys off it, so the "ถึงจุดรับแล้ว" message must pass 'driver_arrived' to produce that push (US-42 AC5).
  Future<Result<ChatMessage>> send(String matchId, String body, String clientMsgId, {String kind = 'user'});

  /// One app-wide Realtime channel for every chat row the caller may read
  /// (RLS filters it). Rooms filter by match id; keeps us at <= 2 channels.
  Stream<ChatMessage> incoming();
}
