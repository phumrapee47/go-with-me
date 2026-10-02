import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/app_failure.dart';
import '../../../core/error/error_mapper.dart';
import '../../../core/error/result.dart';
import '../domain/avatar_repository.dart';

/// Signed URLs live 120 s (server limit 300 s). Paths, URLs and bytes are never logged.
const avatarSignedUrlSeconds = 120;
const avatarBucket = 'avatars';

class SupabaseAvatarRepository implements AvatarRepository {
  SupabaseAvatarRepository(this._client);
  final sb.SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  Future<AvatarSource?> _sign(String? path) async {
    if (path == null || path.isEmpty) return null;
    final url = await _client.storage.from(avatarBucket).createSignedUrl(path, avatarSignedUrlSeconds);
    return AvatarSource.url(url);
  }

  @override
  Future<Result<AvatarSource?>> mine() async {
    final uid = _uid;
    if (uid == null) return const Ok(null);
    try {
      final row = await _client.from('profiles').select('avatar_path').eq('id', uid).maybeSingle();
      return Ok(await _sign(row?['avatar_path'] as String?));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<AvatarSource?>> partner(String matchId) async {
    try {
      final path = await _client.rpc('get_partner_avatar_path', params: {'p_match_id': matchId});
      return Ok(await _sign(path is String ? path : null));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> setMine(Uint8List jpeg) async {
    final uid = _uid;
    if (uid == null) return const Err(AppFailure('GWM_UNAUTHENTICATED'));
    final path = '$uid/avatar.jpg';
    try {
      await _client.storage.from(avatarBucket).uploadBinary(
            path,
            jpeg,
            fileOptions: const sb.FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      await _client.rpc('set_my_avatar', params: {'p_path': path});
      return const Ok(null);
    } on sb.StorageException catch (e) {
      final code = '${e.statusCode}';
      if (code == '413') return const Err(AppFailure(FailureCode.uploadTooLarge));
      if (code == '415') return const Err(AppFailure(FailureCode.uploadType));
      return Err(mapError(e));
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> removeMine() async {
    try {
      await _client.rpc('set_my_avatar', params: {'p_path': null});
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }

  @override
  Future<Result<void>> report(String matchId, AvatarReportReason reason) async {
    try {
      await _client.rpc('report_avatar', params: {'p_match_id': matchId, 'p_reason': reason.db});
      return const Ok(null);
    } catch (e) {
      return Err(mapError(e));
    }
  }
}
