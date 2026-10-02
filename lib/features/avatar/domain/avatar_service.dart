import '../../../core/error/result.dart';
import '../../../core/net/throttle.dart' show Clock;
import 'avatar_repository.dart';

/// Short-lived cache in front of [AvatarRepository] so scrolling a list does not sign a URL per frame.
/// TTL stays below the signed URL lifetime (120 s); "no photo / not allowed" answers are cached for a
/// shorter time. Everything is dropped when a match changes state or the photo changes, so a photo never
/// outlives the right to see it (E-1 Cache rule).
class AvatarService {
  AvatarService(this.repo, {Clock? clock, this.urlTtl = const Duration(seconds: 90), this.emptyTtl = const Duration(seconds: 30)})
      : _clock = clock ?? DateTime.now;

  final AvatarRepository repo;
  final Clock _clock;
  final Duration urlTtl;
  final Duration emptyTtl;
  final _cache = <String, ({AvatarSource? src, DateTime at})>{};
  int repoCalls = 0;

  static const _mine = 'me';
  static String _key(String matchId) => 'match:$matchId';

  Future<AvatarSource?> _get(String key, Future<Result<AvatarSource?>> Function() load) async {
    final hit = _cache[key];
    if (hit != null) {
      final ttl = hit.src == null ? emptyTtl : urlTtl;
      if (_clock().difference(hit.at) < ttl) return hit.src;
    }
    repoCalls++;
    final res = await load();
    // A failure (offline...) is shown as initials but not cached: the next build retries.
    return res.when(
      ok: (s) {
        _cache[key] = (src: s, at: _clock());
        return s;
      },
      err: (_) => null,
    );
  }

  Future<AvatarSource?> mine() => _get(_mine, repo.mine);
  Future<AvatarSource?> partner(String matchId) => _get(_key(matchId), () => repo.partner(matchId));

  void evictMatch(String matchId) => _cache.remove(_key(matchId));
  void evictMine() => _cache.remove(_mine);
  void clear() => _cache.clear();
}
